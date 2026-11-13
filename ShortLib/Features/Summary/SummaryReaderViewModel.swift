import Foundation
import Combine

@MainActor
final class SummaryReaderViewModel: ObservableObject {
    enum Tab: String, CaseIterable, Identifiable {
        case overview, chapters, characters
        var id: String { rawValue }
        var title: String {
            switch self {
            case .overview: return "Кратко"
            case .chapters: return "По главам"
            case .characters: return "Персонажи"
            }
        }
    }

    @Published private(set) var book: Book?
    @Published var tab: Tab = .chapters

    var onBack: (() -> Void)?
    /// «Продолжить пересказ», если он остановился (ошибка, отмена, перезапуск приложения).
    var onResume: (() -> Void)?

    /// Идущий пересказ этой книги: готовые главы читаются, пока остальные готовятся.
    private let job: SummaryJob?
    private var cancellables: Set<AnyCancellable> = []

    init(bookID: UUID, repository: BookRepositoryProtocol, job: SummaryJob? = nil) {
        self.job = job
        repository.booksPublisher
            .map { $0.first { $0.id == bookID } }
            .receive(on: DispatchQueue.main)
            .assign(to: &$book)
        job?.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    var summary: Summary? { book?.summary }
    private var partial: PartialSummary? { book?.partialSummary }

    // MARK: - Пересказ ещё идёт

    /// Показываем частичный пересказ: идёт генерация или полного пересказа ещё нет.
    var isInProgress: Bool { job?.isRunning == true || (summary == nil && partial != nil) }
    var isRunning: Bool { job?.isRunning == true }
    var hasContent: Bool { summary != nil || partial != nil }

    var readyChapters: Int { job?.readyChapters ?? partial?.chapters.count ?? 0 }
    var totalChapters: Int { job?.totalChapters ?? partial?.preset.chapterRange.count ?? summary?.chapters.count ?? 0 }
    var remaining: TimeInterval? { job?.estimatedRemaining }

    /// Бейдж в шапке: «8 из 33 · ≈ 12 мин».
    var progressBadge: String {
        let base = "\(readyChapters) из \(totalChapters)"
        guard let eta = WaitTimeText.short(remaining) else { return base }
        return "\(base) · \(eta)"
    }

    /// Плашка под готовыми главами.
    var pendingTitle: String {
        let next = (chapters.last?.index ?? (partial?.preset.chapterRange.lowerBound ?? 1) - 1) + 1
        return isRunning ? "Глава \(next) готовится…" : "Пересказ остановлен на главе \(next)"
    }

    var pendingDetail: String {
        isRunning ? "\(WaitTimeText.text(remaining)) до конца. Новые главы появятся здесь сами."
                  : "Готовые главы сохранены. Можно продолжить с этого места."
    }

    var pendingProgress: Double { totalChapters > 0 ? Double(readyChapters) / Double(totalChapters) : 0 }

    // MARK: - Содержимое

    var chapters: [ChapterSummary] {
        isInProgress ? (partial?.chapters ?? []) : (summary?.chapters ?? [])
    }

    /// Общая сводка появляется только в конце пересказа.
    var overview: String? { isInProgress ? nil : summary?.overview }
    var characters: [CharacterNote] { isInProgress ? [] : (summary?.characters ?? []) }

    /// «Кратко» — последней: это сюжет целиком, со спойлерами, его открывают осознанно.
    var tabs: [Tab] { characters.isEmpty ? [.chapters, .overview] : [.chapters, .characters, .overview] }

    // MARK: - Раскрывающиеся главы

    /// Раскрытые главы (по индексу). По умолчанию все свёрнуты — список названий для быстрого поиска.
    @Published private(set) var expandedChapters: Set<Int> = []
    /// Глава, к которой прокрутить список (после «Дальше»).
    @Published private(set) var scrollTarget: Int?

    func isExpanded(_ chapter: ChapterSummary) -> Bool { expandedChapters.contains(chapter.index) }

    func toggle(_ chapter: ChapterSummary) {
        if expandedChapters.contains(chapter.index) {
            expandedChapters.remove(chapter.index)
        } else {
            expandedChapters.insert(chapter.index)
        }
    }

    var isAllExpanded: Bool { !chapters.isEmpty && chapters.allSatisfy { expandedChapters.contains($0.index) } }

    func toggleAll() {
        expandedChapters = isAllExpanded ? [] : Set(chapters.map(\.index))
    }

    /// Следующая готовая глава после этой — для кнопки «Дальше».
    func next(after chapter: ChapterSummary) -> ChapterSummary? {
        chapters.first { $0.index > chapter.index }
    }

    /// «Дальше»: свернуть прочитанную, раскрыть следующую и прокрутить к ней.
    func openNext(after chapter: ChapterSummary) {
        guard let next = next(after: chapter) else { return }
        expandedChapters.remove(chapter.index)
        expandedChapters.insert(next.index)
        scrollTarget = next.index
    }

    // MARK: - Предупреждение о спойлерах

    /// Пользователь согласился открыть сводку (на время, пока открыта читалка).
    @Published private(set) var isOverviewRevealed = false

    /// Сводка размыта, поверх — предупреждение.
    var isOverviewHidden: Bool { tab == .overview && overview != nil && !isOverviewRevealed }

    func revealOverview() { isOverviewRevealed = true }

    var metaText: String {
        if isInProgress, let preset = partial?.preset ?? summary?.preset {
            let r = preset.chapterRange
            return "Гл. \(r.lowerBound)–\(r.upperBound) · готово \(readyChapters) из \(RussianPlural.chapters(totalChapters))"
        }
        guard let summary else { return "" }
        let r = summary.preset.chapterRange
        let engine = summary.engine.map { " · \($0)" } ?? ""
        return "Гл. \(r.lowerBound)–\(r.upperBound) · \(summary.wordCount.formatted()) слов · ≈ \(summary.readingMinutes) мин\(engine)"
    }

    var shareText: String {
        guard let book else { return "" }
        let body = chapters.map { "\($0.index). \($0.title)\n\($0.text)" }.joined(separator: "\n\n")
        guard let overview else { return "\(book.title) — пересказ (готово \(readyChapters) из \(totalChapters) глав)\n\n\(body)" }
        return "\(book.title) — пересказ\n\n\(overview)\n\n\(body)"
    }

    func back() { onBack?() }
    func resume() { onResume?() }
    func showChapters() { tab = .chapters }
}
