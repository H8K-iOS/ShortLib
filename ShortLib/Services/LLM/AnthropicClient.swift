import Foundation

/// Настройки облачной модели: напрямую в Anthropic по ключу пользователя
/// или через свой сервер-прокси (бесплатный лимит, позже — подписка).
struct LLMConfig {
    enum Auth {
        /// Свой ключ пользователя (BYOK) — заголовок `x-api-key`.
        case apiKey(String)
        /// Сервер-прокси ShortLib: ключ разработчика только на сервере, устройство — по `installId`.
        case proxy(installId: String, appVersion: String)
    }

    static let anthropicEndpoint = URL(string: "https://api.anthropic.com/v1/messages")!

    var endpoint: URL
    var auth: Auth
    /// Модель для пересказа глав (много запросов — дешевле и быстрее).
    var chapterModel: String
    /// Модель для общей сводки и персонажей (один запрос — можно сильнее).
    var overviewModel: String

    init(apiKey: String, chapterModel: String, overviewModel: String) {
        self.endpoint = Self.anthropicEndpoint
        self.auth = .apiKey(apiKey)
        self.chapterModel = chapterModel
        self.overviewModel = overviewModel
    }

    /// Бесплатный режим через прокси: только Haiku (сервер отклонит другие модели).
    static func freeProxy(baseURL: URL, installId: String, appVersion: String) -> LLMConfig {
        var config = LLMConfig(apiKey: "", chapterModel: LLMModelChoice.fast.chapterModel,
                               overviewModel: LLMModelChoice.fast.overviewModel)
        config.endpoint = baseURL.appendingPathComponent("v1/messages")
        config.auth = .proxy(installId: installId, appVersion: appVersion)
        return config
    }

    var isProxy: Bool {
        if case .proxy = auth { return true }
        return false
    }
}

enum LLMModelChoice: String, CaseIterable, Identifiable {
    case fast, quality

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fast: return "Быстро"
        case .quality: return "Качество"
        }
    }

    var subtitle: String {
        switch self {
        case .fast: return "Haiku для глав и сводки — дешевле всего"
        case .quality: return "Haiku для глав, Sonnet для сводки и персонажей"
        }
    }

    var chapterModel: String { "claude-haiku-5-5" }
    var overviewModel: String { self == .fast ? "claude-haiku-5-5" : "claude-sonnet-5-5" }
}

protocol LLMClient {
    func complete(system: String, prompt: String, model: String, maxTokens: Int) async throws -> String
}

/// Клиент Anthropic Messages API. Повторяет запрос при перегрузке и лимитах.
struct AnthropicClient: LLMClient {
    enum APIError: LocalizedError {
        case invalidKey
        case noCredit
        case rateLimited
        case server(Int, String)
        case emptyResponse
        /// Прокси: бесплатный бюджет устройства исчерпан (402 `quota_exceeded`).
        case freeQuotaExceeded(String)
        /// Прокси: дневной потолок сервиса или долгий лимит по IP (`daily_cap`, `rate_limited`).
        case serviceLimit(String)
        /// Прочие ошибки прокси — текст уже на русском.
        case proxy(String)

        var errorDescription: String? {
            switch self {
            case .freeQuotaExceeded(let message), .serviceLimit(let message), .proxy(let message):
                return message
            case .invalidKey: return "Ключ API не подходит. Проверьте его в Профиле."
            case .noCredit: return "На балансе Anthropic закончились средства. Пополните его на console.anthropic.com."
            case .rateLimited: return "Слишком много запросов подряд. Подождите минуту и нажмите «Повторить»."
            case .server(let code, let message): return "Ошибка сервиса (\(code)): \(message)"
            case .emptyResponse: return "Модель вернула пустой ответ. Попробуйте ещё раз."
            }
        }
    }

    let config: LLMConfig
    var session: URLSession = .shared
    var maxRetries = 4

