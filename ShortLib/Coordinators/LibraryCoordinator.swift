import UIKit

@MainActor
final class LibraryCoordinator: Coordinator {
    var children: [Coordinator] = []
    var onAddBook: (() -> Void)?
    var onOpenProfile: (() -> Void)?

    private let router: Router
    private let deps: AppDependencies

    init(router: Router, deps: AppDependencies) {
        self.router = router
        self.deps = deps
    }

    func start() {
        let vm = LibraryViewModel(repository: deps.repository, generation: deps.generation)
        vm.onSelectBook = { [weak self] id in self?.showDetail(bookID: id) }
        vm.onAddBook = { [weak self] in self?.onAddBook?() }
        router.setRoot(LibraryView(viewModel: vm))
    }

    func showDetail(bookID: UUID) {
        let vm = BookDetailViewModel(bookID: bookID, repository: deps.repository, generation: deps.generation)
        vm.onBack = { [weak self] in self?.router.pop() }
        vm.onDeleted = { [weak self] in self?.router.pop() }
        vm.onSummarize = { [weak self] in self?.startSummary(bookID: bookID, mode: .configure) }
        vm.onRead = { [weak self] in self?.startSummary(bookID: bookID, mode: .read) }
        vm.onResume = { [weak self] in self?.startSummary(bookID: bookID, mode: .resume) }
        router.push(BookDetailView(viewModel: vm))
    }

    private func startSummary(bookID: UUID, mode: SummaryCoordinator.Mode) {
        let flow = SummaryCoordinator(router: router, deps: deps, bookID: bookID, mode: mode)
        flow.onFinish = { [weak self, weak flow] in self?.remove(flow) }
        flow.onOpenProfile = { [weak self] in self?.onOpenProfile?() }
        add(flow)
        flow.start()
    }
}

/// Вкладка «Пересказы»: список готовых пересказов → чтение.
@MainActor
final class SummariesCoordinator: Coordinator {
    var children: [Coordinator] = []

    private let router: Router
    private let deps: AppDependencies

    init(router: Router, deps: AppDependencies) {
        self.router = router
        self.deps = deps
    }

    func start() {
        let vm = SummariesViewModel(repository: deps.repository)
        vm.onSelect = { [weak self] id in
            guard let self else { return }
            let flow = SummaryCoordinator(router: self.router, deps: self.deps, bookID: id, mode: .read)
            flow.onFinish = { [weak self, weak flow] in self?.remove(flow) }
            self.add(flow)
            flow.start()
        }
        router.setRoot(SummariesView(viewModel: vm))
    }
}
