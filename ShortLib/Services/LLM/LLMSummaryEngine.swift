import Foundation

/// Пересказ своими словами через языковую модель.
///
/// Алгоритм:
/// 1. Главы идут по порядку. В каждый запрос передаётся «память сюжета» (персонажи, линии, факты)
///    и пересказ предыдущей главы — так модель понимает контекст и напоминает о прошлых событиях.
///    После главы модель возвращает обновлённую память.
/// 2. Длинная глава сначала делится на части, по каждой делаются заметки, потом из заметок — пересказ.
/// 3. Если спойлеры разрешены, второй проход сопоставляет каждую главу с соседними (2 до, 3 после)
///    и добавляет связи: что подготовлено раньше, что раскроется позже.
/// 4. Общая сводка и персонажи. Для больших книг — сначала сводки арок по 15 глав.
struct LLMSummaryEngine: SummaryEngine {
    let client: LLMClient
    let chapterModel: String
    let overviewModel: String
    let engineLabel: String

    /// Глава длиннее этого делится на части (≈ 12–15 тыс. токенов на часть).
    var chunkWords = 8_000
    /// Сколько запросов второго прохода идёт параллельно.
    var connectionConcurrency = 3

    func summarize(book: Book,
                   preset: SummaryPreset,
                   resume: PartialSummary?,
                   progress: @escaping @Sendable (SummaryProgress) -> Void,
                   onPartial: @escaping @Sendable (PartialSummary) -> Void) async throws -> Summary {
        // Главы без текста пропускаются: сервис пересказа загружает их до вызова движка.
        let chapters = book.chapters.filter { preset.chapterRange.contains($0.index) && $0.isLoaded }
        let system = Prompts.system(preset: preset, bookTitle: book.title, author: book.author)

        // 1. Пересказ по главам с памятью сюжета. При продолжении — с сохранённого места.
        let resumed = validResume(resume, for: preset)
        var memory = resumed?.memory ?? ""
        var results: [ChapterSummary] = resumed?.chapters ?? []
        var previous = results.last?.text ?? ""
        let startIndex = resumed?.nextChapterIndex ?? preset.chapterRange.lowerBound
        progress(SummaryProgress(stage: .summarizing, done: results.count, total: chapters.count))

        // Любая ошибка (в том числе конец бесплатного лимита) пробрасывается наверх: готовые главы уже сохранены
        // через onPartial, их можно читать, а пересказ — продолжить с этого места (например, со своим ключом).
        for (i, chapter) in chapters.enumerated() where chapter.index >= startIndex {
            try Task.checkCancellation()
            let target = preset.targetWords(forChapterWords: chapter.wordCount)
            let (input, isNotes) = try await prepare(chapter, memory: memory, target: target, system: system)

            // Запас: пересказ + скрытый разбор (≈ 400 токенов) + память сюжета (≈ 1 100).
            let response = try await client.complete(
                system: system,
                prompt: Prompts.chapter(index: chapter.index, title: chapter.title, text: input, isNotes: isNotes,
                                        level: preset.level, memory: memory, previousSummary: previous,
                                        targetWords: target),
                model: chapterModel,
                maxTokens: tokens(forWords: target) + Self.analysisTokens + 1_100
            )
            let summary = TagParser.value("summary", in: response) ?? Self.stripService(response)
            memory = TagParser.value("memory", in: response) ?? memory
            previous = summary
            results.append(ChapterSummary(index: chapter.index, title: chapter.title, text: summary))
            onPartial(PartialSummary(preset: preset, chapters: results, memory: memory, updatedAt: Date()))
            progress(SummaryProgress(stage: .summarizing, done: i + 1, total: chapters.count))
        }

        // 2. Связи между главами (только если спойлеры разрешены)
        if !preset.noSpoilers, results.count > 1 {
            results = try await addConnections(to: results, system: system, progress: progress)
        } else {
            progress(SummaryProgress(stage: .connecting, done: 1, total: 1))
        }

        // 3. Общая сводка и персонажи
        progress(SummaryProgress(stage: .overview, done: 0, total: 1))
        let (overview, characters) = try await makeOverview(results, memory: memory, preset: preset, system: system)
        progress(SummaryProgress(stage: .overview, done: 1, total: 1))

        return Summary(preset: preset, overview: overview, chapters: results, createdAt: Date(),
                       characters: characters, engine: engineLabel)
    }

