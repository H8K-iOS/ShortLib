import Foundation

@MainActor
final class SummaryProgressViewModel: ObservableObject {
    enum StepState { case done, active, waiting }

    @Published private(set) var progress = SummaryProgress(stage: .loading, done: 0, total: 1)
    @Published private(set) var errorMessage: String?

    var onCompleted: (() -> Void)?
    var onMinimize: (() -> Void)?
    var onCancel: (() -> Void)?

    let preset: SummaryPreset
    private var book: Book
    private let deps: AppDependencies
    private var task: Task<Void, Never>?

    init(book: Book, preset: SummaryPreset, deps: AppDependencies) {
        self.book = book
        self.preset = preset
        self.deps = deps
    }

    /// Этап связей показываем, только если спойлеры разрешены.
    var stages: [SummaryProgress.Stage] {
        SummaryProgress.Stage.allCases.filter { $0 != .connecting || !preset.noSpoilers }
    }

    var badgeText: String { "\(preset.level.title) · \(preset.level.wordRangeText)" }
    var percentText: String { "\(Int((progress.fraction * 100).rounded()))%" }
    var chaptersInRange: Int { preset.chapterRange.count }

    var ringSubtitle: String {
        switch progress.stage {
        case .summarizing: return "\(progress.done) из \(progress.total) глав"
        default: return progress.stage.title.lowercased()
        }
    }

    func state(of stage: SummaryProgress.Stage) -> StepState {
        if stage.rawValue < progress.stage.rawValue { return .done }
        if stage == progress.stage { return progress.done >= progress.total && stage == .overview ? .done : .active }
        return .waiting
    }

    func detail(of stage: SummaryProgress.Stage) -> String {
        switch state(of: stage) {
        case .waiting: return "—"
        case .done where stage == .summarizing: return "\(chaptersInRange)/\(chaptersInRange)"
        case .done: return "готово"
        case .active: return "\(progress.done)/\(progress.total)"
        }
    }

    // MARK: - Actions

    func start() {
        errorMessage = nil
        task?.cancel()
        task = Task { [weak self] in await self?.run() }
    }

    func minimize() { onMinimize?() }

    func cancel() {
        task?.cancel()
        onCancel?()
    }

    // MARK: - Pipeline

    private func run() async {
        do {
            try await loadMissingChapters()

            update(SummaryProgress(stage: .cleaning, done: 1, total: 1))

            let engine = deps.makeSummaryEngine()
            let summary = try await engine.summarize(book: book, preset: preset) { [weak self] p in
                Task { @MainActor in self?.update(p) }
            }
            book.summary = summary
            deps.repository.upsert(book)
            update(SummaryProgress(stage: .overview, done: 1, total: 1))
            onCompleted?()
        } catch is CancellationError {
            // Пользователь отменил — ничего не сохраняем.
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Главы веб-новелл загружаются по одной, чтобы не перегружать сайт и устройство.
    private func loadMissingChapters() async throws {
        let missing = book.chapters.filter { preset.chapterRange.contains($0.index) && !$0.isLoaded && $0.url != nil }
        update(SummaryProgress(stage: .loading, done: 0, total: max(1, missing.count)))
        guard !missing.isEmpty else {
            update(SummaryProgress(stage: .loading, done: 1, total: 1))
            return
        }
        for (i, chapter) in missing.enumerated() {
            try Task.checkCancellation()
            guard let url = chapter.url else { continue }
            let text = try await deps.scraper.fetchChapterText(url)
            if let idx = book.chapters.firstIndex(where: { $0.index == chapter.index }) {
                book.chapters[idx].text = text
            }
            update(SummaryProgress(stage: .loading, done: i + 1, total: missing.count))
            if (i + 1) % 10 == 0 { deps.repository.upsert(book) } // кешируем загруженное
        }
        deps.repository.upsert(book)
    }

    private func update(_ p: SummaryProgress) {
        // Не откатываемся назад, если обновления пришли не по порядку.
        guard p.fraction >= progress.fraction || p.stage != progress.stage else { return }
        progress = p
    }
}
