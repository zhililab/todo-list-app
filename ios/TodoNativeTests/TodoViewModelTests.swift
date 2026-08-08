import XCTest
import SwiftData
@testable import TodoNative

@MainActor
final class TodoViewModelTests: XCTestCase {
    private var container: ModelContainer!

    override func setUp() {
        super.setUp()
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try! ModelContainer(for: TodoItem.self, configurations: config)
    }

    override func tearDown() {
        container = nil
        super.tearDown()
    }

    func testAddItemAppearsInItems() {
        let vm = TodoViewModel(modelContainer: container)
        vm.addItem(title: "  学习 SwiftUI  ", type: .learning, context: "ml", criteria: "看完", prompt: "写总结", minutes: 30, priority: 4)

        XCTAssertEqual(vm.unarchivedItems.count, 1)
        XCTAssertEqual(vm.unarchivedItems.first?.title, "学习 SwiftUI")
        XCTAssertEqual(vm.unarchivedItems.first?.taskType, .learning)
        XCTAssertTrue(vm.todoItems.contains { $0.title == "学习 SwiftUI" })
    }

    func testEmptyTitleNotAdded() {
        let vm = TodoViewModel(modelContainer: container)
        vm.addItem(title: "   ", type: .personal, context: "", criteria: "", prompt: "", minutes: 10, priority: 3)
        XCTAssertTrue(vm.unarchivedItems.isEmpty)
    }

    func testCaptureNaturalLanguageInfersPriorityAndMinutes() {
        let vm = TodoViewModel(modelContainer: container)
        vm.captureNaturalLanguage("修复紧急 bug，今天上线", type: .code)
        let item = vm.unarchivedItems.first!
        XCTAssertEqual(item.title, "修复紧急 bug，今天上线")
        XCTAssertEqual(item.priority, 5)
        XCTAssertEqual(item.taskType, .code)
        XCTAssertEqual(item.status, .todo)
    }

    func testCaptureNaturalLanguageParsesMinutes() {
        let vm = TodoViewModel(modelContainer: container)
        vm.captureNaturalLanguage("阅读文档 30 分钟", type: .learning)
        let item = vm.unarchivedItems.first!
        XCTAssertEqual(item.estimatedMinutes, 30)
    }

    func testCaptureNaturalLanguageEmptyIgnored() {
        let vm = TodoViewModel(modelContainer: container)
        vm.captureNaturalLanguage("   ", type: .personal)
        XCTAssertTrue(vm.unarchivedItems.isEmpty)
    }

    func testUpdateStatusTransitions() {
        let vm = TodoViewModel(modelContainer: container)
        vm.addItem(title: "买菜", type: .life, context: "", criteria: "", prompt: "", minutes: 10, priority: 2)
        let item = vm.unarchivedItems[0]

        vm.updateStatus(item, status: .doing)
        XCTAssertEqual(item.status, .doing)
        XCTAssertEqual(vm.doingItems.count, 1)

        vm.updateStatus(item, status: .done)
        XCTAssertEqual(item.status, .done)
        XCTAssertEqual(vm.completedItems.count, 1)
        XCTAssertNotNil(item.completedAt)
    }

    func testCompletionRate() {
        let vm = TodoViewModel(modelContainer: container)
        vm.addItem(title: "A", type: .personal, context: "", criteria: "", prompt: "", minutes: 5, priority: 1)
        vm.addItem(title: "B", type: .personal, context: "", criteria: "", prompt: "", minutes: 5, priority: 1)
        let a = vm.unarchivedItems[0]
        vm.updateStatus(a, status: .done)

        XCTAssertEqual(vm.completionRate, 50)
    }

    func testHealthScoreEmpty() {
        let vm = TodoViewModel(modelContainer: container)
        XCTAssertEqual(vm.healthScore, 0)
        XCTAssertEqual(vm.healthLabel(), "等待任务输入")
    }

    func testHealthScoreContextBoostsScore() {
        let vm = TodoViewModel(modelContainer: container)
        vm.addItem(title: "A", type: .code, context: "ctx", criteria: "", prompt: "", minutes: 5, priority: 2)
        vm.addItem(title: "B", type: .life, context: "", criteria: "标准", prompt: "", minutes: 5, priority: 1)
        let a = vm.unarchivedItems[0]
        vm.updateStatus(a, status: .done)

        XCTAssertGreaterThan(vm.healthScore, 0)
        XCTAssertLessThanOrEqual(vm.healthScore, 100)
    }

