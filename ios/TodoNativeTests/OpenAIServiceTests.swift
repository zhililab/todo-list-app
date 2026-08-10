import XCTest
@testable import TodoNative

private final class OpenAIRouteMockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

@MainActor
final class OpenAIServiceTests: XCTestCase {
    private let providerKey = "ai_provider"
    private let baseURLKey = "ai_base_url"
    private let modelKey = "ai_model"
    private let migrationKey = "ai_provider_scoped_config_migrated"

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: providerKey)
        UserDefaults.standard.removeObject(forKey: baseURLKey)
        UserDefaults.standard.removeObject(forKey: modelKey)
        UserDefaults.standard.removeObject(forKey: migrationKey)
        for provider in AIProvider.registry {
            UserDefaults.standard.removeObject(forKey: "ai_model_selection.\(provider.id)")
            UserDefaults.standard.removeObject(forKey: "ai_custom_model.\(provider.id)")
            UserDefaults.standard.removeObject(forKey: "ai_custom_base_url.\(provider.id)")
        }
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: providerKey)
        UserDefaults.standard.removeObject(forKey: baseURLKey)
        UserDefaults.standard.removeObject(forKey: modelKey)
        UserDefaults.standard.removeObject(forKey: migrationKey)
        for provider in AIProvider.registry {
            UserDefaults.standard.removeObject(forKey: "ai_model_selection.\(provider.id)")
            UserDefaults.standard.removeObject(forKey: "ai_custom_model.\(provider.id)")
            UserDefaults.standard.removeObject(forKey: "ai_custom_base_url.\(provider.id)")
        }
        super.tearDown()
    }

    func testProviderRegistryContainsWebProviders() {
        XCTAssertTrue(AIProvider.registry.contains { $0.id == "openai" })
        XCTAssertTrue(AIProvider.registry.contains { $0.id == "deepseek" })
        XCTAssertTrue(AIProvider.registry.contains { $0.id == "moonshot" })
        XCTAssertTrue(AIProvider.registry.contains { $0.id == "zhipu" })
        XCTAssertTrue(AIProvider.registry.contains { $0.id == "qwen" })
        XCTAssertTrue(AIProvider.registry.contains { $0.id == "groq" })
        XCTAssertTrue(AIProvider.registry.contains { $0.id == "siliconflow" })
        XCTAssertTrue(AIProvider.registry.contains { $0.id == "custom" })
    }

    func testDefaultProviderIsOpenAI() {
        XCTAssertEqual(OpenAIService.providerID(), "openai")
        let config = OpenAIService.activeConfig()
        XCTAssertEqual(config.baseURL, "https://api.openai.com/v1")
        XCTAssertEqual(config.model, "gpt-4.1-mini")
    }

    func testDeepSeekDefaults() {
        XCTAssertEqual(AIProvider.provider(id: "deepseek").baseURL, "https://api.deepseek.com")
        XCTAssertEqual(AIProvider.provider(id: "deepseek").defaultModel, "deepseek-v4-flash")
        XCTAssertEqual(AIProvider.provider(id: "deepseek").models.map(\.id), [
            "deepseek-v4-flash",
            "deepseek-v4-pro"
        ])
    }

    func testCustomOverridesProviderDefaults() {
        OpenAIService.saveProviderID("deepseek")
        OpenAIService.saveModelSelection(.custom, providerID: "deepseek")
        OpenAIService.saveCustomModel("deepseek-v4-pro", providerID: "deepseek")
        let config = OpenAIService.activeConfig()
        XCTAssertEqual(config.baseURL, "https://api.deepseek.com")
        XCTAssertEqual(config.model, "deepseek-v4-pro")
    }

    func testProviderSelectionsAreIndependent() {
        OpenAIService.saveModelSelection(.preset("gpt-5-mini"), providerID: "openai")
        OpenAIService.saveModelSelection(.custom, providerID: "deepseek")
        OpenAIService.saveCustomModel("deepseek-v4-pro", providerID: "deepseek")

        XCTAssertEqual(OpenAIService.modelSelection(providerID: "openai"), .preset("gpt-5-mini"))
        XCTAssertEqual(OpenAIService.modelSelection(providerID: "deepseek"), .custom)
        XCTAssertEqual(OpenAIService.customModel(providerID: "deepseek"), "deepseek-v4-pro")
        XCTAssertEqual(OpenAIService.customModel(providerID: "openai"), "")
    }

    func testUnknownPresetFallsBackToProviderDefault() {
        OpenAIService.saveModelSelection(.preset("retired-model"), providerID: "openai")
        OpenAIService.saveProviderID("openai")

        XCTAssertEqual(OpenAIService.modelSelection(providerID: "openai"), .preset("gpt-4.1-mini"))
        XCTAssertEqual(OpenAIService.activeConfig().model, "gpt-4.1-mini")
    }

    func testLegacyConfigMigratesOnlyOnceToCurrentProvider() {
        UserDefaults.standard.set("deepseek", forKey: providerKey)
        UserDefaults.standard.set("legacy-model", forKey: modelKey)
        UserDefaults.standard.set("https://legacy.example/v1", forKey: baseURLKey)

        XCTAssertEqual(OpenAIService.modelSelection(providerID: "deepseek"), .custom)
        XCTAssertEqual(OpenAIService.customModel(providerID: "deepseek"), "legacy-model")
        XCTAssertEqual(OpenAIService.customBaseURL(providerID: "deepseek"), "https://legacy.example/v1")

        UserDefaults.standard.set("changed-legacy", forKey: modelKey)
        XCTAssertEqual(OpenAIService.customModel(providerID: "deepseek"), "legacy-model")
    }

    func testLegacyConfigMigratesToPersistedProviderEvenWhenAnotherProviderReadsFirst() {
        UserDefaults.standard.set("deepseek", forKey: providerKey)
        UserDefaults.standard.set("legacy-model", forKey: modelKey)
        UserDefaults.standard.set("https://legacy.example/v1", forKey: baseURLKey)

        XCTAssertEqual(OpenAIService.modelSelection(providerID: "openai"), .preset("gpt-4.1-mini"))
        XCTAssertEqual(OpenAIService.modelSelection(providerID: "deepseek"), .custom)
        XCTAssertEqual(OpenAIService.customModel(providerID: "deepseek"), "legacy-model")
        XCTAssertEqual(OpenAIService.customBaseURL(providerID: "deepseek"), "https://legacy.example/v1")
        XCTAssertEqual(OpenAIService.customModel(providerID: "openai"), "")
    }

    func testLegacyConfigWithUnknownProviderAndCustomURLMigratesToCustomProvider() {
        UserDefaults.standard.set("retired-provider", forKey: providerKey)
        UserDefaults.standard.set("retired-model", forKey: modelKey)
        UserDefaults.standard.set("https://retired.example/v1", forKey: baseURLKey)

        _ = OpenAIService.modelSelection(providerID: OpenAIService.providerID())

        XCTAssertEqual(OpenAIService.providerID(), "openai")
        XCTAssertEqual(OpenAIService.customModel(providerID: "custom"), "retired-model")
        XCTAssertEqual(OpenAIService.customBaseURL(providerID: "custom"), "https://retired.example/v1")
        XCTAssertEqual(OpenAIService.customModel(providerID: "openai"), "")
    }

    func testManagedQuotaUsesCurrentDeepSeekModel() {
        XCTAssertEqual(OpenAIService.managedModelID, "deepseek-v4-flash")
    }

    func testRoutedCallAtomicallyReportsDirectRouteWithoutNetwork() async throws {
        let quotaKey = QuotaClient.baseURLKey
        let apiKey = OpenAIService.keyStorageKey
        let oldQuota = UserDefaults.standard.object(forKey: quotaKey)
        let oldAPIKey = UserDefaults.standard.object(forKey: apiKey)
        defer {
            restore(oldQuota, forKey: quotaKey)
            restore(oldAPIKey, forKey: apiKey)
        }
        UserDefaults.standard.removeObject(forKey: quotaKey)
        UserDefaults.standard.set("", forKey: apiKey)

        let routed = try await OpenAIService.callOpenAIWithSource(
            promptText: "prompt",
            instructionText: "instruction"
        )

        XCTAssertNil(routed.text)
        XCTAssertEqual(routed.source, .custom)
    }

    func testRoutedCallAtomicallyReportsManagedRouteFromSuccessfulRequest() async throws {
        let quotaKey = QuotaClient.baseURLKey
        let apiKey = OpenAIService.keyStorageKey
        let oldQuota = UserDefaults.standard.object(forKey: quotaKey)
        let oldAPIKey = UserDefaults.standard.object(forKey: apiKey)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [OpenAIRouteMockURLProtocol.self]
        QuotaClient.session = URLSession(configuration: configuration)
        defer {
            restore(oldQuota, forKey: quotaKey)
            restore(oldAPIKey, forKey: apiKey)
            OpenAIRouteMockURLProtocol.handler = nil
            QuotaClient.session = .shared
        }
        UserDefaults.standard.set("https://quota.test", forKey: quotaKey)
        UserDefaults.standard.set("", forKey: apiKey)
        OpenAIRouteMockURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/proxy/chat/completions")
            let data = try JSONSerialization.data(withJSONObject: [
                "choices": [["message": ["content": "managed response"]]]
            ])
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, data)
        }

        let routed = try await OpenAIService.callOpenAIWithSource(
            promptText: "prompt",
            instructionText: "instruction"
        )

        XCTAssertEqual(routed.text, "managed response")
        XCTAssertEqual(routed.source, .managed)
    }

    func testUnknownProviderFallsBackToOpenAI() {
        OpenAIService.saveProviderID("nonexistent")
        XCTAssertEqual(OpenAIService.providerID(), "openai")
    }

    func testExtractChatCompletionsText() {
        let json: [String: Any] = [
            "choices": [["message": ["content": "hello deepseek"]]]
        ]
        XCTAssertEqual(OpenAIService.extractOutputText(from: json), "hello deepseek")
    }

    func testExtractChatCompletionsMultiPart() {
        let json: [String: Any] = [
            "choices": [["message": ["content": [["text": "a"], ["text": "b"]]]]]
        ]
        XCTAssertEqual(OpenAIService.extractOutputText(from: json), "a\nb")
    }

    func testExtractLegacyResponsesText() {
        let json: [String: Any] = [
            "output_text": "legacy response"
        ]
        XCTAssertEqual(OpenAIService.extractOutputText(from: json), "legacy response")
    }

    func testExtractResponsesOutputArray() {
        let json: [String: Any] = [
            "output": [["content": [["type": "output_text", "text": "chunk1"]]]]
        ]
        XCTAssertEqual(OpenAIService.extractOutputText(from: json), "chunk1")
    }

    func testExtractEmptyReturnsNil() {
        XCTAssertNil(OpenAIService.extractOutputText(from: [:]))
        XCTAssertNil(OpenAIService.extractOutputText(from: ["choices": [["message": ["content": "  "]]]]))
    }

    func testExtractTasksStripsMarkdownCheckbox() {
        let text = """
        - [ ] 记录今日三餐热量，控制在 1500 千卡以内
        - [x] 购买体重秤，明早空腹称重并记录基线体重
        """
        XCTAssertEqual(AIService.extractTasks(from: text), [
            "记录今日三餐热量，控制在 1500 千卡以内",
            "购买体重秤，明早空腹称重并记录基线体重"
        ])
    }

    func testExtractTasksStripsCheckedAndNumberedCheckboxVariants() {
        let text = """
        - [X] 准备会议材料
        1. [ ] 给客户发报价单
        2）[ ] 更新项目进度表
        """
        XCTAssertEqual(AIService.extractTasks(from: text), [
            "准备会议材料",
            "给客户发报价单",
            "更新项目进度表"
        ])
    }

    func testExtractTasksStripsBareAndCompactCheckbox() {
        let text = """
        [ ] 无序号复选框任务
        -[ ]紧凑写法也要能清洗
        * [x] 星号列表项
        """
        XCTAssertEqual(AIService.extractTasks(from: text), [
            "无序号复选框任务",
            "紧凑写法也要能清洗",
            "星号列表项"
        ])
    }

    private func restore(_ value: Any?, forKey key: String) {
        if let value {
            UserDefaults.standard.set(value, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }
}
