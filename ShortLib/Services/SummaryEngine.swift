import Foundation
import NaturalLanguage

protocol SummaryEngine {
    /// Пересказывает главы из `preset.chapterRange`. Тексты глав должны быть уже загружены.
    func summarize(book: Book,
                   preset: SummaryPreset,
                   progress: @escaping @Sendable (SummaryProgress) -> Void) async throws -> Summary
}

/// Локальный экстрактивный пересказ: выбирает самые «весомые» предложения каждой главы.
/// Работает офлайн и бесплатно. Для пересказа своими словами подключите LLMSummaryEngine
/// с тем же протоколом — экраны менять не придётся.
struct ExtractiveSummaryEngine: SummaryEngine {

    func summarize(book: Book,
                   preset: SummaryPreset,
                   progress: @escaping @Sendable (SummaryProgress) -> Void) async throws -> Summary {
        let chapters = book.chapters.filter { preset.chapterRange.contains($0.index) }

        // nonisolated async: выполняется вне главного потока, отмена задачи пробрасывается.
        var result: [ChapterSummary] = []
        for (i, chapter) in chapters.enumerated() {
            try Task.checkCancellation()
            await Task.yield()
            let text = Self.summarize(text: chapter.text, ratio: preset.ratio, focus: preset.focus)
            result.append(ChapterSummary(index: chapter.index, title: chapter.title, text: text))
            progress(SummaryProgress(stage: .summarizing, done: i + 1, total: chapters.count))
        }

        progress(SummaryProgress(stage: .overview, done: 0, total: 1))
        let joined = result.map(\.text).joined(separator: " ")
        let overview = Self.summarize(text: joined, ratio: 0.25, focus: preset.focus, maxSentences: 8)
        progress(SummaryProgress(stage: .overview, done: 1, total: 1))

        return Summary(preset: preset, overview: overview, chapters: result, createdAt: Date(), engine: "Ключевые фразы")
    }

    // MARK: - Algorithm

    static func summarize(text: String, ratio: Double, focus: Set<SummaryFocus>, maxSentences: Int = .max) -> String {
        let sentences = split(text)
        guard sentences.count > 2 else { return sentences.joined(separator: " ") }

        let frequencies = wordFrequencies(text)
        let names = focus.contains(.characters) ? properNames(text) : []

        let scored: [(index: Int, score: Double)] = sentences.enumerated().map { (i, s) -> (index: Int, score: Double) in
            let words = tokens(s)
            guard !words.isEmpty else { return (i, 0.0) }
            var score = words.reduce(0.0) { $0 + (frequencies[$1] ?? 0) } / Double(words.count)
            if i == 0 { score *= 1.3 }                                       // начало главы задаёт сцену
            if focus.contains(.characters), words.contains(where: names.contains) { score *= 1.25 }
            if focus.contains(.quotes), s.contains("«") || s.contains("\"") || s.hasPrefix("—") { score *= 1.3 }
            return (i, score)
        }

        let targetWords = Double(text.split(separator: " ").count) * ratio
        var picked: [Int] = []
        var words = 0.0
        for item in scored.sorted(by: { $0.score > $1.score }) {
            picked.append(item.index)
            words += Double(sentences[item.index].split(separator: " ").count)
            if words >= targetWords || picked.count >= maxSentences { break }
        }
        return picked.sorted().map { sentences[$0] }.joined(separator: " ")
    }

    private static func split(_ text: String) -> [String] {
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        return tokenizer.tokens(for: text.startIndex..<text.endIndex)
            .map { text[$0].trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func tokens(_ text: String) -> [String] {
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text
        return tokenizer.tokens(for: text.startIndex..<text.endIndex)
            .map { text[$0].lowercased() }
            .filter { $0.count > 3 }
    }

    private static func wordFrequencies(_ text: String) -> [String: Double] {
        var counts: [String: Double] = [:]
        for w in tokens(text) { counts[w, default: 0] += 1 }
        let maxCount = counts.values.max() ?? 1
        return counts.mapValues { $0 / maxCount }
    }

    private static func properNames(_ text: String) -> Set<String> {
        let tagger = NLTagger(tagSchemes: [.nameType])
        tagger.string = text
        var names = Set<String>()
        tagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .word, scheme: .nameType,
                             options: [.omitPunctuation, .omitWhitespace, .joinNames]) { tag, range in
            if tag == .personalName { names.insert(text[range].lowercased()) }
            return true
        }
        return names
    }
}
