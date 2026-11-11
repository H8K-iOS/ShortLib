import UIKit
import UniformTypeIdentifiers

/// Модальный сценарий добавления книги: EPUB из «Файлов» или веб-новелла по ссылке.
@MainActor
final class ImportCoordinator: NSObject, Coordinator {
    var children: [Coordinator] = []
    /// nil — пользователь закрыл экран без добавления.
    var onFinish: ((Book?) -> Void)?

    private weak var presenter: UIViewController?
    private let deps: AppDependencies
    private let router = Router()
    private var viewModel: ImportViewModel?

    init(presenter: UIViewController, deps: AppDependencies) {
        self.presenter = presenter
        self.deps = deps
    }

    func start() {
        let vm = ImportViewModel(epubParser: deps.epubParser, scraper: deps.scraper)
        vm.onClose = { [weak self] in self?.close(with: nil) }
        vm.onPickFile = { [weak self] in self?.showDocumentPicker() }
        vm.onImported = { [weak self] book in
            self?.deps.repository.upsert(book)
            self?.close(with: book)
        }
        viewModel = vm

        router.setRoot(ImportView(viewModel: vm))
        let nav = router.navigationController
        nav.modalPresentationStyle = .pageSheet
        nav.presentationController?.delegate = self
        presenter?.present(nav, animated: true)
    }

    private func showDocumentPicker() {
        let epub = UTType(filenameExtension: "epub") ?? .data
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [epub], asCopy: true)
        picker.allowsMultipleSelection = false
        picker.delegate = self
        router.present(picker)
    }

    private func close(with book: Book?) {
        router.navigationController.dismiss(animated: true)
        finish(book)
    }

    private func finish(_ book: Book?) {
        let callback = onFinish
        onFinish = nil
        viewModel = nil
        callback?(book)
    }
}

extension ImportCoordinator: UIDocumentPickerDelegate {
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first else { return }
        viewModel?.importEPUB(from: url)
    }
}

extension ImportCoordinator: UIAdaptivePresentationControllerDelegate {
    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        finish(nil)
    }
}
