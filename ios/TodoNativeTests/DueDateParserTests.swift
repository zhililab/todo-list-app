import XCTest
@testable import TodoNative

final class DueDateParserTests: XCTestCase {
    // 固定"现在"为 2026-08-09 10:00（周六）
    private let now = Calendar.current.date(
        from: DateComponents(year: 2026, month: 8, day: 9, hour: 10, minute: 0)
    )!

    private func due(_ text: String) -> Date? {
        DueDateParser.parse(from: text, now: now)
    }

    func testTodayWithClock() {
        guard let date = due("今天 15:00 交周报") else { return XCTFail("nil") }
        let comps = Calendar.current.dateComponents([.day, .hour, .minute], from: date)
        XCTAssertEqual(comps.day, 9)
        XCTAssertEqual(comps.hour, 15)
        XCTAssertEqual(comps.minute, 0)
    }

    func testTodayNoClockIsEndOfDay() {
        guard let date = due("今天完成调研") else { return XCTFail("nil") }
        let comps = Calendar.current.dateComponents([.day, .hour, .minute], from: date)
        XCTAssertEqual(comps.day, 9)
        XCTAssertEqual(comps.hour, 23)
        XCTAssertEqual(comps.minute, 59)
    }

    func testTomorrowIsTomorrowEndOfDay() {
        guard let date = due("明天提交周报") else { return XCTFail("nil") }
        let comps = Calendar.current.dateComponents([.day, .month], from: date)
        XCTAssertEqual(comps.month, 8)
        XCTAssertEqual(comps.day, 10)
    }

    func testDayAfterTomorrow() {
        guard let endOfDay = due("后天整理房间"),
              let afternoon = due("后天下午2点整理房间") else { return XCTFail("nil") }
        let endOfDayComps = Calendar.current.dateComponents([.day, .hour, .minute], from: endOfDay)
        XCTAssertEqual(endOfDayComps.day, 11)
        XCTAssertEqual(endOfDayComps.hour, 23)
        XCTAssertEqual(endOfDayComps.minute, 59)

        let afternoonComps = Calendar.current.dateComponents([.day, .hour], from: afternoon)
        XCTAssertEqual(afternoonComps.day, 11)
        XCTAssertEqual(afternoonComps.hour, 14)
    }

    func testHoursFromNow() {
        guard let date = due("3小时后提醒我") else { return XCTFail("nil") }
        XCTAssertEqual(date.timeIntervalSince(now), 3 * 3600, accuracy: 1)
    }

    func testMinutesFromNow() {
        guard let date = due("30分钟后开会") else { return XCTFail("nil") }
        XCTAssertEqual(date.timeIntervalSince(now), 30 * 60, accuracy: 1)
    }

    func testChineseRelativeDayWithTimeWord() {
        // "明天早上" 落在明天的规则命中
        XCTAssertNotNil(due("明天早上9点开会"))
    }

    func testBareClock() {
        guard let date = due("15:30 交设计方案") else { return XCTFail("nil") }
        let comps = Calendar.current.dateComponents([.hour, .minute], from: date)
        XCTAssertEqual(comps.hour, 15)
        XCTAssertEqual(comps.minute, 30)
    }

    func testTodayHourWord() {
        guard let date = due("下午2点讨论") else { return XCTFail("nil") }
        let comps = Calendar.current.dateComponents([.hour], from: date)
        XCTAssertEqual(comps.hour, 14)
    }

    func testNoTimeExpressionReturnsNil() {
        XCTAssertNil(due("整理会议笔记"))
        XCTAssertNil(due("写周报"))
    }

    func testEmptyStringReturnsNil() {
        XCTAssertNil(due(""))
        XCTAssertNil(due("   "))
    }
}
