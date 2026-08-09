import XCTest
@testable import TodoNative

@MainActor
final class CompanionCoreTests: XCTestCase {
    func testBuildPromptContainsTaskAndBuddy() {
        let item = TodoItem(title: "记录三餐热量", estimatedMinutes: 25, priority: 3)
        let (system, user) = CompanionCore.buildContext(
            memorySummary: "昨天完成3件事", events: [], tasks: [item],
            history: [], language: "zh", health: 80, totalCount: 10, doneCount: 2, buddyName: "小暖")
        XCTAssertTrue(system.contains("小暖"))
        XCTAssertTrue(user.contains("记录三餐热量"))
        XCTAssertTrue(user.contains("健康分"))
    }

    func testHistoryCappedAtEight() {
        let history = (0..<12).map { i in (role: i % 2 == 0 ? "user" : "assistant", content: "msg\(i)") }
        let (_, user) = CompanionCore.buildContext(memorySummary: "", events: [], tasks: [],
            history: history, language: "zh", health: 50, totalCount: 0, doneCount: 0)
        XCTAssertLessThanOrEqual(user.components(separatedBy: "msg").count - 1, 8)
    }

    func testStripMemoryAppendsEvents() {
        let merged = CompanionCore.stripMemory(old: "旧", events: ["完成X", "又完成"])
        XCTAssertTrue(merged.contains("完成X"))
    }
}