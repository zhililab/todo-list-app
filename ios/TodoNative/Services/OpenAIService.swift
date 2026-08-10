import Foundation

struct AIModelOption: Identifiable, Equatable, Hashable {
    let id: String
    let displayName: String

    init(_ id: String, displayName: String? = nil) {
        self.id = id
        self.displayName = displayName ?? id
    }
}

enum AIModelSelection: Equatable, Hashable {
    case preset(String)
    case custom

    fileprivate var storedValue: String {
        switch self {
        case .preset(let id): return "preset:\(id)"
        case .custom: return "custom"
        }
    }

    fileprivate init?(storedValue: String) {
        if storedValue == "custom" {
            self = .custom
        } else if storedValue.hasPrefix("preset:") {
            self = .preset(String(storedValue.dropFirst("preset:".count)))
        } else {
            return nil
        }
    }
}

// OpenAI-compatible providers and a deliberately short, discoverable model catalog.
struct AIProvider: Identifiable, Equatable {
    let id: String
    let name: String
    let baseURL: String
    let models: [AIModelOption]
    let defaultModelID: String

    var defaultModel: String { defaultModelID }

    static let registry: [AIProvider] = [
        AIProvider(id: "openai", name: "OpenAI", baseURL: "https://api.openai.com/v1", models: [.init("gpt-5.1"), .init("gpt-5-mini"), .init("gpt-4.1-mini")], defaultModelID: "gpt-4.1-mini"),
        AIProvider(id: "deepseek", name: "DeepSeek", baseURL: "https://api.deepseek.com", models: [.init("deepseek-v4-flash"), .init("deepseek-v4-pro")], defaultModelID: "deepseek-v4-flash"),
        AIProvider(id: "moonshot", name: "Moonshot (Kimi)", baseURL: "https://api.moonshot.cn/v1", models: [.init("kimi-k2.6"), .init("kimi-k2.5"), .init("moonshot-v1-8k")], defaultModelID: "moonshot-v1-8k"),
        AIProvider(id: "zhipu", name: "Zhipu GLM", baseURL: "https://open.bigmodel.cn/api/paas/v4", models: [.init("glm-5.2"), .init("glm-5.1"), .init("glm-4.5-flash")], defaultModelID: "glm-5.2"),
        AIProvider(id: "qwen", name: "Qwen", baseURL: "https://dashscope.aliyuncs.com/compatible-mode/v1", models: [.init("qwen-plus"), .init("qwen-turbo"), .init("qwen-max")], defaultModelID: "qwen-plus"),
        AIProvider(id: "groq", name: "Groq", baseURL: "https://api.groq.com/openai/v1", models: [.init("llama-3.3-70b-versatile"), .init("llama-3.1-8b-instant"), .init("openai/gpt-oss-120b")], defaultModelID: "llama-3.3-70b-versatile"),
        AIProvider(id: "siliconflow", name: "SiliconFlow", baseURL: "https://api.siliconflow.cn/v1", models: [.init("deepseek-ai/DeepSeek-V3.2"), .init("Qwen/Qwen3.5-27B"), .init("Pro/zai-org/GLM-5")], defaultModelID: "deepseek-ai/DeepSeek-V3.2"),
        AIProvider(id: "custom", name: "Custom", baseURL: "", models: [], defaultModelID: "")
    ]

    static func provider(id: String) -> AIProvider {
        registry.first { $0.id == id } ?? registry[0]
    }
}

enum OpenAIService {
    private static let defaultProviderID = "openai"
    static let managedModelID = "deepseek-v4-flash"

    static let providerKey = "ai_provider"
    static let baseURLKey = "ai_base_url"
    static let modelKey = "ai_model"
    static let keyStorageKey = "openai_api_key"
    static let migrationKey = "ai_provider_scoped_config_migrated"

    static func apiKey() -> String {
        UserDefaults.standard.string(forKey: keyStorageKey) ?? ""
    }

    static func saveAPIKey(_ key: String) {
        UserDefaults.standard.set(key.trimmingCharacters(in: .whitespacesAndNewlines), forKey: keyStorageKey)
    }

    static func providerID() -> String {
        let id = UserDefaults.standard.string(forKey: providerKey) ?? defaultProviderID
        return AIProvider.registry.contains { $0.id == id } ? id : defaultProviderID
    }

