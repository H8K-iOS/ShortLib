import Foundation

/// Простой DI-контейнер. Подмена реализаций (моки, LLM-движок) — только здесь.
@MainActor
final class AppDependencies {
    let repository: BookRepositoryProtocol
    let epubParser: EPUBParsing
    let scraper: WebNovelScraping
    let summaryEngine: SummaryEngine
    let preferences: Preferences

    init(repository: BookRepositoryProtocol = BookRepository(),
         epubParser: EPUBParsing = EPUBParser(),
         scraper: WebNovelScraping = WebNovelScraper(),
         summaryEngine: SummaryEngine = ExtractiveSummaryEngine(),
         preferences: Preferences = Preferences()) {
        self.repository = repository
        self.epubParser = epubParser
        self.scraper = scraper
        self.summaryEngine = summaryEngine
        self.preferences = preferences
    }
}
