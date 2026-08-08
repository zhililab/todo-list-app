import XCTest
@testable import TodoNative

final class AIPlanServiceTests: XCTestCase {
    private var service: AIPlanService!

    override func setUp() {
        super.setUp()
        service = AIPlanService()
    }

    override func tearDown() {
        service = nil
        super.tearDown()
    }

    private func makeItem(
        title: String,
        priority: Int = 3,
        status: TodoStatus = .todo,
        dueDate: Date? = nil,
        estimated: Int = 15,
        isArchived: Bool = false
    ) -> TodoItem {
        let item = TodoItem(
            title: title,
            taskType: .code,
            estimatedMinutes: estimated,
            priority: priority,
            status: status,
            dueDate: dueDate,
            isArchived: isArchived
        )
        return item
    }

    func testEmptyItemsGivesEmptyPlan() {
        XCTAssertTrue(service.generateTodayPlan(from: []).isEmpty)
    }

    func testPlanExcludesDoneItems() {
        let done = makeItem(title: "已完成", status: .done)
        let todo = makeItem(title: "待办")
        let plan = service.generateTodayPlan(from: [done, todo])
        XCTAssertEqual(plan.map(\.title), ["待办"])
    }

    func testPlanExcludesArchivedItems() {
        let archived = makeItem(title: "已归档", isArchived: true)
        let plan = service.generateTodayPlan(from: [archived])
        XCTAssertTrue(plan.isEmpty)
    }

    func testPlanSortsByPriorityDescending() {
        let low = makeItem(title: "低优先级", priority: 1)
        let high = makeItem(title: "高优先级", priority: 5)
        let plan = service.generateTodayPlan(from: [low, high])
        XCTAssertEqual(plan.map(\.title), ["高优先级", "低优先级"])
    }

    func testPlanUsesDueDateAsTieBreaker() {
        let later = makeItem(title: "晚", priority: 3, dueDate: Date().addingTimeInterval(3600))
        let sooner = makeItem(title: "早", priority: 3, dueDate: Date().addingTimeInterval(60))
        let plan = service.generateTodayPlan(from: [later, sooner])
        XCTAssertEqual(plan.map(\.title), ["早", "晚"])
    }

    func testPlanLimitsToFive() {
        let items = (1...10).map { makeItem(title: "任务\($0)", priority: $0 % 5 + 1) }
        let plan = service.generateTodayPlan(from: items)
        XCTAssertLessThanOrEqual(plan.count, 5)
    }

    func testPlanIncludesDoingItems() {
        let doing = makeItem(title: "进行中", status: .doing)
        let plan = service.generateTodayPlan(from: [doing])
        XCTAssertEqual(plan.map(\.title), ["进行中"])
    }
}