    // MARK: - Steps

    /// Короткая глава уходит целиком; длинная — заметками по частям.
    private func prepare(_ chapter: Chapter, memory: String, target: Int, system: String) async throws -> (String, Bool) {
        let parts = Self.split(chapter.text, maxWords: chunkWords)
        guard parts.count > 1 else { return (chapter.text, false) }

        var notes: [String] = []
        for (i, part) in parts.enumerated() {
            try Task.checkCancellation()
            let partTarget = max(150, target * 2 / parts.count)
            let response = try await client.complete(
                system: system,
                prompt: Prompts.chunk(part: i + 1, of: parts.count, chapterTitle: chapter.title,
                                      text: part, memory: memory, targetWords: partTarget),
                model: chapterModel,
                maxTokens: tokens(forWords: partTarget) + 300
            )
            notes.append("Часть \(i + 1):\n" + (TagParser.value("notes", in: response) ?? response))
        }
        return (notes.joined(separator: "\n\n"), true)
    }

    private func addConnections(to results: [ChapterSummary], system: String,
                                progress: @escaping @Sendable (SummaryProgress) -> Void) async throws -> [ChapterSummary] {
        let short = results.map { ($0.index, Self.firstSentences($0.text, maxWords: 80)) }
        var updated = results
        var done = 0
        progress(SummaryProgress(stage: .connecting, done: 0, total: results.count))

        try await withThrowingTaskGroup(of: (Int, String?).self) { group in
            var next = 0
            func enqueue(_ i: Int) {
                let earlier = Array(short[max(0, i - 2)..<i])
                let later = Array(short[(i + 1)..<min(short.count, i + 4)])
                let item = results[i]
                group.addTask {
                    let response = try await client.complete(
                        system: system,
                        prompt: Prompts.connections(index: item.index, summary: item.text, earlier: earlier, later: later),
                        model: chapterModel,
                        maxTokens: 300
                    )
                    let links = TagParser.value("links", in: response)
                    let isEmpty = links == nil || links!.lowercased().hasPrefix("нет")
                    return (i, isEmpty ? nil : links)
                }
            }
            while next < min(connectionConcurrency, results.count) { enqueue(next); next += 1 }
            while let (i, links) = try await group.next() {
                updated[i].connections = links
                done += 1
                progress(SummaryProgress(stage: .connecting, done: done, total: results.count))
                if next < results.count { enqueue(next); next += 1 }
            }
        }
        return updated
    }

    private func makeOverview(_ results: [ChapterSummary], memory: String, preset: SummaryPreset,
                              system: String) async throws -> (String, [CharacterNote]) {
        let totalWords = results.reduce(0) { $0 + $1.text.split(separator: " ").count }
        let target = min(1_200, max(150, totalWords / 4))

        var material: String
        if totalWords > 12_000 {
            // Большая книга: сначала арки по 15 глав, затем сводка по аркам.
            var arcs: [String] = []
            for start in stride(from: 0, to: results.count, by: 15) {
                try Task.checkCancellation()
                let slice = results[start..<min(results.count, start + 15)]
                let text = slice.map { "Глава \($0.index). \($0.title)\n\($0.text)" }.joined(separator: "\n\n")
                let response = try await client.complete(
                    system: system,
                    prompt: Prompts.arc(fromChapter: slice.first!.index, toChapter: slice.last!.index,
                                        summaries: text, targetWords: 400),
                    model: chapterModel,
                    maxTokens: tokens(forWords: 400) + 200
                )
                arcs.append("Главы \(slice.first!.index)–\(slice.last!.index):\n" + (TagParser.value("arc", in: response) ?? response))
            }
            material = arcs.joined(separator: "\n\n")
        } else {
            material = results.map { "Глава \($0.index). \($0.title)\n\($0.text)" }.joined(separator: "\n\n")
        }

        let response = try await client.complete(
            system: system,
            prompt: Prompts.overview(material: material, memory: memory, targetWords: target),
            model: overviewModel,
            maxTokens: tokens(forWords: target) + 1_200
        )
        let overview = TagParser.value("overview", in: response) ?? response
        return (overview, TagParser.characters(in: response))
    }

