import Foundation
import Combine

/// Хранилище книг. Сейчас — JSON-файл в Documents; позже можно заменить на Core Data,
/// не трогая ViewModel: они работают только с протоколом.
protocol BookRepositoryProtocol: AnyObject {
    var booksPublisher: AnyPublisher<[Book], Never> { get }
    var books: [Book] { get }
    func book(id: UUID) -> Book?
    func upsert(_ book: Book)
    func delete(id: UUID)
}

final class BookRepository: BookRepositoryProtocol {
    private let subject: CurrentValueSubject<[Book], Never>
    private let fileURL: URL
    private let queue = DispatchQueue(label: "ShortLib.BookRepository", qos: .utility)

    init(fileManager: FileManager = .default) {
        let dir = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let url = dir.appendingPathComponent("library.json")
        fileURL = url

        if let data = try? Data(contentsOf: url),
           let saved = try? JSONDecoder().decode([Book].self, from: data) {
            subject = CurrentValueSubject(saved)
        } else {
            subject = CurrentValueSubject(SampleData.books)
        }
    }

    var booksPublisher: AnyPublisher<[Book], Never> { subject.eraseToAnyPublisher() }
    var books: [Book] { subject.value }

    func book(id: UUID) -> Book? { subject.value.first { $0.id == id } }

    func upsert(_ book: Book) {
        var list = subject.value
        if let i = list.firstIndex(where: { $0.id == book.id }) {
            list[i] = book
        } else {
            list.insert(book, at: 0)
        }
        subject.send(list)
        persist(list)
    }

    func delete(id: UUID) {
        let list = subject.value.filter { $0.id != id }
        subject.send(list)
        persist(list)
    }

    private func persist(_ list: [Book]) {
        let url = fileURL
        queue.async {
            guard let data = try? JSONEncoder().encode(list) else { return }
            try? data.write(to: url, options: .atomic)
        }
    }
}
