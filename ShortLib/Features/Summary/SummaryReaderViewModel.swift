import Foundation
import Combine

@MainActor
final class SummaryReaderViewModel: ObservableObject {
    enum Tab: String, CaseIterable, Identifiable {
        case overview, chapters
        var id: String { rawValue }
        var title: String { self == .overview ? "Кратко" : "По главам" }
    }

    @Published private(set) var book: Book?
    @Published var tab: Tab = .chapters

    var onBack: (() -> Void)?

    init(bookID: UUID, repository: BookRepositoryProtocol) {
        repository.booksPublisher
            .map { $0.first { $0.id == bookID } }
            .receive(on: DispatchQueue.main)
            .assign(to: &$book)
    }

    var summary: Summary? { book?.summary }

    var metaText: String {
        guard let summary else { return "" }
        let r = summary.preset.chapterRange
        return "Гл. \(r.lowerBound)–\(r.upperBound) · \(summary.wordCount.formatted()) слов · ≈ \(summary.readingMinutes) мин"
    }

    var shareText: String {
        guard let book, let summary else { return "" }
        let chapters = summary.chapters.map { "\($0.index). \($0.title)\n\($0.text)" }.joined(separator: "\n\n")
        return "\(book.title) — пересказ\n\n\(summary.overview)\n\n\(chapters)"
    }

    func back() { onBack?() }
}
