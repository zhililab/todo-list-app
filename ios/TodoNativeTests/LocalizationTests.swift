import XCTest
@testable import TodoNative

@MainActor
final class LocalizationTests: XCTestCase {
    private let languageKey = "app_language"

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: languageKey)
        LanguageEnvironment.setDefaultLanguage()
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: languageKey)
        LanguageEnvironment.setDefaultLanguage()
        super.tearDown()
    }

    func testDefaultsToChinese() {
        XCTAssertEqual(Localization.currentLanguage, "zh")
        XCTAssertEqual(Localization.t("tab.today"), "今日计划")
        XCTAssertEqual(Localization.t("taskType.personal"), "个人")
    }

    func testSwitchToEnglish() {
        Localization.setLanguage("en")
        XCTAssertEqual(Localization.currentLanguage, "en")
        XCTAssertEqual(Localization.t("tab.today"), "Today Plan")
        XCTAssertEqual(Localization.t("taskType.personal"), "Personal")
    }

    func testMissingKeyFallsBackToKey() {
        XCTAssertEqual(Localization.t("no.such.key"), "no.such.key")
    }

    func testLanguageEnvironmentPublishes() {
        let env = LanguageEnvironment()
        XCTAssertEqual(env.language, "zh")
        env.setLanguage("en")
        XCTAssertEqual(env.language, "en")
        XCTAssertEqual(Localization.t("tab.settings"), "Settings")
    }
}