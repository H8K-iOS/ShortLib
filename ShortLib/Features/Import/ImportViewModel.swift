import Foundation

@MainActor
final class ImportViewModel: ObservableObject {
    enum SourceKind { case epub, web }

    enum State: Equatable {
        case idle
        case loading(String)
        case preview(WebNovelPreview)
        case failed(String)
    }

    @Published var kind: SourceKind = .web
    @Published var urlText = ""
    @Published private(set) var state: State = .idle

    var onClose: (() -> Void)?
    var onPickFile: (() -> Void)?
    var onImported: ((Book) -> Void)?

    private let epubParser: EPUBParsing
    private let scraper: WebNovelScraping
    private var task: Task<Void, Never>?

    init(epubParser: EPUBParsing, scraper: WebNovelScraping) {
        self.epubParser = epubParser
        self.scraper = scraper
    }

    var isLoading: Bool { if case .loading = state { return true } else { return false } }

    var primaryTitle: String {
        switch (kind, state) {
        case (.epub, _): return "Выбрать файл"
        case (.web, .preview): return "Добавить в библиотеку"
        case (.web, _): return "Найти главы"
        }
    }

    var canContinue: Bool {
        guard !isLoading else { return false }
        return kind == .epub || normalizedURL != nil
    }

    func select(_ kind: SourceKind) {
        self.kind = kind
        if case .failed = state { state = .idle }
    }

    func primaryAction() {
        switch (kind, state) {
        case (.epub, _): onPickFile?()
        case (.web, .preview(let preview)): addWebNovel(preview)
        case (.web, _): findChapters()
        }
    }

    func urlChanged() {
        if case .preview = state { state = .idle }
        if case .failed = state { state = .idle }
    }

    func close() {
        task?.cancel()
        onClose?()
    }

    // MARK: - EPUB

    func importEPUB(from url: URL) {
        state = .loading("Читаем книгу…")
        task = Task { [weak self, epubParser] in
            do {
                var book = try await epubParser.parse(fileAt: url)
                book.genre = .other
                self?.state = .idle
                self?.onImported?(book)
            } catch {
                self?.state = .failed(error.localizedDescription)
            }
        }
    }

    // MARK: - Web

    private var normalizedURL: URL? {
        var text = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if !text.lowercased().hasPrefix("http") { text = "https://" + text }
        guard let url = URL(string: text), url.host != nil else { return nil }
        return url
    }

    private func findChapters() {
        guard let url = normalizedURL else {
            state = .failed("Ссылка выглядит неверно. Скопируйте адрес страницы с оглавлением целиком.")
            return
        }
        state = .loading("Ищем главы на странице…")
        task = Task { [weak self, scraper] in
            do {
                let preview = try await scraper.fetchPreview(from: url)
                self?.state = .preview(preview)
            } catch {
                self?.state = .failed(error.localizedDescription)
            }
        }
    }

    private func addWebNovel(_ preview: WebNovelPreview) {
        let chapters = preview.links.enumerated().map { i, link in
            Chapter(index: i + 1, title: link.title, text: "", url: link.url)
        }
        let book = Book(title: preview.title,
                        author: preview.sourceURL.host ?? "Веб-новелла",
                        source: .web(url: preview.sourceURL),
                        genre: .novel,
                        chapters: chapters)
        onImported?(book)
    }
}