    // MARK: - Helpers

    /// Русский текст ≈ 2,5–3 токена на слово; берём с запасом.
    private func tokens(forWords words: Int) -> Int { min(8_000, Int(Double(words) * 3.2)) }

    /// Скрытый разбор главы перед пересказом (до 120 слов).
    static let analysisTokens = 400

    /// Если модель не закрыла тег <summary>, убираем из ответа служебные блоки, чтобы читатель их не увидел.
    static func stripService(_ response: String) -> String {
        var text = response
        for tag in ["analysis", "memory"] {
            while let open = text.range(of: "<\(tag)>") {
                let end = text.range(of: "</\(tag)>", range: open.upperBound..<text.endIndex)?.upperBound ?? text.endIndex
                text.removeSubrange(open.lowerBound..<end)
            }
        }
        return text.replacingOccurrences(of: "<summary>", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Делит текст на части по абзацам, не разрывая их.
    static func split(_ text: String, maxWords: Int) -> [String] {
        let paragraphs = text.components(separatedBy: "\n\n")
        var parts: [String] = []
        var current: [String] = []
        var count = 0
        for p in paragraphs {
            let words = p.split(whereSeparator: { $0.isWhitespace }).count
            if count + words > maxWords, !current.isEmpty {
                parts.append(current.joined(separator: "\n\n"))
                current = []
                count = 0
            }
            current.append(p)
            count += words
        }
        if !current.isEmpty { parts.append(current.joined(separator: "\n\n")) }
        return parts
    }

    static func firstSentences(_ text: String, maxWords: Int) -> String {
        let words = text.split(separator: " ")
        guard words.count > maxWords else { return text }
        return words.prefix(maxWords).joined(separator: " ") + "…"
    }
}

/// Оценка объёма работы для экрана настроек.
struct SummaryCostEstimate {
    let requests: Int
    let inputTokens: Int
    let outputTokens: Int

    init(book: Book, preset: SummaryPreset) {
        let chapters = book.chapters.filter { preset.chapterRange.contains($0.index) }
        let words = chapters.map { $0.isLoaded ? $0.wordCount : 3_000 }
        let totalWords = words.reduce(0, +)
        let summaryWords = words.map { preset.targetWords(forChapterWords: $0) }.reduce(0, +)
        let chunks = words.map { max(1, Int(ceil(Double($0) / 8_000))) }.map { $0 > 1 ? $0 : 0 }.reduce(0, +)
        let connections = preset.noSpoilers ? 0 : chapters.count
        let arcs = summaryWords > 12_000 ? Int(ceil(Double(chapters.count) / 15)) : 0

        requests = chapters.count + chunks + connections + arcs + 1
        // Вход: текст глав + память и предыдущий пересказ в каждом запросе + системный промпт.
        inputTokens = Int(Double(totalWords) * 2.8) + chapters.count * 1_800 + connections * 1_200 + summaryWords * 3
        // Выход: пересказы + скрытый разбор и память в каждой главе + связи + сводка.
        outputTokens = Int(Double(summaryWords) * 2.8)
            + chapters.count * (450 + LLMSummaryEngine.analysisTokens) + connections * 80 + 2_000
    }

    var text: String {
        "≈ \(requests) запросов · \(format(inputTokens)) токенов на входе · \(format(outputTokens)) на выходе"
    }

    private func format(_ n: Int) -> String {
        n >= 1_000_000 ? String(format: "%.1f млн", Double(n) / 1_000_000)
            : n >= 1_000 ? "\(n / 1_000) тыс." : "\(n)"
    }
}
