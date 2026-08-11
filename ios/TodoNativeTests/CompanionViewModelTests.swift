import XCTest
import SwiftData
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
        item.completedAt = Date()
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

    func testManualSendNeedsConsentAndRetriesRetainedRequestAfterAcceptance() async {
        let route = AIConsentRoute(identifier: "byok:openai", recipientName: "OpenAI")
        let consent = makeConsentManager()
        let chat = FakeCompanionChat(results: [
            .failure(RemoteAIConsentError.needsConsent(route)),
            .success("可以先完成发布检查。")
        ])
        let vm = CompanionViewModel(
            consentManager: consent,
            chat: chat.call
        )
        vm.messages = []
        vm.input = "帮我安排发布"

        let firstReply = await vm.send(items: [], health: 60, language: "zh")

        XCTAssertNil(firstReply)
        XCTAssertEqual(chat.callCount, 1)
        XCTAssertEqual(consent.pendingRoute, route)
        XCTAssertEqual(vm.messages.map(\.role), ["user"])

        consent.acceptPendingConsent()
        let retriedReply = await vm.resolvePendingConsent(consent.resolution)

        XCTAssertEqual(retriedReply, "可以先完成发布检查。")
        XCTAssertEqual(chat.callCount, 2)
        XCTAssertEqual(vm.messages.map(\.role), ["user", "assistant"])
    }

    func testDecliningConsentRetriesRetainedRequestIntoLocalPlanner() async {
        let route = AIConsentRoute(identifier: "byok:openai", recipientName: "OpenAI")
        let consent = makeConsentManager()
        let chat = FakeCompanionChat(results: [
            .failure(RemoteAIConsentError.needsConsent(route)),
            .failure(RemoteAIConsentError.declined(route))
        ])
        let vm = CompanionViewModel(
            consentManager: consent,
            chat: chat.call
        )
        vm.messages = []
        vm.input = "把发布拆成步骤"

        _ = await vm.send(items: [], health: 60, language: "zh")
        consent.declinePendingConsent()
        let localReply = await vm.resolvePendingConsent(consent.resolution)

        XCTAssertNotNil(localReply)
        XCTAssertEqual(chat.callCount, 2)
        XCTAssertEqual(vm.messages.map(\.role), ["user", "assistant"])
        XCTAssertFalse(vm.messages.last?.actions.isEmpty ?? true)
    }

    func testBreakdownActionNeedsConsentAndRetriesRetainedActionAfterAcceptance() async throws {
        let route = AIConsentRoute(identifier: "byok:openai", recipientName: "OpenAI")
        let consent = makeConsentManager()
        let breakdown = FakeCompanionBreakdown(results: [
            .failure(RemoteAIConsentError.needsConsent(route)),
            .success("- 检查发布配置\n- 验证构建")
        ])
        let companion = CompanionViewModel(
            consentManager: consent,
            chat: { _ in nil },
            breakdown: breakdown.call
        )
        let container = try ModelContainer(
            for: TodoItem.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let todo = TodoViewModel(modelContainer: container)
        let action = CompanionViewModel.BuddyAction(
            label: "拆解",
            kind: "breakdown",
            payload: ["text": "发布版本"]
        )

        companion.apply(action: action, in: todo)
        await yieldUntil { consent.pendingRoute != nil }

        XCTAssertEqual(consent.pendingRoute, route)
        XCTAssertEqual(breakdown.callCount, 1)
        XCTAssertTrue(todo.unarchivedItems.isEmpty)

        consent.acceptPendingConsent()
        _ = await companion.resolvePendingConsent(consent.resolution)

        XCTAssertEqual(breakdown.callCount, 2)
        XCTAssertEqual(Set(todo.unarchivedItems.map(\.title)), ["检查发布配置", "验证构建"])
    }

    private func makeConsentManager() -> AIConsentManager {
        AIConsentManager(
            consentVersion: "1",
            storage: UserDefaults(
                suiteName: "CompanionViewModelTests.consent.\(UUID().uuidString)"
            )!
        )
    }

    private func yieldUntil(_ predicate: () -> Bool) async {
        for _ in 0..<100 where !predicate() {
            await Task.yield()
        }
    }
}

@MainActor
private final class FakeCompanionChat {
    private var results: [Result<String?, Error>]
    private(set) var callCount = 0

    init(results: [Result<String?, Error>]) {
        self.results = results
    }

    func call(messages: [[String: String]]) async throws -> String? {
        callCount += 1
        return try results.removeFirst().get()
    }
}

@MainActor
private final class FakeCompanionBreakdown {
    private var results: [Result<String, Error>]
    private(set) var callCount = 0

    init(results: [Result<String, Error>]) {
        self.results = results
    }

    func call(goal: String, items: [TodoItem]) async throws -> String {
        callCount += 1
        return try results.removeFirst().get()
    }
}
