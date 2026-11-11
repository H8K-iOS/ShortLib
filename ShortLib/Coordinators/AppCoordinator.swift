import SwiftUI
import UIKit

@MainActor
final class AppCoordinator: NSObject, Coordinator {
    var children: [Coordinator] = []

    private let window: UIWindow
    private let deps: AppDependencies
    private let tabBarController = UITabBarController()
    private let addTabPlaceholder = UIViewController()
    private var library: LibraryCoordinator?

    init(window: UIWindow, deps: AppDependencies) {
        self.window = window
        self.deps = deps
    }

    func start() {
        let libraryRouter = Router()
        let library = LibraryCoordinator(router: libraryRouter, deps: deps)
        library.onAddBook = { [weak self] in self?.showImport() }
        library.start()
        add(library)
        self.library = library

        let summariesRouter = Router()
        let summaries = SummariesCoordinator(router: summariesRouter, deps: deps)
        summaries.start()
        add(summaries)

        let profileRouter = Router()
        profileRouter.setRoot(ProfileView(viewModel: ProfileViewModel(deps: deps)))

        libraryRouter.navigationController.tabBarItem = item("Библиотека", "books.vertical")
        addTabPlaceholder.tabBarItem = item("Добавить", "plus.circle")
        summariesRouter.navigationController.tabBarItem = item("Пересказы", "doc.text")
        profileRouter.navigationController.tabBarItem = item("Профиль", "person.crop.circle")

        tabBarController.viewControllers = [
            libraryRouter.navigationController,
            addTabPlaceholder,
            summariesRouter.navigationController,
            profileRouter.navigationController
        ]
        tabBarController.delegate = self
        applyTabBarAppearance()

        window.rootViewController = tabBarController
        window.tintColor = DS.UIColorToken.accent
        window.makeKeyAndVisible()
    }

    // MARK: - Flows

    private func showImport() {
        let importer = ImportCoordinator(presenter: tabBarController, deps: deps)
        importer.onFinish = { [weak self, weak importer] book in
            guard let self else { return }
            self.remove(importer)
            if let book {
                self.tabBarController.selectedIndex = 0
                self.library?.showDetail(bookID: book.id)
            }
        }
        add(importer)
        importer.start()
    }

    // MARK: - Appearance

    private func item(_ title: String, _ symbol: String) -> UITabBarItem {
        UITabBarItem(title: title, image: UIImage(systemName: symbol), selectedImage: nil)
    }

    private func applyTabBarAppearance() {
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = DS.UIColorToken.background
        appearance.shadowColor = DS.UIColorToken.line
        let attrs: [NSAttributedString.Key: Any] = [.font: DS.UIFontToken.tabBar()]
        for layout in [appearance.stackedLayoutAppearance, appearance.inlineLayoutAppearance, appearance.compactInlineLayoutAppearance] {
            layout.normal.iconColor = DS.UIColorToken.secondary
            layout.normal.titleTextAttributes = attrs.merging([.foregroundColor: DS.UIColorToken.secondary]) { $1 }
            layout.selected.iconColor = DS.UIColorToken.accent
            layout.selected.titleTextAttributes = attrs.merging([.foregroundColor: DS.UIColorToken.accent]) { $1 }
        }
        tabBarController.tabBar.standardAppearance = appearance
        tabBarController.tabBar.scrollEdgeAppearance = appearance
    }
}

extension AppCoordinator: UITabBarControllerDelegate {
    /// Вкладка «Добавить» не переключает экран, а открывает импорт модально.
    func tabBarController(_ tabBarController: UITabBarController, shouldSelect viewController: UIViewController) -> Bool {
        if viewController === addTabPlaceholder {
            showImport()
            return false
        }
        return true
    }
}
