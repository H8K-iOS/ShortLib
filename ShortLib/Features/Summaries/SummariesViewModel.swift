import Foundation
import Combine

@MainActor
final class SummariesViewModel: ObservableObject {
    @Published private(set) var books: [Book] = []
    var onSelect: ((UUID) -> Void)?

    init(repository: BookRepositoryProtocol) {
        repository.booksPublisher
            .map { list in
                list.filter { $0.summary != nil }
                    .sorted { ($0.summary?.createdAt ?? .distantPast) > ($1.summary?.createdAt ?? .distantPast) }
            }
            .receive(on: DispatchQueue.main)
            .assign(to: &$books)
    }

    func select(_ book: Book) { onSelect?(book.id) }
}
