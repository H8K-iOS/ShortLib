import Foundation
import Combine

/// Экран прогресса только наблюдает за `SummaryJob`: сама генерация живёт в `SummaryGenerationService`.
@MainActor
final class SummaryProgressViewModel: ObservableObject {
    enum StepState { case done, active, waiting }

    @Published private(set) var progress = SummaryProgress(stage: .loading, done: 0, total: 1)
    @Published private(set) var errorMessage: String?
    /// Сколько глав уже можно читать.
    @Published private(set) var readyChapters = 0

    var onCompleted: (() -> Void)?
    var onMinimize: (() -> Void)?
    var onCancel: (() -> Void)?
    /// «Начать читать», пока остальные главы готовятся.
    var onStartReading: (() -> Void)?

    let preset: SummaryPreset
    private let job: SummaryJob
    private let service: SummaryGenerationService
    private var cancellables: Set<AnyCancellable> = []

    init(job: SummaryJob, service: SummaryGenerationService) {
        self.job = job
        self.preset = job.preset
        self.service = service

        job.$progress.assign(to: &$progress)
        job.$readyChapters.assign(to: &$readyChapters)
        job.$state
            .sink { [weak self] state in self?.handle(state) }
            .store(in: &cancellables)
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

    /// Можно открыть читалку, не дожидаясь конца.
    var canStartReading: Bool { readyChapters > 0 && job.isRunning }

    /// Оставшееся время, секунды; `nil`, пока оценки нет (меньше двух готовых глав в этом запуске).
    var estimatedRemaining: TimeInterval? { job.estimatedRemaining }

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

    /// «Повторить» после ошибки: продолжает с последней сохранённой главы.
    func start() {
        errorMessage = nil
        service.start(bookID: job.bookID, preset: preset)
    }

    func minimize() { onMinimize?() }

    func startReading() { onStartReading?() }

    func cancel() {
        service.cancel(bookID: job.bookID)
        onCancel?()
    }

    private func handle(_ state: SummaryJob.State) {
        switch state {
        case .running: errorMessage = nil
        case .failed(let message): errorMessage = message
        case .completed: onCompleted?()
        case .cancelled: break
        }
    }
}
