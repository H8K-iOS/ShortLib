import Foundation
import Combine

@MainActor
final class BookDetailViewModel: ObservableObject {
    @Published private(set) var book: Book?

    var onBack: (() -> Void)?
    var onSummarize: (() -> Void)?
    var onRead: (() -> Void)?
    var onDeleted: (() -> Void)?

    private let bookID: UUID
    private let repository: BookRepositoryProtocol

    init(bookID: UUID, repository: BookRepositoryProtocol) {
        self.bookID = bookID
        self.repository = repository
        repository.booksPublisher
            .map { $0.first { $0.id == bookID } }
            .receive(on: DispatchQueue.main)
            .assign(to: &$book)
    }

    var originalReadingTime: String {
        guard let book else { return "—" }
        let words = Double(book.estimatedWordCount(in: book.chapterRange))
        let minutes = Int(words / SummaryPreset.readingSpeed)
        return minutes >= 60 ? "≈ \(minutes / 60) ч \(minutes % 60) мин" : "≈ \(minutes) мин"
    }

    var loadedChaptersText: String {
        guard let book else { return "" }
        let loaded = book.chapters.filter(\.isLoaded).count
        return loaded == book.chapters.count ? "\(book.chapters.count) глав, текст загружен"
                                             : "\(book.chapters.count) глав, загружено \(loaded)"
    }

    func back() { onBack?() }
    func summarize() { onSummarize?() }
    func read() { onRead?() }

    func delete() {
        repository.delete(id: bookID)
        onDeleted?()
    }
}