    static func saveProviderID(_ id: String) {
        UserDefaults.standard.set(id, forKey: providerKey)
    }

    private static func selectionKey(providerID: String) -> String {
        "ai_model_selection.\(providerID)"
    }

    private static func customModelKey(providerID: String) -> String {
        "ai_custom_model.\(providerID)"
    }

    private static func customBaseURLKey(providerID: String) -> String {
        "ai_custom_base_url.\(providerID)"
    }

    private static func migrateLegacyIfNeeded() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: migrationKey) else { return }
        let legacyModel = (defaults.string(forKey: modelKey) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let legacyBaseURL = (defaults.string(forKey: baseURLKey) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let migrationProviderID = legacyMigrationProviderID(defaults: defaults, legacyBaseURL: legacyBaseURL)
        if !legacyModel.isEmpty {
            defaults.set(AIModelSelection.custom.storedValue, forKey: selectionKey(providerID: migrationProviderID))
            defaults.set(legacyModel, forKey: customModelKey(providerID: migrationProviderID))
        }
        if !legacyBaseURL.isEmpty {
            defaults.set(legacyBaseURL, forKey: customBaseURLKey(providerID: migrationProviderID))
        }
        defaults.set(true, forKey: migrationKey)
    }

    private static func legacyMigrationProviderID(defaults: UserDefaults, legacyBaseURL: String) -> String {
        if let storedProviderID = defaults.string(forKey: providerKey) {
            return AIProvider.registry.contains { $0.id == storedProviderID }
                ? storedProviderID
                : "custom"
        }
        return legacyBaseURL.isEmpty ? defaultProviderID : "custom"
    }

    static func modelSelection(providerID: String) -> AIModelSelection {
        migrateLegacyIfNeeded()
        let provider = AIProvider.provider(id: providerID)
        guard provider.id != "custom" else { return .custom }
        guard let stored = UserDefaults.standard.string(forKey: selectionKey(providerID: providerID)),
              let selection = AIModelSelection(storedValue: stored) else {
            return .preset(provider.defaultModelID)
        }
        if case .preset(let id) = selection, !provider.models.contains(where: { $0.id == id }) {
            return .preset(provider.defaultModelID)
        }
        return selection
    }

    static func saveModelSelection(_ selection: AIModelSelection, providerID: String) {
        UserDefaults.standard.set(selection.storedValue, forKey: selectionKey(providerID: providerID))
    }

    static func customBaseURL(providerID: String) -> String {
        migrateLegacyIfNeeded()
        return UserDefaults.standard.string(forKey: customBaseURLKey(providerID: providerID)) ?? ""
    }

    static func customModel(providerID: String) -> String {
        migrateLegacyIfNeeded()
        return UserDefaults.standard.string(forKey: customModelKey(providerID: providerID)) ?? ""
    }

    static func saveCustomBaseURL(_ url: String, providerID: String) {
        UserDefaults.standard.set(url.trimmingCharacters(in: .whitespacesAndNewlines), forKey: customBaseURLKey(providerID: providerID))
    }

    static func saveCustomModel(_ model: String, providerID: String) {
        UserDefaults.standard.set(model.trimmingCharacters(in: .whitespacesAndNewlines), forKey: customModelKey(providerID: providerID))
    }

    static func customBaseURL() -> String { customBaseURL(providerID: providerID()) }
    static func customModel() -> String { customModel(providerID: providerID()) }
    static func saveCustomBaseURL(_ url: String) { saveCustomBaseURL(url, providerID: providerID()) }
    static func saveCustomModel(_ model: String) { saveCustomModel(model, providerID: providerID()) }

    // 解析生效的 Base URL 与模型（优先用户自定义值）
    static func activeConfig() -> (baseURL: String, model: String) {
        let provider = AIProvider.provider(id: providerID())
        let scopedBaseURL = customBaseURL(providerID: provider.id)
        let baseURL = scopedBaseURL.isEmpty ? provider.baseURL : scopedBaseURL
        let model: String
        switch modelSelection(providerID: provider.id) {
        case .custom:
            let custom = customModel(providerID: provider.id)
            model = custom.isEmpty ? provider.defaultModelID : custom
        case .preset(let id):
            model = provider.models.contains { $0.id == id } ? id : provider.defaultModelID
        }
        return (baseURL, model)
    }

    // 与 web app.js callOpenAI 保持一致（OpenAI 兼容 /chat/completions）
    // 适配：无 Key 且配置了额度代理时走 QuotaClient；否则直连原逻辑
    static func callOpenAI(promptText: String, instructionText: String) async throws -> String? {
        try await callOpenAIWithSource(
            promptText: promptText,
            instructionText: instructionText
        ).text
    }

    static func callOpenAIWithSource(
        promptText: String,
        instructionText: String
    ) async throws -> (text: String?, source: AIAssistantSource) {
        let messages: [[String: Any]] = [
            ["role": "system", "content": instructionText],
            ["role": "user", "content": promptText]
        ]
        return try await callChatWithSource(messages: messages)
    }

    // 统一入口：QuotaClient.baseURL 已配置且用户未填 API Key → 走 app 托管额度代理；
    // 否则走原直连逻辑。
    static func callChat(messages: [[String: Any]]) async throws -> String? {
        try await callChatWithSource(messages: messages).text
    }

    private static func callChatWithSource(
        messages: [[String: Any]]
    ) async throws -> (text: String?, source: AIAssistantSource) {
        if QuotaClient.baseURL != nil && apiKey().isEmpty {
            let body: [String: Any] = [
                "model": managedModelID,
                "messages": messages,
                "stream": false
            ]
            let json = try await QuotaClient.chat(body: body)
            return (extractOutputText(from: json), .managed)
        }
        return (try await directCall(messages: messages), .custom)
    }

    private static func directCall(messages: [[String: Any]]) async throws -> String? {
        let key = apiKey().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return nil }

        let config = activeConfig()
        guard !config.baseURL.isEmpty else { throw OpenAIError.noBaseURL }
        guard !config.model.isEmpty else { throw OpenAIError.noModel }

        let trimmed = config.baseURL.hasSuffix("/") ? String(config.baseURL.dropLast()) : config.baseURL
        guard let url = URL(string: "\(trimmed)/chat/completions") else {
            throw OpenAIError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")

        let body: [String: Any] = [
            "model": config.model,
            "messages": messages
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let message = String(data: data, encoding: .utf8) ?? ""
            throw OpenAIError.requestFailed(status: status, message: message)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw OpenAIError.invalidResponse
        }
        guard let text = extractOutputText(from: json), !text.isEmpty else {
            throw OpenAIError.emptyOutput
        }
        return text
    }

    // 与 web app.js extractOutputText 保持一致：兼容 chat/completions 与 legacy responses
    static func extractOutputText(from data: [String: Any]) -> String? {
        if let outputText = data["output_text"] as? String,
           !outputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return outputText.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // chat/completions 格式：choices[0].message.content
        if let choices = data["choices"] as? [[String: Any]],
           let choice = choices.first,
           let message = choice["message"] as? [String: Any] {
            if let content = message["content"] as? String,
               !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return content.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if let parts = message["content"] as? [[String: Any]] {
                let joined = parts
                    .compactMap { $0["text"] as? String }
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .joined(separator: "\n")
                return joined.isEmpty ? nil : joined
            }
        }

        guard let output = data["output"] as? [[String: Any]] else { return nil }

        var chunks: [String] = []
        for item in output {
            guard let content = item["content"] as? [[String: Any]] else { continue }
            for chunk in content {
                if let type = chunk["type"] as? String, type == "output_text",
                   let text = chunk["text"] as? String {
                    chunks.append(text.trimmingCharacters(in: .whitespacesAndNewlines))
                }
            }
        }
        let joined = chunks.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return joined.isEmpty ? nil : joined
    }

    enum OpenAIError: LocalizedError, Sendable {
        case requestFailed(status: Int, message: String)
        case invalidResponse
        case emptyOutput
        case noBaseURL
        case noModel

        var errorDescription: String? {
            switch self {
            case .requestFailed(let status, let message):
                return Localization.t("ai.error.requestFailed", status, message)
            case .invalidResponse, .emptyOutput:
                return Localization.t("ai.error.empty")
            case .noBaseURL:
                return Localization.t("ai.error.noBaseURL")
            case .noModel:
                return Localization.t("ai.error.noModel")
            }
        }
    }
}
