import Foundation

/// Настройки облачной модели. Чтобы перейти на подписку через свой сервер,
/// достаточно поменять `endpoint` на адрес прокси и передавать токен пользователя вместо ключа.
struct LLMConfig {
    var endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    var apiKey: String
    /// Модель для пересказа глав (много запросов — дешевле и быстрее).
    var chapterModel: String
    /// Модель для общей сводки и персонажей (один запрос — можно сильнее).
    var overviewModel: String
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

        var errorDescription: String? {
            switch self {
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
        request.setValue(config.apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.httpBody = try JSONEncoder().encode(MessagesRequest(
            model: model,
            max_tokens: maxTokens,
            system: system,
            messages: [.init(role: "user", content: prompt)]
        ))

        var attempt = 0
        while true {
            try Task.checkCancellation()
            let (data, response) = try await session.data(for: request)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0

            switch code {
            case 200:
                let decoded = try JSONDecoder().decode(MessagesResponse.self, from: data)
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
                let retryAfter = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "retry-after").flatMap { Double($0) }
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
        let model: String
        let max_tokens: Int
        let system: String
        let messages: [Message]
    }

    private struct MessagesResponse: Decodable {
        struct Block: Decodable { let type: String; let text: String? }
        let content: [Block]
    }

    private struct ErrorResponse: Decodable {
        struct Body: Decodable { let message: String }
        let error: Body
    }
}
