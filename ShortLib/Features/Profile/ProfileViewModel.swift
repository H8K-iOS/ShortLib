import Foundation

@MainActor
final class ProfileViewModel: ObservableObject {
    enum KeyStatus: Equatable {
        case idle, checking, saved, failed(String)
    }

    @Published var keyInput = ""
    @Published private(set) var hasKey: Bool
    @Published private(set) var status: KeyStatus = .idle

    private let deps: AppDependencies
    private var task: Task<Void, Never>?

    init(deps: AppDependencies) {
        self.deps = deps
        hasKey = deps.preferences.hasAPIKey
    }

    var maskedKey: String {
        guard let key = deps.preferences.apiKey else { return "" }
        return "\(key.prefix(7))…\(key.suffix(4))"
    }

    var canSave: Bool {
        status != .checking && keyInput.trimmingCharacters(in: .whitespacesAndNewlines).count > 20
    }

    /// Сначала проверяем ключ коротким запросом, сохраняем только рабочий.
    func save() {
        let key = keyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        status = .checking
        task = Task { [weak self, deps] in
            do {
                _ = try await deps.makeTestClient(apiKey: key)
                    .complete(system: "Ответь одним словом.", prompt: "Привет", model: LLMModelChoice.fast.chapterModel, maxTokens: 5)
                deps.preferences.apiKey = key
                self?.keyInput = ""
                self?.hasKey = true
                self?.status = .saved
            } catch {
                self?.status = .failed(error.localizedDescription)
            }
        }
    }

    func removeKey() {
        deps.preferences.apiKey = nil
        hasKey = false
        status = .idle
    }
}
