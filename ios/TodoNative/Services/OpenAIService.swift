import Foundation

// 与 web app.js AI_PROVIDERS 对齐
struct AIProvider: Identifiable, Equatable {
    let id: String
    let name: String
    let baseURL: String
    let defaultModel: String

    static let registry: [AIProvider] = [
        AIProvider(id: "openai", name: "OpenAI", baseURL: "https://api.openai.com/v1", defaultModel: "gpt-4.1-mini"),
        AIProvider(id: "deepseek", name: "DeepSeek", baseURL: "https://api.deepseek.com", defaultModel: "deepseek-chat"),
        AIProvider(id: "moonshot", name: "Moonshot (Kimi)", baseURL: "https://api.moonshot.cn/v1", defaultModel: "moonshot-v1-8k"),
        AIProvider(id: "zhipu", name: "Zhipu GLM", baseURL: "https://open.bigmodel.cn/api/paas/v4", defaultModel: "glm-4-flash"),
        AIProvider(id: "qwen", name: "Qwen", baseURL: "https://dashscope.aliyuncs.com/compatible-mode/v1", defaultModel: "qwen-plus"),
        AIProvider(id: "groq", name: "Groq", baseURL: "https://api.groq.com/openai/v1", defaultModel: "llama-3.3-70b-versatile"),
        AIProvider(id: "siliconflow", name: "SiliconFlow", baseURL: "https://api.siliconflow.cn/v1", defaultModel: "deepseek-ai/DeepSeek-V3"),
        AIProvider(id: "custom", name: "Custom", baseURL: "", defaultModel: "")
    ]

    static func provider(id: String) -> AIProvider {
        registry.first { $0.id == id } ?? registry[0]
    }
}

enum OpenAIService {
    private static let defaultProviderID = "openai"

    static let providerKey = "ai_provider"
    static let baseURLKey = "ai_base_url"
    static let modelKey = "ai_model"
    static let keyStorageKey = "openai_api_key"

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

    static func customBaseURL() -> String {
        UserDefaults.standard.string(forKey: baseURLKey) ?? ""
    }

    static func customModel() -> String {
        UserDefaults.standard.string(forKey: modelKey) ?? ""
    }

    static func saveCustomBaseURL(_ url: String) {
        UserDefaults.standard.set(url.trimmingCharacters(in: .whitespacesAndNewlines), forKey: baseURLKey)
    }

    static func saveCustomModel(_ model: String) {
        UserDefaults.standard.set(model.trimmingCharacters(in: .whitespacesAndNewlines), forKey: modelKey)
    }

    // 解析生效的 Base URL 与模型（优先用户自定义值）
    static func activeConfig() -> (baseURL: String, model: String) {
        let provider = AIProvider.provider(id: providerID())
        let baseURL = customBaseURL().isEmpty ? provider.baseURL : customBaseURL()
        let model = customModel().isEmpty ? provider.defaultModel : customModel()
        return (baseURL, model)
    }

    // 与 web app.js callOpenAI 保持一致（OpenAI 兼容 /chat/completions）
    static func callOpenAI(promptText: String, instructionText: String) async throws -> String? {
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
            "messages": [
                ["role": "system", "content": instructionText],
                ["role": "user", "content": promptText]
            ]
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
