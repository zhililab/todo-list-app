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

private final class OpenAIFakeKeychainBackend: KeychainPersisting {
    enum Failure: Error { case write }

    var values: [String: Data] = [:]
    var shouldFailWrites = false

    func data(service: String, account: String) throws -> Data? {
        values["\(service)|\(account)"]
    }

    func setData(_ data: Data, service: String, account: String) throws {
        if shouldFailWrites { throw Failure.write }
        values["\(service)|\(account)"] = data
    }

    func deleteData(service: String, account: String) throws {
        values.removeValue(forKey: "\(service)|\(account)")
    }
}

@MainActor
final class OpenAIServiceTests: XCTestCase {
    private let providerKey = "ai_provider"
    private let baseURLKey = "ai_base_url"
    private let modelKey = "ai_model"
    private let migrationKey = "ai_provider_scoped_config_migrated"
    nonisolated(unsafe) private var keychainBackend: OpenAIFakeKeychainBackend!
    nonisolated(unsafe) private var consentDefaults: UserDefaults!
    nonisolated(unsafe) private var consentSuiteName = ""
    nonisolated(unsafe) private var originalCredentialStore: KeychainStore!
    nonisolated(unsafe) private var originalConsentManager: AIConsentManager!
    nonisolated(unsafe) private var originalSession: URLSession!

