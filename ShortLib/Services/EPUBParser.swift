import Foundation

protocol EPUBParsing {
    func parse(fileAt url: URL) async throws -> Book
}

/// Разбирает EPUB 2/3: container.xml → OPF (метаданные, manifest, spine) → XHTML глав.
struct EPUBParser: EPUBParsing {
    enum ParseError: LocalizedError {
        case noPackage, emptyBook
        var errorDescription: String? {
            switch self {
            case .noPackage: return "Не нашли описание книги внутри EPUB."
            case .emptyBook: return "В книге нет глав с текстом."
            }
        }
    }

    func parse(fileAt url: URL) async throws -> Book {
        try await Task.detached(priority: .userInitiated) {
            try parseSync(url)
        }.value
    }

    private func parseSync(_ url: URL) throws -> Book {
        let zip = try ZipReader(url: url)

        let container = String(decoding: try zip.data(at: "META-INF/container.xml"), as: UTF8.self)
        guard let opfPath = HTMLText.firstMatch(#"full-path="([^"]+)""#, in: container) else { throw ParseError.noPackage }
        let baseDir = (opfPath as NSString).deletingLastPathComponent

        let opf = OPFParser(data: try zip.data(at: opfPath))
        var chapters: [Chapter] = []

        for idref in opf.spine {
            guard let href = opf.manifest[idref] else { continue }
            let path = Self.resolve(href, base: baseDir)
            guard let raw = try? zip.data(at: path) else { continue }
            let html = String(decoding: raw, as: UTF8.self)
            let text = HTMLText.plainText(from: html)
            guard text.split(separator: " ").count > 40 else { continue } // пропускаем обложки, оглавления
            let heading = HTMLText.firstMatch(#"(?is)<h[1-3][^>]*>(.*?)</h[1-3]>"#, in: html)
                .map(HTMLText.plainText(from:))
            let title = (heading?.isEmpty == false ? heading! : "Глава \(chapters.count + 1)")
            chapters.append(Chapter(index: chapters.count + 1, title: title, text: text))
        }

        guard !chapters.isEmpty else { throw ParseError.emptyBook }

        return Book(
            title: opf.title ?? url.deletingPathExtension().lastPathComponent,
            author: opf.author ?? "Автор неизвестен",
            source: .epub(fileName: url.lastPathComponent),
            genre: .other,
            language: (opf.language ?? "—").uppercased(),
            chapters: chapters
        )
    }

    static func resolve(_ href: String, base: String) -> String {
        let clean = (href.removingPercentEncoding ?? href).components(separatedBy: "#")[0]
        let joined = base.isEmpty ? clean : base + "/" + clean
        var parts: [String] = []
        for p in joined.split(separator: "/") {
            if p == ".." { _ = parts.popLast() } else if p != "." { parts.append(String(p)) }
        }
        return parts.joined(separator: "/")
    }
}

/// SAX-разбор OPF через Foundation XMLParser.
private final class OPFParser: NSObject, XMLParserDelegate {
    private(set) var title: String?
    private(set) var author: String?
    private(set) var language: String?
    private(set) var manifest: [String: String] = [:]
    private(set) var spine: [String] = []

    private var current = ""
    private var buffer = ""

    init(data: Data) {
        super.init()
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = true
        parser.delegate = self
        parser.parse()
    }

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                qualifiedName: String?, attributes: [String: String] = [:]) {
        current = name
        buffer = ""
        switch name {
        case "item":
            if let id = attributes["id"], let href = attributes["href"] { manifest[id] = href }
        case "itemref":
            if let idref = attributes["idref"], attributes["linear"] != "no" { spine.append(idref) }
        default: break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) { buffer += string }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        let value = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        switch name {
        case "title" where title == nil: title = value
        case "creator" where author == nil: author = value
        case "language" where language == nil: language = value
        default: break
        }
    }
}