    func complete(system: String, prompt: String, model: String, maxTokens: Int) async throws -> String {
        var request = URLRequest(url: config.endpoint, timeoutInterval: 120)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        switch config.auth {
        case .apiKey(let key):
            request.setValue(key, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        case .proxy(let installId, let appVersion):
            request.setValue(installId, forHTTPHeaderField: "X-ShortLib-Install")
            request.setValue(appVersion, forHTTPHeaderField: "X-ShortLib-Version")
        }
        request.httpBody = try JSONEncoder().encode(MessagesRequest(
            model: model,
            max_tokens: maxTokens,
            system: system,
            messages: [.init(role: "user", content: prompt)],
            thinking: MessagesRequest.Thinking.off(for: model)
        ))

        var attempt = 0
        while true {
            try Task.checkCancellation()
            let (data, response) = try await session.data(for: request)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            let retryAfter = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "retry-after").flatMap { Double($0) }

            // Ошибки прокси ShortLib: {"error": {"code": "...", "message": "по-русски"}}.
            if config.isProxy, code != 200,
               let proxyError = (try? JSONDecoder().decode(ErrorResponse.self, from: data))?.error,
               let errorCode = proxyError.code {
                switch errorCode {
                case "quota_exceeded":
                    throw APIError.freeQuotaExceeded(proxyError.message)
                case "daily_cap":
                    throw APIError.serviceLimit(proxyError.message)
                case "rate_limited", "upstream_busy":
                    // Короткую паузу ждём сами, долгую (лимит по IP на сутки) — показываем пользователю.
                    let delay = retryAfter ?? pow(2, Double(attempt + 1))
                    attempt += 1
                    guard attempt <= maxRetries, delay <= 60 else {
                        throw errorCode == "rate_limited" ? APIError.serviceLimit(proxyError.message)
                                                         : APIError.server(code, proxyError.message)
                    }
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    continue
                default:
                    throw APIError.proxy(proxyError.message)
                }
            }

            switch code {
            case 200:
                let decoded = try JSONDecoder().decode(MessagesResponse.self, from: data)
                // stop_reason == "max_tokens" — не ошибка: возвращаем обрезанный текст как есть,
                // движок пересказа сам разбирает незакрытый тег.
                let text = decoded.content.compactMap(\.text).joined()
                guard !text.isEmpty else { throw APIError.emptyResponse }
                return text
            case 401, 403:
                throw APIError.invalidKey
            case 429, 500, 502, 503, 529:
                attempt += 1
                guard attempt <= maxRetries else {
                    throw code == 429 ? APIError.rateLimited : APIError.server(code, "сервис перегружен")
                }
                let delay = retryAfter ?? pow(2, Double(attempt)) // 2, 4, 8, 16 c
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            default:
                let message = (try? JSONDecoder().decode(ErrorResponse.self, from: data))?.error.message
                    ?? String(decoding: data.prefix(200), as: UTF8.self)
                if message.lowercased().contains("credit") { throw APIError.noCredit }
                throw APIError.server(code, message)
            }
        }
    }

    // MARK: - DTO

    private struct MessagesRequest: Encodable {
        struct Message: Encodable { let role: String; let content: String }
        /// Модели 5.5 по умолчанию тратят скрытые токены на размышления (оплачиваются как выход и съедают
        /// max_tokens). Разбор главы модель и так пишет в `<analysis>`, поэтому размышления выключаем.
        struct Thinking: Encodable {
            let type: String

            /// Haiku 5.5 — `disabled` (допустимо при effort ≤ high); Sonnet 5.5 на `disabled` отвечает 400,
            /// у него выключение — `between_tools`. Для прочих моделей поле не отправляем.
            static func off(for model: String) -> Thinking? {
                if model.hasPrefix("claude-haiku-5-5") { return Thinking(type: "disabled") }
                if model.hasPrefix("claude-sonnet-5-5") { return Thinking(type: "between_tools") }
                return nil
            }
        }
        let model: String
        let max_tokens: Int
        let system: String
        let messages: [Message]
        /// `nil` не кодируется (encodeIfPresent).
        let thinking: Thinking?
    }

    private struct MessagesResponse: Decodable {
        struct Block: Decodable { let type: String; let text: String? }
        let content: [Block]
        /// `end_turn`, `max_tokens`, `stop_sequence`, `refusal`…
        let stop_reason: String?
    }

    private struct ErrorResponse: Decodable {
        /// `code` — только у прокси ShortLib; у Anthropic вместо него `type`.
        struct Body: Decodable { let message: String; let code: String? }
        let error: Body
    }
}
