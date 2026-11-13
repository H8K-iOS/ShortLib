import Foundation

/// Адрес сервера-прокси ShortLib (Cloudflare Worker, папка `server/`).
/// Задаётся ключом `ShortLibProxyURL` в Info.plist; пустая строка — бесплатный режим выключен.
enum ProxyConfig {
    static var baseURL: URL? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "ShortLibProxyURL") as? String else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let url = URL(string: trimmed), url.scheme == "https" else { return nil }
        return url
    }

    /// Значение заголовка `X-ShortLib-Version`, например `1.0 (7)`.
    static var appVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "0"
        let build = info?["CFBundleVersion"] as? String ?? "0"
        return "\(version) (\(build))"
    }
}

/// Анонимный идентификатор установки. Лежит в Keychain, поэтому переживает переустановку приложения.
enum InstallID {
    private static let account = "shortlib_install_id"

    static var value: String {
        if let stored = KeychainStore.get(account), UUID(uuidString: stored) != nil {
            return stored
        }
        let id = UUID().uuidString.lowercased()
        KeychainStore.set(id, for: account)
        return id
    }
}

/// Остаток бесплатного бюджета устройства — ответ `GET /v1/quota`.
struct FreeQuota: Decodable, Equatable, Sendable {
    /// Оценка числа глав по остатку токенов. Точный учёт глав — на клиенте.
    let chaptersLeft: Int
    let tokensLeft: Int
    let plan: String

    var isAvailable: Bool { tokensLeft > 0 }
}

protocol FreeQuotaProviding: Sendable {
    func fetchQuota() async throws -> FreeQuota
}

struct FreeQuotaClient: FreeQuotaProviding, Sendable {
    let baseURL: URL
    let installId: String
    let appVersion: String
    var session: URLSession = .shared

    func fetchQuota() async throws -> FreeQuota {
        var request = URLRequest(url: baseURL.appendingPathComponent("v1/quota"), timeoutInterval: 8)
        request.setValue(installId, forHTTPHeaderField: "X-ShortLib-Install")
        request.setValue(appVersion, forHTTPHeaderField: "X-ShortLib-Version")
        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return try JSONDecoder().decode(FreeQuota.self, from: data)
    }
}
