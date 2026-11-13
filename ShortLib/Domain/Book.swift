import Foundation

struct Book: Identifiable, Codable, Hashable {
    let id: UUID
    var title: String
    var author: String
    var source: BookSource
    var genre: Genre
    var language: String
    var chapters: [Chapter]
    var coverStyle: Int
    var summary: Summary?
    /// Пересказ в процессе: готовые главы и «память сюжета». Удаляется, когда готов полный `summary`.
    var partialSummary: PartialSummary?
    var addedAt: Date

    init(id: UUID = UUID(),
         title: String,
         author: String,
         source: BookSource,
         genre: Genre = .other,
         language: String = "—",
         chapters: [Chapter],
         coverStyle: Int = Int.random(in: 0..<4),
         summary: Summary? = nil,
         partialSummary: PartialSummary? = nil,
         addedAt: Date = Date()) {
        self.id = id
        self.title = title
        self.author = author
        self.source = source
        self.genre = genre
        self.language = language
        self.chapters = chapters
        self.coverStyle = coverStyle
        self.summary = summary
        self.partialSummary = partialSummary
        self.addedAt = addedAt
    }

    var wordCount: Int { chapters.reduce(0) { $0 + $1.wordCount } }

    func wordCount(in range: ClosedRange<Int>) -> Int {
        chapters.filter { range.contains($0.index) }.reduce(0) { $0 + $1.wordCount }
    }

    /// Оценка для глав без загруженного текста (веб-новеллы до загрузки).
    func estimatedWordCount(in range: ClosedRange<Int>) -> Int {
        let known = wordCount(in: range)
        return known > 0 ? known : range.count * 3_000
    }

    var chapterRange: ClosedRange<Int> { 1...max(1, chapters.count) }
}

enum BookSource: Codable, Hashable {
    case epub(fileName: String)
    case web(url: URL)

    var kindTitle: String {
        switch self {
        case .epub: return "EPUB"
        case .web: return "Веб-новелла"
        }
    }

    var hostTitle: String {
        switch self {
        case .epub(let name): return name
        case .web(let url): return url.host ?? url.absoluteString
        }
    }
}

enum Genre: String, Codable, CaseIterable, Identifiable {
    case fantasy, novel, classic, nonfiction, other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fantasy: return "Фэнтези"
        case .novel: return "Новеллы"
        case .classic: return "Классика"
        case .nonfiction: return "Нон-фикшн"
        case .other: return "Другое"
        }
    }

    var systemImage: String {
        switch self {
        case .fantasy: return "wand.and.stars"
        case .novel: return "globe"
        case .classic: return "building.columns"
        case .nonfiction: return "lightbulb"
        case .other: return "book"
        }
    }
}
