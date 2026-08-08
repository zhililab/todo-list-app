import XCTest
@testable import TodoNative

@MainActor
final class OpenAIServiceTests: XCTestCase {
    private let providerKey = "ai_provider"
    private let baseURLKey = "ai_base_url"
    private let modelKey = "ai_model"

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: providerKey)
        UserDefaults.standard.removeObject(forKey: baseURLKey)
        UserDefaults.standard.removeObject(forKey: modelKey)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: providerKey)
        UserDefaults.standard.removeObject(forKey: baseURLKey)
        UserDefaults.standard.removeObject(forKey: modelKey)
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
        XCTAssertEqual(AIProvider.provider(id: "deepseek").defaultModel, "deepseek-chat")
    }

    func testCustomOverridesProviderDefaults() {
        OpenAIService.saveProviderID("deepseek")
        OpenAIService.saveCustomModel("deepseek-reasoner")
        let config = OpenAIService.activeConfig()
        XCTAssertEqual(config.baseURL, "https://api.deepseek.com")
        XCTAssertEqual(config.model, "deepseek-reasoner")
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