import Foundation

struct ChapterLink: Hashable {
    let title: String
    let url: URL
}

struct WebNovelPreview: Equatable {
    let title: String
    let links: [ChapterLink]
    let sourceURL: URL
}

protocol WebNovelScraping {
    func fetchPreview(from url: URL) async throws -> WebNovelPreview
    func fetchChapterText(_ url: URL) async throws -> String
}

/// Универсальный парсер оглавления: ищет ссылки, похожие на главы.
/// Для популярных сайтов можно добавить свои правила (SiteRule) без изменения ViewModel.
struct WebNovelScraper: WebNovelScraping {
    enum ScrapeError: LocalizedError {
        case badResponse(Int), noChapters
        var errorDescription: String? {
            switch self {
            case .badResponse(let code): return "Сайт ответил ошибкой \(code). Проверьте ссылку."
            case .noChapters: return "На странице не нашли список глав. Нужна ссылка именно на оглавление."
            }
        }
    }

    private let session: URLSession

    init(session: URLSession = .shared) { self.session = session }

    func fetchPreview(from url: URL) async throws -> WebNovelPreview {
        let html = try await load(url)
        let links = Self.extractChapterLinks(html: html, base: url)
        guard !links.isEmpty else { throw ScrapeError.noChapters }
        let rawTitle = HTMLText.firstMatch(#"(?is)<h1[^>]*>(.*?)</h1>"#, in: html)
            ?? HTMLText.firstMatch(#"(?is)<title[^>]*>(.*?)</title>"#, in: html) ?? url.host ?? "Новелла"
        return WebNovelPreview(title: HTMLText.plainText(from: rawTitle), links: links, sourceURL: url)
    }

    func fetchChapterText(_ url: URL) async throws -> String {
        let html = try await load(url)
        // Берём самый «плотный» блок с абзацами.
        let paragraphs = Self.matches(#"(?is)<p[^>]*>(.*?)</p>"#, in: html)
            .map(HTMLText.plainText(from:))
            .filter { $0.count > 30 }
        return paragraphs.isEmpty ? HTMLText.plainText(from: html) : paragraphs.joined(separator: "\n\n")
    }

    // MARK: - Parsing

    static func extractChapterLinks(html: String, base: URL) -> [ChapterLink] {
        guard let re = try? NSRegularExpression(pattern: #"(?is)<a\s[^>]*href\s*=\s*["']([^"'#]+)["'][^>]*>(.*?)</a>"#) else { return [] }
        let ns = html as NSString
        let chapterHint = try? NSRegularExpression(pattern: #"(?i)(chapter|глава|ch[-_.]?\d|/c\d+|episode|часть)"#)
        var seen = Set<URL>()
        var result: [ChapterLink] = []

        for m in re.matches(in: html, range: NSRange(location: 0, length: ns.length)) {
            let href = ns.substring(with: m.range(at: 1))
            let title = HTMLText.plainText(from: ns.substring(with: m.range(at: 2)))
            guard let url = URL(string: href, relativeTo: base)?.absoluteURL,
                  url.host == base.host, !seen.contains(url) else { continue }
            let probe = href + " " + title
            guard chapterHint?.firstMatch(in: probe, range: NSRange(probe.startIndex..., in: probe)) != nil else { continue }
            seen.insert(url)
            result.append(ChapterLink(title: title.isEmpty ? "Глава \(result.count + 1)" : title, url: url))
        }
        return result
    }

    private static func matches(_ pattern: String, in text: String) -> [String] {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = text as NSString
        return re.matches(in: text, range: NSRange(location: 0, length: ns.length)).map { ns.substring(with: $0.range(at: 1)) }
    }

    private func load(_ url: URL) async throws -> String {
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X) ShortLib/1.0", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw ScrapeError.badResponse(http.statusCode)
        }
        return String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
    }
}
