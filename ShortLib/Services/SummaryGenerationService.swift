import Foundation
import Combine
import UIKit

/// Пересказ одной книги. Живёт в `SummaryGenerationService`, а не в экране:
/// уход с экрана прогресса или из читалки генерацию не обрывает.
@MainActor
final class SummaryJob: ObservableObject, Identifiable {
    enum State: Equatable {
        case running
        case failed(String)
        case completed
        case cancelled
    }

    let bookID: UUID
    let preset: SummaryPreset
    var id: UUID { bookID }

    @Published fileprivate(set) var progress = SummaryProgress(stage: .loading, done: 0, total: 1)
    @Published fileprivate(set) var state: State = .running
    /// Сколько глав уже пересказано (включая сохранённые в прошлых запусках).
    @Published fileprivate(set) var readyChapters = 0

    /// Моменты готовности глав в текущем запуске — для оценки оставшегося времени.
    private var chapterTimes: [Date] = []
    fileprivate var task: Task<Void, Never>?
    /// Приложение сворачивали во время этого запуска: сетевая ошибка, скорее всего, из-за остановки iOS.
    fileprivate var backgroundedDuringRun = false
    /// Задачу прервала iOS, пока приложение было свёрнуто: при возврате продолжаем сами.
    fileprivate var interruptedInBackground = false

    var totalChapters: Int { preset.chapterRange.count }
    var isRunning: Bool { state == .running }

    /// Оставшееся время по средней скорости глав в этом запуске; `nil`, пока данных мало.
    var estimatedRemaining: TimeInterval? {
        guard isRunning, chapterTimes.count >= 2,
              let first = chapterTimes.first, let last = chapterTimes.last else { return nil }
        let perChapter = last.timeIntervalSince(first) / Double(chapterTimes.count - 1)
        let left = totalChapters - readyChapters
        guard left > 0 else { return nil }
        // Связи и сводка в конце — примерно ещё пара «глав».
        return perChapter * Double(left + 2)
    }

    fileprivate init(bookID: UUID, preset: SummaryPreset) {
        self.bookID = bookID
        self.preset = preset
    }

    fileprivate func reset(ready: Int) {
        state = .running
        progress = SummaryProgress(stage: .loading, done: 0, total: 1)
        readyChapters = ready
        chapterTimes = [Date()]
        backgroundedDuringRun = false
        interruptedInBackground = false
    }

    fileprivate func markChapterReady(count: Int) {
        guard count > readyChapters else { return }
        readyChapters = count
        chapterTimes.append(Date())
    }

    fileprivate func update(_ p: SummaryProgress) {
        // Не откатываемся назад, если обновления пришли не по порядку.
        guard p.fraction >= progress.fraction || p.stage != progress.stage else { return }
        progress = p
    }
}

/// Владеет задачами пересказа по книгам: загрузка глав → движок → сохранение.
/// Частичный пересказ (`Book.partialSummary`) сохраняется после каждой главы,
/// поэтому после остановки iOS или перезапуска пересказ продолжается с того же места.
@MainActor
final class SummaryGenerationService: ObservableObject {
    /// Книги, для которых сейчас идёт пересказ.
    @Published private(set) var runningBookIDs: Set<UUID> = []
    /// Вызывается, когда задача закончилась (успех, ошибка, отмена) — например, обновить бесплатный лимит.
    var onJobFinished: ((UUID) -> Void)?

    private let repository: BookRepositoryProtocol
    private let scraper: WebNovelScraping
    private let engineFactory: () -> SummaryEngine
    private var jobs: [UUID: SummaryJob] = [:]
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    private var observers: [NSObjectProtocol] = []

