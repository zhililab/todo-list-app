import XCTest
@testable import TodoNative

@MainActor
final class CompanionViewModelTests: XCTestCase {
    private let suiteName = "com.todo.test.companion.celebrate"

    private var storage: UserDefaults {
        let defaults = UserDefaults(suiteName: suiteName)!
        return defaults
    }

    override func setUp() {
        super.setUp()
        storage.removeObject(forKey: CompanionViewModel.celebratedKey)
        UserDefaults.standard.removeObject(forKey: CompanionViewModel.historyKey)
    }

    override func tearDown() {
        storage.removeObject(forKey: CompanionViewModel.celebratedKey)
        UserDefaults.standard.removeObject(forKey: CompanionViewModel.historyKey)
        super.tearDown()
    }

    private func makeCompletedItem(title: String = "完成任务") -> TodoItem {
        let item = TodoItem(title: title)
        item.status = .done
        item.completedAt = Date().addingTimeInterval(-600)
        return item
    }

    func testShouldCelebrateTrueWhenNotRecordedToday() {
        XCTAssertTrue(CompanionViewModel.shouldCelebrate(today: "2026-08-08", storage: storage))
    }

    func testShouldCelebrateFalseSameDay() {
        CompanionViewModel.markCelebrated(today: "2026-08-08", storage: storage)
        XCTAssertFalse(CompanionViewModel.shouldCelebrate(today: "2026-08-08", storage: storage))
    }

    func testShouldCelebrateTrueAfterDayChange() {
        CompanionViewModel.markCelebrated(today: "2026-08-07", storage: storage)
        XCTAssertTrue(CompanionViewModel.shouldCelebrate(today: "2026-08-08", storage: storage))
    }

    func testRunMomentsNoDuplicateCelebrateSameDay() {
        let vm = CompanionViewModel()
        vm.messages = []
        vm.runMoments(items: [makeCompletedItem()], storage: storage)
        XCTAssertEqual(vm.messages.count, 1)
        XCTAssertEqual(vm.messages.first?.role, "assistant")
        XCTAssertTrue(vm.messages.first?.text.contains("完成任务") ?? false)
        XCTAssertEqual(CompanionViewModel.shouldCelebrate(today: CompanionViewModel.todayString(), storage: storage), false)

        vm.runMoments(items: [makeCompletedItem()], storage: storage)
        XCTAssertEqual(vm.messages.count, 1)
    }

    func testRunMomentsCelebratesAgainNextDay() {
        CompanionViewModel.markCelebrated(today: "2000-01-01", storage: storage)
        let vm = CompanionViewModel()
        vm.messages = []
        vm.runMoments(items: [makeCompletedItem()], storage: storage)
        XCTAssertEqual(vm.messages.count, 1)
        XCTAssertTrue(vm.messages.first?.text.contains("完成任务") ?? false)
    }

    func testRunMomentsNoCelebrateWhenNothingCompleted() {
        let vm = CompanionViewModel()
        vm.messages = []
        vm.runMoments(items: [TodoItem(title: "普通任务")], storage: storage)
        XCTAssertTrue(vm.messages.isEmpty)
    }
}
