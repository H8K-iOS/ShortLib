import Foundation

@MainActor
final class SummarySettingsViewModel: ObservableObject {
    @Published var level: DetailLevel
    @Published var ratio: Double
    @Published var focus: Set<SummaryFocus>
    @Published var noSpoilers: Bool
    @Published var lastChapter: Int

    var onCreate: ((SummaryPreset) -> Void)?
    var onClose: (() -> Void)?

    let book: Book
    /// Пересказ своими словами (есть ключ API) или бесплатные ключевые фразы.
    let usesLanguageModel: Bool
    private let defaultLevel: DetailLevel
    private let language: SummaryLanguage

    init(book: Book, defaults: Preferences, usesLanguageModel: Bool) {
        self.book = book
        self.usesLanguageModel = usesLanguageModel
        language = defaults.summaryLanguage
        let start = book.summary?.preset
        defaultLevel = defaults.defaultDetailLevel
        level = start?.level ?? defaultLevel
        ratio = start?.ratio ?? defaultLevel.defaultRatio
        focus = start?.focus ?? [.plot, .characters]
        noSpoilers = start?.noSpoilers ?? true
        lastChapter = start?.chapterRange.upperBound ?? book.chapters.count
    }

    var chapterCount: Int { book.chapters.count }
    var isAllChapters: Bool { lastChapter == chapterCount }

    var preset: SummaryPreset {
        SummaryPreset(level: level, ratio: ratio, focus: focus, noSpoilers: noSpoilers,
                      chapterRange: 1...max(1, min(lastChapter, chapterCount)), language: language)
    }

    var estimateText: String {
        "≈ \(preset.estimatedMinutes(for: book)) мин чтения · главы 1–\(preset.chapterRange.upperBound)"
    }

    var engineTitle: String {
        usesLanguageModel ? "Пересказ своими словами · Claude" : "Сейчас: ключевые фразы из текста"
    }

    var engineDetail: String {
        usesLanguageModel
            ? SummaryCostEstimate(book: book, preset: preset).text
            : "Чтобы получить связный пересказ с учётом прошлых глав, добавьте ключ Claude API в Профиле."
    }

    var spoilerDetail: String {
        noSpoilers ? "Пересказ не заглядывает дальше выбранной главы"
                   : "Добавим связи с будущими главами: что подготовлено и что раскроется позже"
    }

    func toggle(_ item: SummaryFocus) {
        if focus.contains(item) {
            guard focus.count > 1 else { return } // хотя бы один фокус
            focus.remove(item)
        } else {
            focus.insert(item)
        }
    }

    func selectAllChapters() { lastChapter = chapterCount }

    func reset() {
        level = defaultLevel
        ratio = defaultLevel.defaultRatio
        focus = [.plot, .characters]
        noSpoilers = true
        lastChapter = chapterCount
    }

    func create() { onCreate?(preset) }
    func close() { onClose?() }
}
