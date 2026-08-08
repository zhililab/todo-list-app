import XCTest
@testable import TodoNative

final class TodoItemTests: XCTestCase {
    func testDefaultInit() {
        let item = TodoItem(title: "写周报")
        XCTAssertEqual(item.title, "写周报")
        XCTAssertEqual(item.taskType, .personal)
        XCTAssertEqual(item.status, .todo)
        XCTAssertEqual(item.priority, 3)
        XCTAssertEqual(item.estimatedMinutes, 15)
        XCTAssertFalse(item.isArchived)
        XCTAssertNotNil(item.createdAt)
        XCTAssertNotNil(item.updatedAt)
    }

    func testTaskTypeMapping() {
        XCTAssertEqual(TaskType.allCases.count, 5)
        XCTAssertTrue(TaskType.allCases.contains(.personal))
        XCTAssertTrue(TaskType.allCases.contains(.code))
        XCTAssertTrue(TaskType.allCases.contains(.product))
        XCTAssertTrue(TaskType.allCases.contains(.learning))
        XCTAssertTrue(TaskType.allCases.contains(.life))
        XCTAssertEqual(TaskType.personal.rawValue, "Personal")
    }

    func testTodoStatusMapping() {
        XCTAssertEqual(TodoStatus.todo.rawValue, "todo")
        XCTAssertEqual(TodoStatus.doing.rawValue, "doing")
        XCTAssertEqual(TodoStatus.done.rawValue, "done")
        XCTAssertEqual(TodoStatus.archived.rawValue, "archived")
    }

    func testTaskTypeLocalizedNames() {
        XCTAssertEqual(TaskType.personal.localizedName, "个人")
        XCTAssertEqual(TaskType.code.localizedName, "代码")
        XCTAssertEqual(TaskType.product.localizedName, "产品")
        XCTAssertEqual(TaskType.learning.localizedName, "学习")
        XCTAssertEqual(TaskType.life.localizedName, "生活")
    }

    func testStoredTypeGetters() {
        let item = TodoItem(title: "x", taskType: .code)
        XCTAssertEqual(item.taskTypeRaw, "Code")
        XCTAssertEqual(item.taskType, .code)

        item.taskType = .life
        XCTAssertEqual(item.taskTypeRaw, "Life")
        XCTAssertEqual(item.taskType, .life)
    }
}