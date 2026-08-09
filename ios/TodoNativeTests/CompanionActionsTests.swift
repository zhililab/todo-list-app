import XCTest
@testable import TodoNative

@MainActor
final class CompanionActionsTests: XCTestCase {
    func testParseExtractsActionsAndCleanText() {
        let reply = """
        我感觉你需要把这步落地。
        {"type":"confirm","actions":[{"action":"add_task","payload":{"title":"记录今日三餐"},"label":"加入待办"},{"action":"complete_task","payload":{"title":"买体重秤"},"label":"标记完成"}]}
        慢慢来，不着急。
        """
        let result = CompanionActions.parse(reply)
        XCTAssertEqual(result.actions.count, 2)
        XCTAssertEqual(result.actions[0].kind, "add_task")
        XCTAssertEqual(result.actions[0].payload["title"], "记录今日三餐")
        XCTAssertEqual(result.actions[1].kind, "complete_task")
        XCTAssertTrue(result.text.contains("这步落地"))
    }

    func testPlainTextWithoutActionsStaysPure() {
        let reply = "今天也要慢慢来，我陪着你。"
        let result = CompanionActions.parse(reply)
        XCTAssertEqual(result.actions.count, 0)
        XCTAssertEqual(result.text, reply)
    }

    func testCapsActionsAtTwo() {
        let json = #"{"actions":[{"action":"add_task","payload":{"title":"a"}},{"action":"add_task","payload":{"title":"b"}},{"action":"add_task","payload":{"title":"c"}}]}"#
        let result = CompanionActions.parse(json)
        XCTAssertEqual(result.actions.count, 2)
    }

    func testFiltersUnknownActionKinds() {
        let json = #"{"actions":[{"action":"delete_everything","label":"危险"},{"action":"add_task","payload":{"title":"安全任务"},"label":"加入待办"}]}"#
        let result = CompanionActions.parse(json)
        XCTAssertEqual(result.actions.count, 1)
        XCTAssertEqual(result.actions[0].kind, "add_task")
    }
}