import UIKit

/// Сценарий пересказа: настройки (sheet) → прогресс → чтение.
@MainActor
final class SummaryCoordinator: Coordinator {
    enum Mode { case configure, read }

    var children: [Coordinator] = []
    var onFinish: (() -> Void)?

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
        case .configure: showSettings()
        case .read: showReader(replacingTop: false)
        }
    }

    // MARK: - Steps

    private func showSettings() {
        guard let book = deps.repository.book(id: bookID) else { return finish() }
        let vm = SummarySettingsViewModel(book: book, defaults: deps.preferences,
                                          usesLanguageModel: deps.usesLanguageModel)
        vm.onClose = { [weak self] in
            self?.router.dismiss()
            self?.finish()
        }
        vm.onCreate = { [weak self] preset in
            self?.router.dismiss { self?.showProgress(preset: preset) }
        }
        router.presentSheet(SummarySettingsView(viewModel: vm), onDismiss: { [weak self] in self?.finish() })
    }

    private func showProgress(preset: SummaryPreset) {
        guard let book = deps.repository.book(id: bookID) else { return finish() }
        let vm = SummaryProgressViewModel(book: book, preset: preset, deps: deps)
        progressViewModel = vm

        vm.onCompleted = { [weak self] in
            guard let self else { return }
            if self.isProgressVisible {
                self.showReader(replacingTop: true)
            } else {
                // Пользователь свернул экран: пересказ сохранён, в библиотеке появится бейдж.
                self.finish()
            }
        }
        vm.onMinimize = { [weak self] in self?.router.pop() }
        vm.onCancel = { [weak self] in
            self?.progressViewModel = nil
            self?.router.pop()
            self?.finish()
        }

        isProgressVisible = true
        router.push(SummaryProgressView(viewModel: vm), onPop: { [weak self] in
            // Свайп назад или «Свернуть»: генерация продолжается, координатор держит ViewModel.
            self?.isProgressVisible = false
        })
        vm.start()
    }

    private func showReader(replacingTop: Bool) {
        let vm = SummaryReaderViewModel(bookID: bookID, repository: deps.repository)
        vm.onBack = { [weak self] in self?.router.pop() }
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
