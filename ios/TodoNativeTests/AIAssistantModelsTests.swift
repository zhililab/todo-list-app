import XCTest
@testable import TodoNative

final class AIAssistantModelsTests: XCTestCase {
    private let stableID = UUID(uuidString: "00000000-0000-0000-0000-000000000010")!

    private func makeSnapshot(
        id: UUID? = nil,
        title: String = "发布",
        status: String = "todo",
        priority: Int = 4,
        estimatedMinutes: Int = 30,
        dueDate: Date? = nil,
        isArchived: Bool = false
    ) -> AIAssistantTaskSnapshot {
        AIAssistantTaskSnapshot(
            id: id ?? stableID,
            title: title,
            status: status,
            priority: priority,
            estimatedMinutes: estimatedMinutes,
            dueDate: dueDate,
            isArchived: isArchived
        )
    }

    private func fingerprint(
        _ snapshot: AIAssistantTaskSnapshot,
        health: Int = 58
    ) -> String {
        AIAssistantContext(tasks: [snapshot], health: health).fingerprint
    }

    private func requireSendable<T: Sendable>(_: T.Type) {}

    func testFingerprintIsStableAcrossItemOrder() {
        let a = AIAssistantTaskSnapshot(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            title: "发布",
            status: "todo",
            priority: 4,
            estimatedMinutes: 30,
            dueDate: Date(timeIntervalSince1970: 100),
            isArchived: false
        )
        let b = AIAssistantTaskSnapshot(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            title: "复盘",
            status: "doing",
            priority: 2,
            estimatedMinutes: 20,
            dueDate: nil,
            isArchived: false
        )

        XCTAssertEqual(
            AIAssistantContext(tasks: [a, b], health: 58).fingerprint,
            AIAssistantContext(tasks: [b, a], health: 58).fingerprint
        )
    }

    func testFingerprintChangesForRelevantTaskState() {
        let id = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let todo = AIAssistantTaskSnapshot(
            id: id,
            title: "发布",
            status: "todo",
            priority: 4,
            estimatedMinutes: 30,
            dueDate: nil,
            isArchived: false
        )
        let done = AIAssistantTaskSnapshot(
            id: id,
            title: "发布",
            status: "done",
            priority: 4,
            estimatedMinutes: 30,
            dueDate: nil,
            isArchived: false
        )

        XCTAssertNotEqual(
            AIAssistantContext(tasks: [todo], health: 58).fingerprint,
            AIAssistantContext(tasks: [done], health: 58).fingerprint
        )
    }

    func testFingerprintPreservesFullDueDatePrecision() {
        // These adjacent timestamps become the same Double after conversion to milliseconds.
        let earlierInterval = Double(bitPattern: 4_744_917_124_793_761_813)
        let laterInterval = Double(bitPattern: 4_744_917_124_793_761_814)
        let earlier = makeSnapshot(dueDate: Date(timeIntervalSince1970: earlierInterval))
        let later = makeSnapshot(dueDate: Date(timeIntervalSince1970: laterInterval))

        XCTAssertNotEqual(fingerprint(earlier), fingerprint(later))
    }

    func testFingerprintChangesForHealth() {
        let snapshot = makeSnapshot()

        XCTAssertNotEqual(fingerprint(snapshot, health: 58), fingerprint(snapshot, health: 59))
    }

    func testFingerprintChangesForTaskID() {
        let first = makeSnapshot()
        let second = makeSnapshot(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000011")!
        )

        XCTAssertNotEqual(fingerprint(first), fingerprint(second))
    }

    func testFingerprintChangesForTitle() {
        XCTAssertNotEqual(fingerprint(makeSnapshot()), fingerprint(makeSnapshot(title: "复盘")))
    }

    func testFingerprintChangesForPriority() {
        XCTAssertNotEqual(fingerprint(makeSnapshot()), fingerprint(makeSnapshot(priority: 5)))
    }

    func testFingerprintChangesForEstimatedMinutes() {
        XCTAssertNotEqual(
            fingerprint(makeSnapshot()),
            fingerprint(makeSnapshot(estimatedMinutes: 31))
        )
    }

    func testFingerprintChangesForArchiveState() {
        XCTAssertNotEqual(
            fingerprint(makeSnapshot()),
            fingerprint(makeSnapshot(isArchived: true))
        )
    }

    func testFingerprintDoesNotCollideWhenTaskFieldsContainPipe() {
        let id = UUID(uuidString: "00000000-0000-0000-0000-000000000003")!
        let titleContainsPipe = AIAssistantTaskSnapshot(
            id: id,
            title: "发布|done",
            status: "4",
            priority: 30,
            estimatedMinutes: 15,
            dueDate: nil,
            isArchived: false
        )
        let statusContainsPipe = AIAssistantTaskSnapshot(
            id: id,
            title: "发布",
            status: "done|4",
            priority: 30,
            estimatedMinutes: 15,
            dueDate: nil,
            isArchived: false
        )

        XCTAssertNotEqual(
            AIAssistantContext(tasks: [titleContainsPipe], health: 58).fingerprint,
            AIAssistantContext(tasks: [statusContainsPipe], health: 58).fingerprint
        )
    }

    func testFingerprintDoesNotCollideWhenTaskFieldsContainNewline() {
        let id = UUID(uuidString: "00000000-0000-0000-0000-000000000004")!
        let titleContainsNewline = AIAssistantTaskSnapshot(
            id: id,
            title: "发布\ndone",
            status: "4",
            priority: 30,
            estimatedMinutes: 15,
            dueDate: nil,
            isArchived: false
        )
        let statusContainsNewline = AIAssistantTaskSnapshot(
            id: id,
            title: "发布",
            status: "done\n4",
            priority: 30,
            estimatedMinutes: 15,
            dueDate: nil,
            isArchived: false
        )

        XCTAssertNotEqual(
            AIAssistantContext(tasks: [titleContainsNewline], health: 58).fingerprint,
            AIAssistantContext(tasks: [statusContainsNewline], health: 58).fingerprint
        )
    }

    func testModesExposeStableIDs() {
        XCTAssertEqual(AIWorkbenchMode.allCases.map(\.id), ["todayPlan", "breakdown", "review"])
    }

    func testAssistantValueTypesAreSendable() {
        requireSendable(AIWorkbenchMode.self)
        requireSendable(AIAssistantSource.self)
        requireSendable(AIAssistantTaskSnapshot.self)
        requireSendable(AIAssistantContext.self)
        requireSendable(AIDailyBriefContent.self)
        requireSendable(AIDailyBrief.self)
        requireSendable(AISuggestedTask.self)
        requireSendable(AIResultSection.self)
        requireSendable(AIWorkbenchResult.self)
    }
}
