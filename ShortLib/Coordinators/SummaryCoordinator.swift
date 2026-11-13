import UIKit

/// Сценарий пересказа: настройки (sheet) → прогресс → чтение.
@MainActor
final class SummaryCoordinator: Coordinator {
    /// `resume` — вернуться к идущему пересказу или продолжить прерванный с сохранённой главы.
    enum Mode { case configure, read, resume }

    var children: [Coordinator] = []
    var onFinish: (() -> Void)?
    /// Пользователь хочет добавить свой ключ: родитель переключает на вкладку «Профиль».
    var onOpenProfile: (() -> Void)?

    private let router: Router
    private let deps: AppDependencies
    private let bookID: UUID
    private let mode: Mode

    private var progressViewModel: SummaryProgressViewModel?
    private var isProgressVisible = false

    init(router: Router, deps: AppDependencies, bookID: UUID, mode: Mode) {
        self.router = router
        self.deps = deps
        self.bookID = bookID
        self.mode = mode
    }

    func start() {
        switch mode {
        case .configure:
            if deps.engineKind == .extractive, deps.freeQuota == nil {
                // Остаток бесплатных глав ещё не загружен (например, не было сети при запуске) — спросим сервер.
                Task { [weak self] in
                    await self?.deps.refreshFreeQuota()
                    self?.showSettings()
                }
            } else {
                showSettings()
            }
        case .read: showReader(replacingTop: false)
        case .resume:
            guard let job = deps.generation.resume(bookID: bookID) else { return finish() }
            showProgress(job: job)
        }
    }

    // MARK: - Steps

    private func showSettings() {
        guard let book = deps.repository.book(id: bookID) else { return finish() }
        let vm = SummarySettingsViewModel(book: book, defaults: deps.preferences,
                                          usesLanguageModel: deps.usesLanguageModel,
                                          freeChaptersLeft: deps.engineKind == .freeProxy
                                              ? deps.freeQuota?.chaptersLeft : nil,
                                          freeLimitReached: !deps.preferences.hasAPIKey
                                              && deps.freeQuota?.isAvailable == false)
        vm.onClose = { [weak self] in
            self?.router.dismiss()
            self?.finish()
        }
        vm.onAddKey = { [weak self] in
            self?.router.dismiss {
                self?.onOpenProfile?()
                self?.finish()
            }
        }
        vm.onCreate = { [weak self] preset in
            self?.router.dismiss {
                guard let self else { return }
                self.showProgress(job: self.deps.generation.start(bookID: self.bookID, preset: preset))
            }
        }
        router.presentSheet(SummarySettingsView(viewModel: vm), onDismiss: { [weak self] in self?.finish() })
    }

    /// Экран прогресса наблюдает за задачей сервиса; сама генерация от экрана не зависит.
    private func showProgress(job: SummaryJob) {
        let vm = SummaryProgressViewModel(job: job, service: deps.generation)
        progressViewModel = vm

        vm.onCompleted = { [weak self] in
            guard let self, self.isProgressVisible else { return }
            self.showReader(replacingTop: true)
        }
        vm.onStartReading = { [weak self] in self?.showReader(replacingTop: true) }
        vm.onMinimize = { [weak self] in self?.router.pop() }
        vm.onCancel = { [weak self] in self?.router.pop() }

        isProgressVisible = true
        router.push(SummaryProgressView(viewModel: vm), onPop: { [weak self] in
            // Свайп назад, «Свернуть» или «Отменить»: генерация (если не отменена) идёт в сервисе.
            self?.isProgressVisible = false
            self?.finish()
        })
    }

    private func showReader(replacingTop: Bool) {
        isProgressVisible = false
        let vm = SummaryReaderViewModel(bookID: bookID, repository: deps.repository,
                                        job: deps.generation.job(for: bookID))
        vm.onBack = { [weak self] in self?.router.pop() }
        vm.onResume = { [weak self] in
            // Продолжаем в сервисе и пересоздаём читалку, чтобы она наблюдала за новой задачей.
            guard let self, self.deps.generation.resume(bookID: self.bookID) != nil else { return }
            self.showReader(replacingTop: true)
        }
        let onPop: () -> Void = { [weak self] in self?.finish() }
        if replacingTop {
            router.replaceTop(SummaryReaderView(viewModel: vm), onPop: onPop)
        } else {
            router.push(SummaryReaderView(viewModel: vm), onPop: onPop)
        }
        progressViewModel = nil
    }

    private func finish() {
        progressViewModel = nil
        let callback = onFinish
        onFinish = nil
        callback?()
    }
}
