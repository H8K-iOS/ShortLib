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
    private let defaultLevel: DetailLevel

    init(book: Book, defaults: Preferences) {
        self.book = book
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
                      chapterRange: 1...max(1, min(lastChapter, chapterCount)))
    }

    var estimateText: String {
        "≈ \(preset.estimatedMinutes(for: book)) мин чтения · главы 1–\(preset.chapterRange.upperBound)"
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