    override func setUp() {
        super.setUp()
        MainActor.assumeIsolated {
            originalCredentialStore = OpenAIService.credentialStore
            originalConsentManager = OpenAIService.consentManager
            originalSession = OpenAIService.session
            keychainBackend = OpenAIFakeKeychainBackend()
            OpenAIService.credentialStore = KeychainStore(
                service: "OpenAIServiceTests.credentials",
                account: "openai-api-key",
                backend: keychainBackend
            )
            consentSuiteName = "OpenAIServiceTests.consent.\(UUID().uuidString)"
            consentDefaults = UserDefaults(suiteName: consentSuiteName)!
            OpenAIService.consentManager = AIConsentManager(
                consentVersion: "1",
                storage: consentDefaults
            )
        }
        UserDefaults.standard.removeObject(forKey: OpenAIService.keyStorageKey)
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
        UserDefaults.standard.removeObject(forKey: OpenAIService.keyStorageKey)
        MainActor.assumeIsolated {
            keychainBackend = nil
            consentDefaults.removePersistentDomain(forName: consentSuiteName)
            consentDefaults = nil
            consentSuiteName = ""
            OpenAIService.credentialStore = originalCredentialStore
            OpenAIService.consentManager = originalConsentManager
            OpenAIService.session = originalSession
            originalCredentialStore = nil
            originalConsentManager = nil
            originalSession = nil
        }
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

    func testAPIKeyMigratesFromLegacyUserDefaultsIntoInjectedKeychain() throws {
        UserDefaults.standard.set("  sk-legacy-key  ", forKey: OpenAIService.keyStorageKey)

        XCTAssertEqual(OpenAIService.apiKey(), "sk-legacy-key")
        XCTAssertNil(UserDefaults.standard.object(forKey: OpenAIService.keyStorageKey))
        XCTAssertEqual(try OpenAIService.credentialStore.read(), "sk-legacy-key")
    }

    func testSavingAPIKeyTrimsAndWritesInjectedKeychain() {
        OpenAIService.saveAPIKey("  sk-new-key\n")

        XCTAssertEqual(OpenAIService.apiKey(), "sk-new-key")
        XCTAssertNil(UserDefaults.standard.object(forKey: OpenAIService.keyStorageKey))
    }

    func testFailedAPIKeyWriteReportsFailureAndKeepsPersistedKey() {
        XCTAssertTrue(OpenAIService.saveAPIKey("sk-existing"))
        keychainBackend.shouldFailWrites = true

        XCTAssertFalse(OpenAIService.saveAPIKey("sk-unsaved"))
        XCTAssertEqual(OpenAIService.apiKey(), "sk-existing")
    }

    func testAIViewModelRestoresPersistedKeyWhenKeychainWriteFails() {
        XCTAssertTrue(OpenAIService.saveAPIKey("sk-existing"))
        let viewModel = AIViewModel()
        keychainBackend.shouldFailWrites = true

        viewModel.apiKey = "sk-unsaved"

        XCTAssertEqual(viewModel.apiKey, "sk-existing")
        XCTAssertEqual(viewModel.statusMessage, Localization.t("ai.keySaveFailed"))
    }

    func testDeletingLocalAIConfigurationRemovesKeySettingsAndConsent() throws {
        OpenAIService.saveAPIKey("sk-delete-me")
        OpenAIService.saveProviderID("custom")
        OpenAIService.saveCustomBaseURL("https://delete.test/v1", providerID: "custom")
        OpenAIService.saveCustomModel("delete-model", providerID: "custom")
        let route = try XCTUnwrap(OpenAIService.currentConsentRoute())
        OpenAIService.consentManager.accept(route)

        try OpenAIService.deleteLocalAIConfiguration()

        XCTAssertEqual(OpenAIService.apiKey(), "")
        XCTAssertEqual(OpenAIService.providerID(), "openai")
        XCTAssertEqual(OpenAIService.customBaseURL(providerID: "custom"), "")
        XCTAssertEqual(OpenAIService.customModel(providerID: "custom"), "")
        XCTAssertFalse(OpenAIService.consentManager.hasStoredConsent)
    }

    func testDirectTransportIsNotInvokedBeforeCurrentConsent() async throws {
        OpenAIService.saveAPIKey("sk-direct")
        OpenAIService.saveProviderID("custom")
        OpenAIService.saveCustomBaseURL("https://direct.test/v1", providerID: "custom")
        OpenAIService.saveCustomModel("test-model", providerID: "custom")
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [OpenAIRouteMockURLProtocol.self]
        OpenAIService.session = URLSession(configuration: configuration)
        var transportCallCount = 0
        OpenAIRouteMockURLProtocol.handler = { request in
            transportCallCount += 1
            return try Self.successResponse(for: request, text: "remote response")
        }
        defer { OpenAIRouteMockURLProtocol.handler = nil }

        let route = try XCTUnwrap(OpenAIService.currentConsentRoute())
        do {
            _ = try await OpenAIService.callOpenAIWithSource(
                promptText: "private task content",
                instructionText: "instruction"
            )
            XCTFail("Expected consent requirement")
        } catch RemoteAIConsentError.needsConsent(let blockedRoute) {
            XCTAssertEqual(blockedRoute, route)
        }
        XCTAssertEqual(transportCallCount, 0)

        OpenAIService.consentManager.accept(route)
        let response = try await OpenAIService.callOpenAIWithSource(
            promptText: "private task content",
            instructionText: "instruction"
        )
        XCTAssertEqual(response.text, "remote response")
        XCTAssertEqual(transportCallCount, 1)
    }

    func testBYOKProviderChangeRequiresConsentBeforeNewTransport() async throws {
        OpenAIService.saveAPIKey("sk-direct")
        OpenAIService.saveProviderID("openai")
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [OpenAIRouteMockURLProtocol.self]
        OpenAIService.session = URLSession(configuration: configuration)
        var transportCallCount = 0
        OpenAIRouteMockURLProtocol.handler = { request in
            transportCallCount += 1
            return try Self.successResponse(for: request, text: "remote response")
        }
        defer { OpenAIRouteMockURLProtocol.handler = nil }

        let openAIRoute = try XCTUnwrap(OpenAIService.currentConsentRoute())
        OpenAIService.consentManager.accept(openAIRoute)
        _ = try await OpenAIService.callOpenAIWithSource(
            promptText: "first request",
            instructionText: "instruction"
        )
        XCTAssertEqual(transportCallCount, 1)

        OpenAIService.saveProviderID("deepseek")
        let deepSeekRoute = try XCTUnwrap(OpenAIService.currentConsentRoute())
        XCTAssertNotEqual(deepSeekRoute.identifier, openAIRoute.identifier)
        do {
            _ = try await OpenAIService.callOpenAIWithSource(
                promptText: "second private request",
                instructionText: "instruction"
            )
            XCTFail("Expected renewed consent")
        } catch RemoteAIConsentError.needsConsent(let blockedRoute) {
            XCTAssertEqual(blockedRoute, deepSeekRoute)
        }
        XCTAssertEqual(transportCallCount, 1)
    }

    func testBuiltInProviderWithOverriddenEndpointUsesActualRecipientAndNewRoute() throws {
        OpenAIService.saveAPIKey("sk-direct")
        OpenAIService.saveProviderID("openai")
        let standardRoute = try XCTUnwrap(OpenAIService.currentConsentRoute())

        OpenAIService.saveCustomBaseURL(
            "https://compatible.example/v1",
            providerID: "openai"
        )
        let overriddenRoute = try XCTUnwrap(OpenAIService.currentConsentRoute())

        XCTAssertNotEqual(overriddenRoute.identifier, standardRoute.identifier)
        XCTAssertEqual(overriddenRoute.recipientName, "compatible.example")
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
        let oldQuota = UserDefaults.standard.object(forKey: quotaKey)
        defer {
            restore(oldQuota, forKey: quotaKey)
        }
        UserDefaults.standard.set("", forKey: quotaKey)
        OpenAIService.saveAPIKey("")

        let routed = try await OpenAIService.callOpenAIWithSource(
            promptText: "prompt",
            instructionText: "instruction"
        )

        XCTAssertNil(routed.text)
        XCTAssertEqual(routed.source, .custom)
    }

    func testRoutedCallAtomicallyReportsManagedRouteFromSuccessfulRequest() async throws {
        let quotaKey = QuotaClient.baseURLKey
        let oldQuota = UserDefaults.standard.object(forKey: quotaKey)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [OpenAIRouteMockURLProtocol.self]
        QuotaClient.session = URLSession(configuration: configuration)
        defer {
            restore(oldQuota, forKey: quotaKey)
            OpenAIRouteMockURLProtocol.handler = nil
            QuotaClient.session = .shared
        }
        UserDefaults.standard.set("https://quota.test", forKey: quotaKey)
        OpenAIService.saveAPIKey("")
        if let route = OpenAIService.currentConsentRoute() {
            OpenAIService.consentManager.accept(route)
        }
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

    private static func successResponse(
        for request: URLRequest,
        text: String
    ) throws -> (HTTPURLResponse, Data) {
        let data = try JSONSerialization.data(withJSONObject: [
            "choices": [["message": ["content": text]]]
        ])
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        return (response, data)
    }
}
