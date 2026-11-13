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

    /// Доля от исходного объёма по умолчанию (позиция ползунка).
    var defaultRatio: Double {
        switch self {
        case .brief: return 0.06
        case .balanced: return 0.12
        case .detailed: return 0.20
        }
    }

    /// Границы длины пересказа одной главы в словах. Доля из ползунка сдвигает длину внутри них.
    var wordRange: ClosedRange<Int> {
        switch self {
        case .brief: return 200...400
        case .balanced: return 400...700
        case .detailed: return 700...900
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

enum SummaryLanguage: String, Codable, CaseIterable, Identifiable {
    case russian, original

    var id: String { rawValue }
    var title: String { self == .russian ? "Русский" : "Как в оригинале" }
}

struct SummaryPreset: Codable, Hashable {
    var level: DetailLevel = .balanced
    var ratio: Double = DetailLevel.balanced.defaultRatio
    var focus: Set<SummaryFocus> = [.plot, .characters]
    var noSpoilers = true
    var chapterRange: ClosedRange<Int>
    var language: SummaryLanguage = .russian

    init(level: DetailLevel = .balanced,
         ratio: Double = DetailLevel.balanced.defaultRatio,
         focus: Set<SummaryFocus> = [.plot, .characters],
         noSpoilers: Bool = true,
         chapterRange: ClosedRange<Int>,
         language: SummaryLanguage = .russian) {
        self.level = level
        self.ratio = ratio
        self.focus = focus
        self.noSpoilers = noSpoilers
        self.chapterRange = chapterRange
        self.language = language
    }

    /// Новые поля читаются через decodeIfPresent, чтобы старые сохранённые пересказы не ломали библиотеку.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        level = try c.decodeIfPresent(DetailLevel.self, forKey: .level) ?? .balanced
        ratio = try c.decodeIfPresent(Double.self, forKey: .ratio) ?? level.defaultRatio
        focus = try c.decodeIfPresent(Set<SummaryFocus>.self, forKey: .focus) ?? [.plot, .characters]
        noSpoilers = try c.decodeIfPresent(Bool.self, forKey: .noSpoilers) ?? true
        chapterRange = try c.decode(ClosedRange<Int>.self, forKey: .chapterRange)
        language = try c.decodeIfPresent(SummaryLanguage.self, forKey: .language) ?? .russian
    }

    /// Скорость чтения, слов в минуту.
    static let readingSpeed = 230.0

    func estimatedMinutes(for book: Book) -> Int {
        let chapters = book.chapters.filter { chapterRange.contains($0.index) }
        let words = chapters.isEmpty
            ? Double(book.estimatedWordCount(in: chapterRange)) * ratio
            : Double(chapters.map { targetWords(forChapterWords: $0.isLoaded ? $0.wordCount : 3_000) }.reduce(0, +))
        return max(1, Int((words / Self.readingSpeed).rounded()))
    }

    /// Пересказ не длиннее этой доли главы — иначе на коротких главах (веб-новеллы) нет сжатия.
    static let maxChapterShare = 0.35

    /// Целевая длина пересказа одной главы в словах:
    /// доля главы, зажатая в диапазон уровня, но не больше 35% самой главы.
    func targetWords(forChapterWords words: Int) -> Int {
        let range = level.wordRange
        let proportional = Int(Double(words) * ratio)
        let clamped = min(range.upperBound, max(range.lowerBound, proportional))
        let capped = min(clamped, Int(Double(words) * Self.maxChapterShare))
        return max(40, capped)
    }
}

struct ChapterSummary: Identifiable, Codable, Hashable {
    let index: Int
    let title: String
    let text: String
    /// Связи с другими главами («это объяснится в гл. 12»). Только если спойлеры разрешены.
    var connections: String? = nil
    var id: Int { index }
}

/// Частично готовый пересказ: главы по порядку от начала диапазона, без пропусков.
/// Нужен, чтобы читать готовые главы во время пересказа и продолжить его после перезапуска.
struct PartialSummary: Codable, Hashable, Sendable {
    let preset: SummaryPreset
    /// Готовые главы строго по порядку, начиная с `preset.chapterRange.lowerBound`.
    let chapters: [ChapterSummary]
    /// «Память сюжета» после последней готовой главы — с ней движок продолжит со следующей.
    let memory: String
    let updatedAt: Date

    /// Индекс следующей главы, которую нужно пересказать.
    var nextChapterIndex: Int { (chapters.last?.index ?? preset.chapterRange.lowerBound - 1) + 1 }
}

struct CharacterNote: Identifiable, Codable, Hashable {
    let name: String
    let note: String
    var id: String { name }
}

struct Summary: Codable, Hashable {
    let preset: SummaryPreset
    let overview: String
    let chapters: [ChapterSummary]
    let createdAt: Date
    /// Главные персонажи (только у пересказа через языковую модель).
    var characters: [CharacterNote]? = nil
    /// Чем сделан пересказ: «Claude · Haiku» или «Ключевые фразы».
    var engine: String? = nil

    var wordCount: Int {
        chapters.reduce(overview.split(separator: " ").count) { $0 + $1.text.split(separator: " ").count }
    }

    var readingMinutes: Int { max(1, Int((Double(wordCount) / SummaryPreset.readingSpeed).rounded())) }
}

struct SummaryProgress: Equatable {
    enum Stage: Int, CaseIterable {
        case loading, cleaning, summarizing, connecting, overview

        var title: String {
            switch self {
            case .loading: return "Загрузка глав"
            case .cleaning: return "Очистка текста"
            case .summarizing: return "Пересказ по главам"
            case .connecting: return "Связи между главами"
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
        case .summarizing: return 0.2 + 0.6 * inner
        case .connecting: return 0.8 + 0.1 * inner
        case .overview: return min(1, 0.9 + 0.1 * inner)
        }
    }
}
