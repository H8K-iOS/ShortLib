import Foundation

struct Chapter: Identifiable, Codable, Hashable {
    /// Порядковый номер, начиная с 1.
    let index: Int
    var title: String
    /// Пустой, пока глава веб-новеллы не загружена.
    var text: String
    var url: URL?

    var id: Int { index }
    var isLoaded: Bool { !text.isEmpty }
    var wordCount: Int { text.split(whereSeparator: { $0.isWhitespace }).count }
}
