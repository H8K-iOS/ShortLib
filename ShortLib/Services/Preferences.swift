import Foundation

/// Настройки пользователя. Ключ API — в Keychain, остальное — в UserDefaults.
final class Preferences {
    static let detailLevelKey = "defaultDetailLevel"
    static let modelChoiceKey = "llmModelChoice"
    static let languageKey = "summaryLanguage"
    private static let apiKeyAccount = "anthropic_api_key"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    var defaultDetailLevel: DetailLevel {
        DetailLevel(rawValue: defaults.string(forKey: Self.detailLevelKey) ?? "") ?? .balanced
    }

    var modelChoice: LLMModelChoice {
        LLMModelChoice(rawValue: defaults.string(forKey: Self.modelChoiceKey) ?? "") ?? .quality
    }

    var summaryLanguage: SummaryLanguage {
        SummaryLanguage(rawValue: defaults.string(forKey: Self.languageKey) ?? "") ?? .russian
    }

    var apiKey: String? {
        get {
            let key = KeychainStore.get(Self.apiKeyAccount)?.trimmingCharacters(in: .whitespacesAndNewlines)
            return (key?.isEmpty ?? true) ? nil : key
        }
        set {
            if let newValue, !newValue.isEmpty {
                KeychainStore.set(newValue, for: Self.apiKeyAccount)
            } else {
                KeychainStore.delete(Self.apiKeyAccount)
            }
        }
    }

    var hasAPIKey: Bool { apiKey != nil }
}
