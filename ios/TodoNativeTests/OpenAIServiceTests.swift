import XCTest
@testable import TodoNative

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

    func testManagedQuotaUsesCurrentDeepSeekModel() {
        XCTAssertEqual(OpenAIService.managedModelID, "deepseek-v4-flash")
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
}