    init(repository: BookRepositoryProtocol,
         scraper: WebNovelScraping,
         engineFactory: @escaping () -> SummaryEngine) {
        self.repository = repository
        self.scraper = scraper
        self.engineFactory = engineFactory

        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: UIApplication.didEnterBackgroundNotification,
                                            object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.didEnterBackground() }
        })
        observers.append(center.addObserver(forName: UIApplication.didBecomeActiveNotification,
                                            object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.didBecomeActive() }
        })
    }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    // MARK: - Public API

    func job(for bookID: UUID) -> SummaryJob? { jobs[bookID] }

    func isRunning(bookID: UUID) -> Bool { runningBookIDs.contains(bookID) }

    /// Есть сохранённый частичный пересказ, а задача не идёт — можно предложить «Продолжить пересказ».
    func canResume(bookID: UUID) -> Bool {
        !isRunning(bookID: bookID) && repository.book(id: bookID)?.partialSummary != nil
    }

    /// Запускает пересказ с пресетом. Если для книги уже идёт пересказ с тем же пресетом — возвращает его.
    /// Частичный пересказ с другим пресетом сбрасывается.
    @discardableResult
    func start(bookID: UUID, preset: SummaryPreset) -> SummaryJob {
        if let existing = jobs[bookID], existing.preset == preset {
            if !existing.isRunning { run(existing) }
            return existing
        }
        jobs[bookID]?.task?.cancel()

        if var book = repository.book(id: bookID), let partial = book.partialSummary, partial.preset != preset {
            book.partialSummary = nil
            repository.upsert(book)
        }
        let job = SummaryJob(bookID: bookID, preset: preset)
        jobs[bookID] = job
        run(job)
        return job
    }

    /// Продолжает пересказ с сохранённого места (пресет берётся из частичного пересказа).
    @discardableResult
    func resume(bookID: UUID) -> SummaryJob? {
        if let job = jobs[bookID], job.isRunning { return job }
        guard let partial = repository.book(id: bookID)?.partialSummary else { return nil }
        return start(bookID: bookID, preset: partial.preset)
    }

    /// Отмена пользователем. Готовые главы остаются в частичном пересказе — их можно дочитать или продолжить.
    func cancel(bookID: UUID) {
        guard let job = jobs[bookID] else { return }
        job.task?.cancel()
        job.state = .cancelled
        finish(job)
    }

    // MARK: - Pipeline

    private func run(_ job: SummaryJob) {
        let ready = repository.book(id: job.bookID)?.partialSummary
            .flatMap { $0.preset == job.preset ? $0.chapters.count : nil } ?? 0
        job.reset(ready: ready)
        runningBookIDs.insert(job.bookID)
        beginBackgroundTaskIfNeeded()
        job.task = Task { [weak self] in await self?.pipeline(job) }
    }

    private func pipeline(_ job: SummaryJob) async {
        do {
            guard var book = repository.book(id: job.bookID) else { throw CancellationError() }
            try await loadMissingChapters(of: &book, job: job)
            job.update(SummaryProgress(stage: .cleaning, done: 1, total: 1))

            let resume = book.partialSummary.flatMap { $0.preset == job.preset ? $0 : nil }
            let engine = engineFactory()
            let summary = try await engine.summarize(
                book: book,
                preset: job.preset,
                resume: resume,
                progress: { p in
                    Task { @MainActor in job.update(p) }
                },
                onPartial: { [weak self] partial in
                    Task { @MainActor in
                        guard let self else { return }
                        self.save(partial, for: job)
                    }
                }
            )

            try Task.checkCancellation()
            guard var latest = repository.book(id: job.bookID) else { throw CancellationError() }
            latest.summary = summary
            // Бесплатный лимит кончился посреди книги: движок вернул урезанный пересказ.
            // Частичный оставляем — после добавления своего ключа можно «Продолжить пересказ».
            let isTruncated = summary.preset.chapterRange.upperBound < job.preset.chapterRange.upperBound
            if !isTruncated { latest.partialSummary = nil }
            repository.upsert(latest)
            job.markChapterReady(count: job.totalChapters)
            job.update(SummaryProgress(stage: .overview, done: 1, total: 1))
            job.state = .completed
            finish(job)
        } catch is CancellationError {
            if job.state == .running { job.state = .cancelled }
            finish(job)
        } catch {
            guard job.state == .running else { return finish(job) }
            if job.backgroundedDuringRun {
                // Сеть оборвалась из-за остановки iOS: продолжим с сохранённой главы (один раз за сворачивание).
                if UIApplication.shared.applicationState == .active { return run(job) }
                job.interruptedInBackground = true
            }
            job.state = .failed(error.localizedDescription)
            finish(job)
        }
    }

    /// Главы веб-новелл загружаются по одной, чтобы не перегружать сайт и устройство.
    private func loadMissingChapters(of book: inout Book, job: SummaryJob) async throws {
        let missing = book.chapters.filter { job.preset.chapterRange.contains($0.index) && !$0.isLoaded && $0.url != nil }
        job.update(SummaryProgress(stage: .loading, done: 0, total: max(1, missing.count)))
        guard !missing.isEmpty else {
            job.update(SummaryProgress(stage: .loading, done: 1, total: 1))
            return
        }
        for (i, chapter) in missing.enumerated() {
            try Task.checkCancellation()
            guard let url = chapter.url else { continue }
            let text = try await scraper.fetchChapterText(url)
            if let idx = book.chapters.firstIndex(where: { $0.index == chapter.index }) {
                book.chapters[idx].text = text
            }
            job.update(SummaryProgress(stage: .loading, done: i + 1, total: missing.count))
            if (i + 1) % 10 == 0 { persistChapters(of: book) } // кешируем загруженное
        }
        persistChapters(of: book)
    }

    /// Сохраняет тексты глав, не затирая остальные поля книги (частичный пересказ, старый пересказ).
    private func persistChapters(of book: Book) {
        guard var latest = repository.book(id: book.id) else { return }
        latest.chapters = book.chapters
        repository.upsert(latest)
    }

    private func save(_ partial: PartialSummary, for job: SummaryJob) {
        // Поздние обновления после завершения или отмены не должны вернуть частичный пересказ.
        guard job.isRunning, partial.preset == job.preset,
              var book = repository.book(id: job.bookID) else { return }
        if let saved = book.partialSummary, saved.preset == partial.preset,
           saved.chapters.count > partial.chapters.count { return }
        book.partialSummary = partial
        repository.upsert(book)
        job.markChapterReady(count: partial.chapters.count)
    }

    private func finish(_ job: SummaryJob) {
        guard runningBookIDs.remove(job.bookID) != nil else { return }
        onJobFinished?(job.bookID)
        if runningBookIDs.isEmpty { endBackgroundTask() }
    }

    // MARK: - App lifecycle

    /// iOS даёт свёрнутому приложению ~30 с: хватает дописать текущую главу и сохранить её.
    /// Дольше пересказ не идёт — при возврате продолжаем с сохранённого места.
    private func beginBackgroundTaskIfNeeded() {
        guard backgroundTask == .invalid else { return }
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "ShortLib.summary") { [weak self] in
            Task { @MainActor in self?.endBackgroundTask() }
        }
    }

    private func endBackgroundTask() {
        guard backgroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTask)
        backgroundTask = .invalid
    }

    private func didEnterBackground() {
        for job in jobs.values where job.isRunning { job.backgroundedDuringRun = true }
        if !runningBookIDs.isEmpty { beginBackgroundTaskIfNeeded() }
    }

    private func didBecomeActive() {
        for job in jobs.values where job.interruptedInBackground {
            if case .failed = job.state { run(job) }
        }
    }
}
