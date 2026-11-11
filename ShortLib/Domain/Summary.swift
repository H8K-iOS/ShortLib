import Foundation

enum DetailLevel: String, Codable, CaseIterable, Identifiable {
    case brief, balanced, detailed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .brief: return "Кратко"
        case .balanced: return "Баланс"
        case .detailed: return "Подробно"
        }
    }

    /// Доля от исходного объёма.
    var defaultRatio: Double {
        switch self {
        case .brief: return 0.04
        case .balanced: return 0.08
        case .detailed: return 0.15
        }
    }

    static let ratioRange: ClosedRange<Double> = 0.03...0.25

    static func nearest(to ratio: Double) -> DetailLevel {
        allCases.min { abs($0.defaultRatio - ratio) < abs($1.defaultRatio - ratio) } ?? .balanced
    }
}

enum SummaryFocus: String, Codable, CaseIterable, Identifiable, Hashable {
    case plot, characters, world, quotes

    var id: String { rawValue }

    var title: String {
        switch self {
        case .plot: return "Сюжет"
        case .characters: return "Персонажи"
        case .world: return "Мир и магия"
        case .quotes: return "Цитаты"
        }
    }
}

struct SummaryPreset: Codable, Hashable {
    var level: DetailLevel = .balanced
    var ratio: Double = DetailLevel.balanced.defaultRatio
    var focus: Set<SummaryFocus> = [.plot, .characters]
    var noSpoilers = true
    var chapterRange: ClosedRange<Int>

    /// Скорость чтения, слов в минуту.
    static let readingSpeed = 230.0

    func estimatedMinutes(for book: Book) -> Int {
        let words = Double(book.estimatedWordCount(in: chapterRange)) * ratio
        return max(1, Int((words / Self.readingSpeed).rounded()))
    }
}

struct ChapterSummary: Identifiable, Codable, Hashable {
    let index: Int
    let title: String
    let text: String
    var id: Int { index }
}

struct Summary: Codable, Hashable {
    let preset: SummaryPreset
    let overview: String
    let chapters: [ChapterSummary]
    let createdAt: Date

    var wordCount: Int {
        chapters.reduce(overview.split(separator: " ").count) { $0 + $1.text.split(separator: " ").count }
    }

    var readingMinutes: Int { max(1, Int((Double(wordCount) / SummaryPreset.readingSpeed).rounded())) }
}

struct SummaryProgress: Equatable {
    enum Stage: Int, CaseIterable {
        case loading, cleaning, summarizing, overview

        var title: String {
            switch self {
            case .loading: return "Загрузка глав"
            case .cleaning: return "Очистка текста"
            case .summarizing: return "Пересказ по главам"
            case .overview: return "Общая сводка"
            }
        }
    }

    var stage: Stage
    var done: Int
    var total: Int

    var fraction: Double {
        let inner = total > 0 ? Double(done) / Double(total) : 0
        // Вес этапа суммаризации больше остальных.
        switch stage {
        case .loading: return 0.15 * inner
        case .cleaning: return 0.15 + 0.05 * inner
        case .summarizing: return 0.2 + 0.7 * inner
        case .overview: return min(1, 0.9 + 0.1 * inner)
        }
    }
}
