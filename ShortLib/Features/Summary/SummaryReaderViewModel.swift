import Foundation
import Combine

@MainActor
final class SummaryReaderViewModel: ObservableObject {
    enum Tab: String, CaseIterable, Identifiable {
        case overview, chapters, characters
        var id: String { rawValue }
        var title: String {
            switch self {
            case .overview: return "Кратко"
            case .chapters: return "По главам"
            case .characters: return "Персонажи"
            }
        }
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

    var tabs: [Tab] {
        (summary?.characters?.isEmpty ?? true) ? [.overview, .chapters] : Tab.allCases
    }

    var metaText: String {
        guard let summary else { return "" }
        let r = summary.preset.chapterRange
        let engine = summary.engine.map { " · \($0)" } ?? ""
        return "Гл. \(r.lowerBound)–\(r.upperBound) · \(summary.wordCount.formatted()) слов · ≈ \(summary.readingMinutes) мин\(engine)"
    }

    var shareText: String {
        guard let book, let summary else { return "" }
        let chapters = summary.chapters.map { "\($0.index). \($0.title)\n\($0.text)" }.joined(separator: "\n\n")
        return "\(book.title) — пересказ\n\n\(summary.overview)\n\n\(chapters)"
    }

    func back() { onBack?() }
}
