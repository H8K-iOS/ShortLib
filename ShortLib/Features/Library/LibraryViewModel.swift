import Foundation
import Combine

@MainActor
final class LibraryViewModel: ObservableObject {
    @Published private(set) var books: [Book] = []
    @Published var selectedGenre: Genre?
    /// Книги, для которых сейчас идёт пересказ, — для бейджа на обложке.
    @Published private(set) var generatingIDs: Set<UUID> = []

    var onSelectBook: ((UUID) -> Void)?
    var onAddBook: (() -> Void)?

    init(repository: BookRepositoryProtocol, generation: SummaryGenerationService? = nil) {
        repository.booksPublisher
            .receive(on: DispatchQueue.main)
            .assign(to: &$books)
        generation?.$runningBookIDs
            .receive(on: DispatchQueue.main)
            .assign(to: &$generatingIDs)
    }

    func isGenerating(_ book: Book) -> Bool { generatingIDs.contains(book.id) }

    var genres: [Genre] { Genre.allCases.filter { $0 != .other } }

    var visibleBooks: [Book] {
        guard let selectedGenre else { return books }
        return books.filter { $0.genre == selectedGenre }
    }

    func select(_ book: Book) { onSelectBook?(book.id) }
    func addBook() { onAddBook?() }
}
