import Foundation
import Combine

@MainActor
final class LibraryViewModel: ObservableObject {
    @Published private(set) var books: [Book] = []
    @Published var selectedGenre: Genre?

    var onSelectBook: ((UUID) -> Void)?
    var onAddBook: (() -> Void)?

    init(repository: BookRepositoryProtocol) {
        repository.booksPublisher
            .receive(on: DispatchQueue.main)
            .assign(to: &$books)
    }

    var genres: [Genre] { Genre.allCases.filter { $0 != .other } }

    var visibleBooks: [Book] {
        guard let selectedGenre else { return books }
        return books.filter { $0.genre == selectedGenre }
    }

    func select(_ book: Book) { onSelectBook?(book.id) }
    func addBook() { onAddBook?() }
}
