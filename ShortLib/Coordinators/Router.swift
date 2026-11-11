import SwiftUI
import UIKit

/// Обёртка над UINavigationController. Экраны — SwiftUI, навигация — UIKit.
/// Системная панель навигации скрыта: кнопки «назад» рисует сам экран (стиль ShortLib),
/// жест смахивания назад при этом сохранён.
@MainActor
final class Router: NSObject {
    let navigationController: UINavigationController
    private var onPop: [ObjectIdentifier: () -> Void] = [:]
    private var onSheetDismiss: (() -> Void)?

    init(navigationController: UINavigationController = UINavigationController()) {
        self.navigationController = navigationController
        super.init()
        navigationController.setNavigationBarHidden(true, animated: false)
        navigationController.delegate = self
        navigationController.interactivePopGestureRecognizer?.delegate = self
    }

    // MARK: - Stack

    func setRoot<V: View>(_ view: V) {
        navigationController.setViewControllers([host(view)], animated: false)
    }

    func push<V: View>(_ view: V, animated: Bool = true, onPop: (() -> Void)? = nil) {
        let vc = host(view)
        if let onPop { self.onPop[ObjectIdentifier(vc)] = onPop }
        navigationController.pushViewController(vc, animated: animated)
    }

    /// Заменяет верхний экран (например, прогресс → готовый пересказ).
    func replaceTop<V: View>(_ view: V, onPop: (() -> Void)? = nil) {
        let vc = host(view)
        if let onPop { self.onPop[ObjectIdentifier(vc)] = onPop }
        var stack = navigationController.viewControllers
        if let old = stack.popLast() { self.onPop[ObjectIdentifier(old)] = nil }
        stack.append(vc)
        navigationController.setViewControllers(stack, animated: true)
    }

    func pop(animated: Bool = true) {
        navigationController.popViewController(animated: animated)
    }

    // MARK: - Modal

    func present(_ controller: UIViewController, animated: Bool = true) {
        topPresented.present(controller, animated: animated)
    }

    func presentSheet<V: View>(_ view: V, detents: [UISheetPresentationController.Detent] = [.large()],
                               onDismiss: (() -> Void)? = nil) {
        let vc = host(view)
        vc.modalPresentationStyle = .pageSheet
        if let sheet = vc.sheetPresentationController {
            sheet.detents = detents
            sheet.prefersGrabberVisible = true
            sheet.preferredCornerRadius = DS.Radius.xl
        }
        vc.presentationController?.delegate = self
        onSheetDismiss = onDismiss
        topPresented.present(vc, animated: true)
    }

    func dismiss(animated: Bool = true, completion: (() -> Void)? = nil) {
        onSheetDismiss = nil
        navigationController.dismiss(animated: animated, completion: completion)
    }

    // MARK: - Private

    private var topPresented: UIViewController {
        var top: UIViewController = navigationController
        while let next = top.presentedViewController { top = next }
        return top
    }

    private func host<V: View>(_ view: V) -> UIViewController {
        let vc = UIHostingController(rootView: view.dsScreen())
        vc.view.backgroundColor = DS.UIColorToken.background
        return vc
    }
}

extension Router: UINavigationControllerDelegate {
    func navigationController(_ navigationController: UINavigationController,
                              didShow viewController: UIViewController, animated: Bool) {
        guard let from = navigationController.transitionCoordinator?.viewController(forKey: .from),
              !navigationController.viewControllers.contains(from) else { return }
        onPop.removeValue(forKey: ObjectIdentifier(from))?()
    }
}

extension Router: UIGestureRecognizerDelegate {
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        navigationController.viewControllers.count > 1
    }
}

extension Router: UIAdaptivePresentationControllerDelegate {
    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        let callback = onSheetDismiss
        onSheetDismiss = nil
        callback?()
    }
}
