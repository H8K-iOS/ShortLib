import Foundation

/// Простой DI-контейнер. Подмена реализаций (моки, сервер с подпиской) — только здесь.
@MainActor
final class AppDependencies {
    let repository: BookRepositoryProtocol
    let epubParser: EPUBParsing
    let scraper: WebNovelScraping
    let preferences: Preferences
    private let engineOverride: SummaryEngine?

    init(repository: BookRepositoryProtocol = BookRepository(),
         epubParser: EPUBParsing = EPUBParser(),
         scraper: WebNovelScraping = WebNovelScraper(),
         preferences: Preferences = Preferences(),
         engineOverride: SummaryEngine? = nil) {
        self.repository = repository
        self.epubParser = epubParser
        self.scraper = scraper
        self.preferences = preferences
        self.engineOverride = engineOverride
    }

    /// Есть ключ API — пересказ своими словами через Claude. Нет — бесплатный режим «ключевые фразы».
    func makeSummaryEngine() -> SummaryEngine {
        if let engineOverride { return engineOverride }
        guard let key = preferences.apiKey else { return ExtractiveSummaryEngine() }
        let choice = preferences.modelChoice
        let config = LLMConfig(apiKey: key, chapterModel: choice.chapterModel, overviewModel: choice.overviewModel)
        return LLMSummaryEngine(client: AnthropicClient(config: config),
                                chapterModel: config.chapterModel,
                                overviewModel: config.overviewModel,
                                engineLabel: "Claude · \(choice.title.lowercased())")
    }

    var usesLanguageModel: Bool { engineOverride == nil && preferences.hasAPIKey }

    func makeTestClient(apiKey: String) -> LLMClient {
        AnthropicClient(config: LLMConfig(apiKey: apiKey,
                                          chapterModel: LLMModelChoice.fast.chapterModel,
                                          overviewModel: LLMModelChoice.fast.overviewModel),
                        maxRetries: 0)
    }
}
