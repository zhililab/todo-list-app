import XCTest
@testable import TodoNative

final class AISelectedGoalContextTests: XCTestCase {
    private let fixedID = UUID(uuidString: "00000000-0000-0000-0000-000000000041")!
    private let fixedDueDate = Date(timeIntervalSince1970: 1_786_291_200)

    func testActiveTaskCreatesStructuredSelectedGoalContext() throws {
        let item = makeItem(title: "  发布 1.0\n")

        let selected = try XCTUnwrap(AISelectedGoalContext(item: item))

        XCTAssertEqual(selected.id, item.id)
        XCTAssertEqual(selected.title, "发布 1.0")
        XCTAssertEqual(selected.context, "面向首批用户")
        XCTAssertEqual(selected.acceptanceCriteria, "TestFlight 通过")
        XCTAssertEqual(selected.nextPrompt, "列出发布检查项")
        XCTAssertEqual(selected.taskType, TaskType.product.rawValue)
        XCTAssertEqual(selected.priority, 5)
        XCTAssertEqual(selected.estimatedMinutes, 45)
        XCTAssertEqual(selected.dueDate, item.dueDate)
    }

    func testCompletedArchivedAndBlankTasksAreIneligible() {
        XCTAssertNil(AISelectedGoalContext(item: makeItem(status: .done)))
        XCTAssertNil(AISelectedGoalContext(item: makeItem(isArchived: true)))
        XCTAssertNil(AISelectedGoalContext(item: makeItem(title: " \n\t ")))
    }

    func testArchivedStatusIsIneligibleEvenWhenArchiveFlagIsFalse() {
        let item = makeItem(status: .archived, isArchived: false)

        XCTAssertNil(AISelectedGoalContext(item: item))
    }

    func testFingerprintIsDeterministicAndChangesWithEveryPromptField() throws {
        let selected = try XCTUnwrap(AISelectedGoalContext(item: makeItem()))
        let duplicate = try XCTUnwrap(AISelectedGoalContext(item: clone(selected)))

        XCTAssertEqual(selected.fingerprint, duplicate.fingerprint)

        let mutations: [(String, (TodoItem) -> Void)] = [
            ("title", { $0.title = "发布 1.1" }),
            ("context", { $0.context = "面向所有用户" }),
            ("acceptanceCriteria", { $0.acceptanceCriteria = "审核通过" }),
            ("nextPrompt", { $0.nextPrompt = "列出回滚步骤" }),
            ("taskType", { $0.taskType = .code }),
            ("priority", { $0.priority = 4 }),
            ("estimatedMinutes", { $0.estimatedMinutes = 60 }),
            ("dueDate", { $0.dueDate = Date(timeIntervalSince1970: 1_786_377_600) })
        ]

        for (field, mutate) in mutations {
            let item = clone(selected)
            mutate(item)
            let mutated = try XCTUnwrap(AISelectedGoalContext(item: item))
            XCTAssertNotEqual(selected.fingerprint, mutated.fingerprint, field)
        }
    }

    private func makeItem(
        title: String = "发布 1.0",
        status: TodoStatus = .doing,
        isArchived: Bool = false
    ) -> TodoItem {
        let item = TodoItem(
            title: title,
            context: "面向首批用户",
            acceptanceCriteria: "TestFlight 通过",
            nextPrompt: "列出发布检查项",
            taskType: .product,
            estimatedMinutes: 45,
            priority: 5,
            status: status,
            dueDate: fixedDueDate,
            isArchived: isArchived
        )
        item.id = fixedID
        return item
    }

    private func clone(_ selected: AISelectedGoalContext) -> TodoItem {
        let item = TodoItem(
            title: selected.title,
            context: selected.context,
            acceptanceCriteria: selected.acceptanceCriteria,
            nextPrompt: selected.nextPrompt,
            taskType: TaskType(rawValue: selected.taskType)!,
            estimatedMinutes: selected.estimatedMinutes,
            priority: selected.priority,
            status: .doing,
            dueDate: selected.dueDate
        )
        item.id = selected.id
        return item
    }
}
