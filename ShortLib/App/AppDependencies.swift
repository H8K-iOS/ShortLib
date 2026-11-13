import Foundation

/// Каким движком будет сделан пересказ.
enum SummaryEngineKind: Equatable {
    /// Свой ключ пользователя — напрямую в Anthropic, модели по выбору в Профиле.
    case ownKey
    /// Без ключа, через сервер-прокси ShortLib, пока есть бесплатный бюджет (только Haiku).
    case freeProxy
    /// Бесплатно и офлайн: «ключевые фразы».
    case extractive
}

/// Простой DI-контейнер. Подмена реализаций (моки, сервер с подпиской) — только здесь.
@MainActor
final class AppDependencies {
    let repository: BookRepositoryProtocol
    let epubParser: EPUBParsing
    let scraper: WebNovelScraping
    let preferences: Preferences
    private let engineOverride: SummaryEngine?
    private let proxyBaseURL: URL?
    private let quotaProvider: FreeQuotaProviding?

    /// Последний известный остаток бесплатного бюджета; `nil` — ещё не загружен или прокси выключен.
    private(set) var freeQuota: FreeQuota?

    /// Задачи пересказа живут здесь, а не в экранах: уход с экрана генерацию не обрывает.
    private(set) lazy var generation: SummaryGenerationService = {
        let service = SummaryGenerationService(repository: repository, scraper: scraper,
                                               engineFactory: { [unowned self] in self.makeSummaryEngine() })
        service.onJobFinished = { [unowned self] _ in
            Task { await self.refreshFreeQuota() }
        }
        return service
    }()

    init(repository: BookRepositoryProtocol = BookRepository(),
         epubParser: EPUBParsing = EPUBParser(),
         scraper: WebNovelScraping = WebNovelScraper(),
         preferences: Preferences = Preferences(),
         engineOverride: SummaryEngine? = nil,
         proxyBaseURL: URL? = ProxyConfig.baseURL,
         quotaProvider: FreeQuotaProviding? = nil) {
        self.repository = repository
        self.epubParser = epubParser
        self.scraper = scraper
        self.preferences = preferences
        self.engineOverride = engineOverride
        self.proxyBaseURL = proxyBaseURL
        self.quotaProvider = quotaProvider ?? proxyBaseURL.map {
            FreeQuotaClient(baseURL: $0, installId: InstallID.value, appVersion: ProxyConfig.appVersion)
        }
    }

    /// Свой ключ → напрямую; нет ключа, но есть бесплатный бюджет → прокси; иначе — «ключевые фразы».
    var engineKind: SummaryEngineKind {
        if engineOverride != nil { return .extractive }
        if preferences.hasAPIKey { return .ownKey }
        if proxyBaseURL != nil, freeQuota?.isAvailable == true { return .freeProxy }
        return .extractive
    }

    func makeSummaryEngine() -> SummaryEngine {
        if let engineOverride { return engineOverride }
        switch engineKind {
        case .ownKey:
            guard let key = preferences.apiKey else { return ExtractiveSummaryEngine() }
            let choice = preferences.modelChoice
            let config = LLMConfig(apiKey: key, chapterModel: choice.chapterModel, overviewModel: choice.overviewModel)
            return LLMSummaryEngine(client: AnthropicClient(config: config),
                                    chapterModel: config.chapterModel,
                                    overviewModel: config.overviewModel,
                                    engineLabel: "Claude · \(choice.title.lowercased())")
        case .freeProxy:
            guard let proxyBaseURL else { return ExtractiveSummaryEngine() }
            let config = LLMConfig.freeProxy(baseURL: proxyBaseURL, installId: InstallID.value,
                                             appVersion: ProxyConfig.appVersion)
            return LLMSummaryEngine(client: AnthropicClient(config: config),
                                    chapterModel: config.chapterModel,
                                    overviewModel: config.overviewModel,
                                    engineLabel: "Claude · бесплатно")
        case .extractive:
            return ExtractiveSummaryEngine()
        }
    }

    var usesLanguageModel: Bool { engineKind != .extractive }

    /// Обновляет остаток бесплатного бюджета. При ошибке сети оставляет прежнее значение.
    func refreshFreeQuota() async {
        guard engineOverride == nil, !preferences.hasAPIKey, let quotaProvider else { return }
        if let quota = try? await quotaProvider.fetchQuota() {
            freeQuota = quota
        }
    }

    func makeTestClient(apiKey: String) -> LLMClient {
        AnthropicClient(config: LLMConfig(apiKey: apiKey,
                                          chapterModel: LLMModelChoice.fast.chapterModel,
                                          overviewModel: LLMModelChoice.fast.overviewModel),
                        maxRetries: 0)
    }
}
