import XCTest
@testable import TodoNative

@MainActor
final class CompanionEventsTests: XCTestCase {
    override func setUp() {
        super.setUp()
        CompanionEvents.clearNudged()
    }

    override func tearDown() {
        CompanionEvents.clearNudged()
        super.tearDown()
    }

    func testCelebrateWhenDayCompletedAtLeastOne() {
        let now = Date()
        let item = TodoItem(title: "完成任务A", estimatedMinutes: 6, priority: 3)
        item.status = .done
        item.completedAt = now.addingTimeInterval(-3600)
        let moments = CompanionEvents.moments(tasks: [item], completedToday: 2)
        XCTAssertTrue(moments.contains { $0.type == "celebrate" && $0.text.contains("完成任务A") })
    }

    func testNudgeWhenTaskOlderThanThreeDays() {
        let now = Date()
        let item = TodoItem(title: "任务B")
        item.createdAt = now.addingTimeInterval(-4 * 86400)
        let moments = CompanionEvents.moments(tasks: [item], completedToday: 0, now: now)
        XCTAssertTrue(moments.contains { $0.type == "nudge" && $0.text.contains("任务B") })
    }

    func testNudgeNotRepeatedAfterMarked() {
        let now = Date()
        let item = TodoItem(title: "任务C")
        item.createdAt = now.addingTimeInterval(-5 * 86400)
        let first = CompanionEvents.moments(tasks: [item], completedToday: 0, now: now)
        XCTAssertTrue(first.contains { $0.type == "nudge" })
        CompanionEvents.markNudged(item)
        let second = CompanionEvents.moments(tasks: [item], completedToday: 0, now: now)
        XCTAssertFalse(second.contains { $0.type == "nudge" })
    }

    func testFreshTaskDoesNotNudge() {
        let now = Date()
        let item = TodoItem(title: "任务D")
        item.createdAt = now.addingTimeInterval(-2 * 86400)
        let moments = CompanionEvents.moments(tasks: [item], completedToday: 0, now: now)
        XCTAssertFalse(moments.contains { $0.type == "nudge" })
    }

    func testThirdCompletionCelebrates() {
        let now = Date()
        let item = TodoItem(title: "任务E")
        item.status = .done
        item.completedAt = now.addingTimeInterval(-600)
        let moments = CompanionEvents.moments(tasks: [item], completedToday: 3, now: now)
        XCTAssertTrue(moments.contains { $0.type == "celebrate" })
    }
}