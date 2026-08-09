import XCTest
@testable import TodoNative

final class NotificationServiceTests: XCTestCase {
    private var calendar: Calendar { Calendar.current }

    private func date(_ daysFromNow: Int, hour: Int = 0, minute: Int = 0) -> Date {
        let base = calendar.startOfDay(for: Date())
        let day = calendar.date(byAdding: .day, value: daysFromNow, to: base)!
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)!
    }

    func testFutureDateTriggersAtUserChosenTime() {
        let now = date(0, hour: 10)
        let due = date(3, hour: 18, minute: 30)

        XCTAssertEqual(
            NotificationService.triggerDate(for: due, now: now).timeIntervalSinceReferenceDate,
            due.timeIntervalSinceReferenceDate,
            accuracy: 1.0
        )
    }

    func testTodayChosenTimeStillInFutureTriggersAtThatTime() {
        let now = date(0, hour: 10)
        let due = date(0, hour: 15)

        XCTAssertEqual(NotificationService.triggerDate(for: due, now: now), due)
    }

    func testTodayChosenTimeAlreadyPassedTriggersWithMinimumInterval() {
        let now = date(0, hour: 10)
        let due = date(0, hour: 9)

        let fired = NotificationService.triggerDate(for: due, now: now)
        XCTAssertGreaterThanOrEqual(fired.timeIntervalSince(now), 60)
    }

    func testPastDateTriggersWithMinimumInterval() {
        let now = date(0, hour: 10)
        let due = date(-2, hour: 15)

        let fired = NotificationService.triggerDate(for: due, now: now)
        XCTAssertGreaterThanOrEqual(fired.timeIntervalSince(now), 60)
    }

    func testFarPastDateUsesAtLeastOneMinuteInterval() {
        let now = date(0, hour: 10)
        let due = date(-10)

        let fired = NotificationService.triggerDate(for: due, now: now)
        XCTAssertGreaterThanOrEqual(fired.timeIntervalSince(now), 60)
    }
}
