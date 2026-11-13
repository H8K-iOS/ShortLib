import Foundation
import Combine

@MainActor
final class BookDetailViewModel: ObservableObject {
    @Published private(set) var book: Book?
    /// Для книги сейчас идёт пересказ.
    @Published private(set) var isGenerating = false

    var onBack: (() -> Void)?
    var onSummarize: (() -> Void)?
    var onRead: (() -> Void)?
    var onDeleted: (() -> Void)?
    /// «Продолжить пересказ» (прерван iOS или ошибкой) или вернуться к экрану прогресса идущего пересказа.
    var onResume: (() -> Void)?

    private let bookID: UUID
    private let repository: BookRepositoryProtocol
    private let generation: SummaryGenerationService

    init(bookID: UUID, repository: BookRepositoryProtocol, generation: SummaryGenerationService) {
        self.bookID = bookID
        self.repository = repository
        self.generation = generation
        repository.booksPublisher
            .map { $0.first { $0.id == bookID } }
            .receive(on: DispatchQueue.main)
            .assign(to: &$book)
        generation.$runningBookIDs
            .map { $0.contains(bookID) }
            .removeDuplicates()
            .assign(to: &$isGenerating)
    }

    /// Есть сохранённый частичный пересказ, а задача не идёт — показать «Продолжить пересказ».
    var canResume: Bool { !isGenerating && book?.partialSummary != nil }

    /// «Готово 12 из 33 глав» для частичного пересказа.
    var partialProgressText: String? {
        guard let partial = book?.partialSummary else { return nil }
        return "Готово \(partial.chapters.count) из \(partial.preset.chapterRange.count) глав"
    }

    /// Читать можно и частичный пересказ.
    var canRead: Bool { book?.summary != nil || !(book?.partialSummary?.chapters.isEmpty ?? true) }

    func resume() { onResume?() }

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
        generation.cancel(bookID: bookID)
        repository.delete(id: bookID)
        onDeleted?()
    }
}
