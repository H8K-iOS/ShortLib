import UIKit

/// Координатор владеет навигацией одного сценария и держит дочерние координаторы.
@MainActor
protocol Coordinator: AnyObject {
    var children: [Coordinator] { get set }
    func start()
}

extension Coordinator {
    func add(_ child: Coordinator) {
        children.append(child)
    }

    func remove(_ child: Coordinator?) {
        guard let child else { return }
        children.removeAll { $0 === child }
    }
}