    func testHealthLabelTiers() {
        XCTAssertEqual(TodoViewModel.healthLabelStatic(95), "状态很好")
        XCTAssertEqual(TodoViewModel.healthLabelStatic(70), "稳步推进")
        XCTAssertEqual(TodoViewModel.healthLabelStatic(50), "补充上下文")
        XCTAssertEqual(TodoViewModel.healthLabelStatic(20), "需要拆解")
    }

    func testDeleteRemovesItem() {
        let vm = TodoViewModel(modelContainer: container)
        vm.addItem(title: "要删除", type: .personal, context: "", criteria: "", prompt: "", minutes: 5, priority: 1)
        let item = vm.unarchivedItems[0]
        vm.delete(item)
        XCTAssertTrue(vm.unarchivedItems.isEmpty)
    }

    func testStatusFilter() {
        let vm = TodoViewModel(modelContainer: container)
        vm.addItem(title: "A", type: .personal, context: "", criteria: "", prompt: "", minutes: 5, priority: 1)
        vm.addItem(title: "B", type: .personal, context: "", criteria: "", prompt: "", minutes: 5, priority: 1)
        let a = vm.unarchivedItems.first { $0.title == "A" }!
        vm.updateStatus(a, status: .done)

        vm.selectedStatusFilter = .active
        let activeTitles = vm.filteredItems.map(\.title)
        XCTAssertFalse(activeTitles.contains("A"))

        vm.selectedStatusFilter = .completed
        XCTAssertEqual(Set(vm.filteredItems.map(\.title)), Set(["A"]))

        vm.selectedStatusFilter = .high
        XCTAssertTrue(vm.filteredItems.isEmpty)
    }

    func testHighPriorityFilter() {
        let vm = TodoViewModel(modelContainer: container)
        vm.addItem(title: "High", type: .personal, context: "", criteria: "", prompt: "", minutes: 5, priority: 5)
        vm.addItem(title: "Low", type: .personal, context: "", criteria: "", prompt: "", minutes: 5, priority: 1)

        vm.selectedStatusFilter = .high
        XCTAssertEqual(vm.filteredItems.map(\.title), ["High"])

        vm.selectedStatusFilter = .all
        vm.addItem(title: "DoneHigh", type: .personal, context: "", criteria: "", prompt: "", minutes: 5, priority: 5)
        let doneHigh = vm.unarchivedItems.first { $0.title == "DoneHigh" }!
        vm.updateStatus(doneHigh, status: .done)
        vm.selectedStatusFilter = .high
        XCTAssertFalse(vm.filteredItems.map(\.title).contains("DoneHigh"))
    }

    func testArchiveRemovesFromActiveList() {
        let vm = TodoViewModel(modelContainer: container)
        vm.addItem(title: "临时事", type: .personal, context: "", criteria: "", prompt: "", minutes: 5, priority: 1)
        let item = vm.unarchivedItems[0]

        vm.archive(item)
        XCTAssertTrue(item.isArchived)
        XCTAssertTrue(vm.unarchivedItems.isEmpty)
        XCTAssertEqual(vm.completionRate, 0)
    }

    func testFilterByTaskType() {
        let vm = TodoViewModel(modelContainer: container)
        vm.addItem(title: "CodeTask", type: .code, context: "", criteria: "", prompt: "", minutes: 5, priority: 1)
        vm.addItem(title: "LifeTask", type: .life, context: "", criteria: "", prompt: "", minutes: 5, priority: 1)

        XCTAssertEqual(vm.filteredItems.count, 2)

        vm.selectedType = .code
        XCTAssertEqual(vm.filteredItems.map(\.title), ["CodeTask"])

        vm.selectedType = nil
        XCTAssertEqual(vm.filteredItems.count, 2)
    }

    func testTodayPlanUpdatesOnAdd() {
        let vm = TodoViewModel(modelContainer: container)
        vm.addItem(title: "计划项", type: .personal, context: "", criteria: "", prompt: "", minutes: 5, priority: 1)
        XCTAssertFalse(vm.todayPlan.isEmpty)
        XCTAssertEqual(vm.todayPlan.first?.title, "计划项")
    }

    func testMarkdownExport() {
        let vm = TodoViewModel(modelContainer: container)
        vm.addItem(title: "导出项", type: .code, context: "ctx", criteria: "acc", prompt: "prompt", minutes: 5, priority: 2)
        let md = vm.exportMarkdown()
        XCTAssertTrue(md.contains("导出项"))
        XCTAssertTrue(md.contains("ctx"))
    }
}