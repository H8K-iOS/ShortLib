import Foundation

@MainActor
final class SummarySettingsViewModel: ObservableObject {
    /// Чем будет сделан пересказ — от этого зависит, что показывает экран.
    enum Access: Equatable {
        /// Свой ключ Claude API.
        case ownKey
        /// Бесплатно через сервер ShortLib: осталось `chaptersLeft` глав.
        case free(chaptersLeft: Int)
        /// Бесплатные главы закончились — остаются ключевые фразы, свой ключ или подписка.
        case limitReached
        /// Ни ключа, ни бесплатного лимита — ключевые фразы.
        case extractive
    }

    @Published var level: DetailLevel
    @Published var ratio: Double
    @Published var focus: Set<SummaryFocus>
    @Published var noSpoilers: Bool
    @Published var lastChapter: Int

    var onCreate: ((SummaryPreset) -> Void)?
    var onClose: (() -> Void)?
    /// Открыть Профиль, чтобы добавить свой ключ.
    var onAddKey: (() -> Void)?

    let book: Book
    let access: Access
    private let defaultLevel: DetailLevel
    private let language: SummaryLanguage

    /// Бесплатный лимит — 5 глав на устройство.
    static let freeChapterLimit = 5

    init(book: Book, defaults: Preferences, usesLanguageModel: Bool,
         freeChaptersLeft: Int? = nil, freeLimitReached: Bool = false) {
        self.book = book
        if let left = freeChaptersLeft {
            access = .free(chaptersLeft: max(1, min(left, Self.freeChapterLimit)))
        } else if usesLanguageModel {
            access = .ownKey
        } else {
            access = freeLimitReached ? .limitReached : .extractive
        }
        language = defaults.summaryLanguage
        let start = book.summary?.preset
        defaultLevel = defaults.defaultDetailLevel
        level = start?.level ?? defaultLevel
        ratio = start?.ratio ?? defaultLevel.defaultRatio
        focus = start?.focus ?? [.plot, .characters]
        noSpoilers = start?.noSpoilers ?? true
        lastChapter = start?.chapterRange.upperBound ?? book.chapters.count
        lastChapter = min(lastChapter, maxSelectableChapter)
    }

    // MARK: - Режим

    var usesLanguageModel: Bool {
        switch access {
        case .ownKey, .free: return true
        case .limitReached, .extractive: return false
        }
    }

    var isFreeMode: Bool { if case .free = access { return true } else { return false } }
    var isLimitReached: Bool { access == .limitReached }

    /// Остаток бесплатных глав для плашки; `nil` — не бесплатный режим.
    var freeChaptersLeft: Int? { if case .free(let left) = access { return left } else { return nil } }

    var engineTitle: String {
        switch access {
        case .ownKey: return "Пересказ своими словами · Claude"
        case .free: return "Пересказ своими словами · бесплатно"
        case .limitReached, .extractive: return "Ключевые фразы"
        }
    }

    var engineDetail: String {
        switch access {
        case .ownKey: return SummaryCostEstimate(book: book, preset: preset).text
        case .free: return "Быстрая модель Claude Haiku. Бесплатные главы даются один раз на устройство."
        case .limitReached, .extractive: return "Это выдержки из текста, а не пересказ: без связей между главами и памяти сюжета."
        }
    }

    /// Ссылка «Добавить ключ» в карточке режима — только для ключевых фраз.
    var showsAddKeyLink: Bool { access == .extractive }

    // MARK: - Главы

    var chapterCount: Int { book.chapters.count }
    /// Сколько глав можно выбрать: все или бесплатный остаток.
    var maxSelectableChapter: Int { max(1, min(chapterCount, freeChaptersLeft ?? chapterCount)) }
    var isChapterLimited: Bool { maxSelectableChapter < chapterCount }
    var isAllChapters: Bool { lastChapter == chapterCount }

    /// Подсказка под выбором глав в бесплатном режиме.
    var chapterHint: String? {
        guard isChapterLimited else { return nil }
        return "Без ключа — до \(RussianPlural.chapters(maxSelectableChapter)). Со своим ключом можно всю книгу."
    }

    var preset: SummaryPreset {
        SummaryPreset(level: level, ratio: ratio, focus: focus, noSpoilers: noSpoilers,
                      chapterRange: 1...max(1, min(lastChapter, maxSelectableChapter)), language: language)
    }

    var estimateText: String {
        "≈ \(preset.estimatedMinutes(for: book)) мин чтения · главы 1–\(preset.chapterRange.upperBound)"
    }

    var spoilerDetail: String {
        noSpoilers ? "Пересказ не заглядывает дальше выбранной главы"
                   : "Добавим связи с будущими главами: что подготовлено и что раскроется позже"
    }

    // MARK: - Главная кнопка

    var createTitle: String {
        switch access {
        case .ownKey: return "Создать пересказ"
        case .free: return "Пересказать \(RussianPlural.chapters(preset.chapterRange.upperBound))"
        case .limitReached, .extractive: return "Собрать ключевые фразы"
        }
    }

    // MARK: - Действия

    func toggle(_ item: SummaryFocus) {
        if focus.contains(item) {
            guard focus.count > 1 else { return } // хотя бы один фокус
            focus.remove(item)
        } else {
            focus.insert(item)
        }
    }

    func selectAllChapters() { lastChapter = maxSelectableChapter }

    func reset() {
        level = defaultLevel
        ratio = defaultLevel.defaultRatio
        focus = [.plot, .characters]
        noSpoilers = true
        lastChapter = maxSelectableChapter
    }

    func create() { onCreate?(preset) }
    func close() { onClose?() }
    func addKey() { onAddKey?() }
}
