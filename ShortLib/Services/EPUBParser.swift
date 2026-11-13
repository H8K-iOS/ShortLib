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
        // Страницы, которые сама книга помечает как служебные: nav (EPUB 3) и guide (EPUB 2).
        let servicePaths = Set((opf.navHrefs + opf.serviceGuideHrefs).map { Self.resolve($0, base: baseDir) })
        var chapters: [Chapter] = []

        for idref in opf.spine {
            guard let href = opf.manifest[idref] else { continue }
            let path = Self.resolve(href, base: baseDir)
            guard !servicePaths.contains(path), let raw = try? zip.data(at: path) else { continue }
            let html = String(decoding: raw, as: UTF8.self)
            let text = HTMLText.plainText(from: html)
            guard text.split(whereSeparator: { $0.isWhitespace }).count > 40 else { continue } // обложки, титулы, разделители частей
            let headingLines = Self.headingLines(in: html)
            guard !Self.isServicePage(text: text, html: html, headingLines: headingLines) else { continue }
            let title = Self.chapterTitle(from: headingLines) ?? "Глава \(chapters.count + 1)"
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

    // MARK: - Служебные страницы

    /// Заголовки страниц, которые не являются главами книги.
    private static let serviceTitle = #"(?i)^(annotation|аннотация|содержание|оглавление|contents|table of contents|"#
        + #"copyright|информация об издании|сведения об издании|от издательства|выходные данные|"#
        + #"примечания|комментарии|notes|footnotes|endnotes)[.:]?$"#

    /// Строка вида «Глава 5», «Chapter V», «Часть первая», «Эпилог» — так выглядят пункты оглавления.
    private static let chapterListLine = #"(?i)^(глава|гл\.|часть|chapter|part|пролог|эпилог|prologue|epilogue)(\s|$)"#

    /// Аннотация, оглавление, выходные данные и т. п.
    static func isServicePage(text: String, html: String, headingLines: [String]) -> Bool {
        // 1. Заголовок или первая строка — служебные.
        let firstLine = text.split(separator: "\n", omittingEmptySubsequences: true).first.map(String.init) ?? ""
        for candidate in [headingLines.first ?? "", firstLine] {
            let clean = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            if !clean.isEmpty, HTMLText.firstMatch("(" + serviceTitle + ")", in: clean) != nil { return true }
        }

        // 2. Больше половины абзацев — пункты списка глав.
        let lines = text.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let listLines = lines.filter { line in
            line.split(separator: " ").count <= 12 && HTMLText.firstMatch("(" + chapterListLine + ")", in: line) != nil
        }
        if listLines.count >= 3, Double(listLines.count) >= Double(lines.count) * 0.5 { return true }

        // 3. Больше половины текста — ссылки (оглавление со ссылками на главы).
        let linkWords = HTMLText.allMatches(#"(?is)<a\b[^>]*>(.*?)</a>"#, in: html)
            .map { HTMLText.plainText(from: $0).split(whereSeparator: { $0.isWhitespace }).count }
            .reduce(0, +)
        let totalWords = text.split(whereSeparator: { $0.isWhitespace }).count
        return totalWords > 0 && Double(linkWords) > Double(totalWords) * 0.5
    }

    // MARK: - Название главы

    /// Строки первых двух заголовков страницы (h1–h3), по порядку.
    static func headingLines(in html: String) -> [String] {
        HTMLText.allMatches(#"(?is)<h[1-3][^>]*>(.*?)</h[1-3]>"#, in: html)
            .prefix(2)
            .flatMap { HTMLText.plainText(from: $0).components(separatedBy: "\n") }
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// «Глава 1» + «Никогда не разговаривайте с неизвестными» → «Никогда не разговаривайте с неизвестными».
    /// Номер главы приложение показывает само, поэтому из названия он убирается.
    static func chapterTitle(from allLines: [String]) -> String? {
        // «Часть первая» над «Главой 1» — это раздел, а не название главы.
        var lines = allLines
        while lines.count > 1, HTMLText.firstMatch(#"((?i)^(часть|part|книга|book)(\s|$))"#, in: lines[0]) != nil {
            lines.removeFirst()
        }
        guard let first = lines.first else { return nil }
        guard let rest = stripChapterNumber(first) else { return first }
        if !rest.isEmpty { return rest }
        // Номер и название в разных строках или заголовках.
        if lines.count > 1, stripChapterNumber(lines[1]) == nil { return lines[1] }
        return first
    }

    /// Если строка начинается с «Глава N» / «Chapter N», возвращает то, что после номера; иначе nil.
    static func stripChapterNumber(_ line: String) -> String? {
        let ordinal = #"(перв|втор|трет|четв[её]рт|пят|шест|седьм|восьм|девят|десят)[а-яё]*"#
        let pattern = #"(?i)^(?:глава|гл\.|chapter)\s*(?:\d+|(?-i:[IVXLCDM]+)|"# + ordinal + #")\b\s*[.:—–-]?\s*(.*)$"#
        guard let re = try? NSRegularExpression(pattern: pattern),
              let m = re.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
              let r = Range(m.range(at: m.numberOfRanges - 1), in: line) else { return nil }
        return String(line[r]).trimmingCharacters(in: .whitespaces)
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
    /// Документ навигации EPUB 3 (`properties="nav"`).
    private(set) var navHrefs: [String] = []
    /// Служебные страницы из `<guide>` EPUB 2: оглавление, обложка, титул, выходные данные.
    private(set) var serviceGuideHrefs: [String] = []

    private static let serviceGuideTypes: Set<String> = ["toc", "cover", "title-page", "copyright-page", "colophon"]

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
            if let id = attributes["id"], let href = attributes["href"] {
                manifest[id] = href
                if attributes["properties"]?.split(separator: " ").contains("nav") == true { navHrefs.append(href) }
            }
        case "reference":
            if let type = attributes["type"]?.lowercased(), Self.serviceGuideTypes.contains(type),
               let href = attributes["href"] {
                serviceGuideHrefs.append(href)
            }
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
