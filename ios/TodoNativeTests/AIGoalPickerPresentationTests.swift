import XCTest
@testable import TodoNative

@MainActor
final class AIGoalPickerPresentationTests: XCTestCase {
    func testCandidatesFilterGroupAndSortDeterministically() {
        let dueSoon = item(
            id: "00000000-0000-0000-0000-000000000020",
            title: "Due soon",
            priority: 3,
            status: .todo,
            dueDate: date(20),
            updatedAt: date(5)
        )
        let dueLater = item(
            id: "00000000-0000-0000-0000-000000000021",
            title: "Due later",
            priority: 3,
            status: .todo,
            dueDate: date(30),
            updatedAt: date(6)
        )
        let noDueNew = item(
            id: "00000000-0000-0000-0000-000000000022",
            title: "No due, newer",
            priority: 3,
            status: .todo,
            updatedAt: date(9)
        )
        let noDueTieA = item(
            id: "00000000-0000-0000-0000-000000000023",
            title: "No due, tie A",
            priority: 3,
            status: .todo,
            updatedAt: date(8)
        )
        let noDueTieB = item(
            id: "00000000-0000-0000-0000-000000000024",
            title: "No due, tie B",
            priority: 3,
            status: .todo,
            updatedAt: date(8)
        )
        let todoHighestPriority = item(
            id: "00000000-0000-0000-0000-000000000025",
            title: "Highest priority",
            priority: 5,
            status: .todo,
            updatedAt: date(1)
        )
        let doingHigh = item(
            id: "00000000-0000-0000-0000-000000000010",
            title: "Doing high",
            priority: 5,
            status: .doing,
            updatedAt: date(1)
        )
        let doingLow = item(
            id: "00000000-0000-0000-0000-000000000011",
            title: "Doing low",
            priority: 1,
            status: .doing,
            dueDate: date(2),
            updatedAt: date(2)
        )
        let done = item(title: "Done", status: .done)
        let archivedStatus = item(title: "Archived status", status: .archived)
        let archivedFlag = item(title: "Archived flag", status: .todo, isArchived: true)
        let blank = item(title: " \n\t ", priority: 5, status: .doing)

        let presentation = AIGoalPickerPresentation(
            items: [
                noDueTieB, done, doingLow, dueLater, blank, archivedFlag,
                todoHighestPriority, noDueNew, doingHigh, archivedStatus, noDueTieA, dueSoon
            ],
            query: ""
        )

        XCTAssertEqual(presentation.doing.map(\.id), [doingHigh.id, doingLow.id])
        XCTAssertEqual(
            presentation.todo.map(\.id),
            [todoHighestPriority.id, dueSoon.id, dueLater.id, noDueNew.id, noDueTieA.id, noDueTieB.id]
        )
        XCTAssertEqual(presentation.all.map(\.id), presentation.doing.map(\.id) + presentation.todo.map(\.id))
        XCTAssertFalse(presentation.all.contains(where: { $0.id == done.id }))
        XCTAssertFalse(presentation.all.contains(where: { $0.id == archivedStatus.id }))
        XCTAssertFalse(presentation.all.contains(where: { $0.id == archivedFlag.id }))
        XCTAssertFalse(presentation.all.contains(where: { $0.id == blank.id }))
    }

    func testSearchTrimsQueryAndMatchesEachApprovedFieldCaseInsensitively() {
        let title = item(title: "Ship MixedCase Title")
        let context = item(title: "Context task", context: "Stakeholder CONTEXT Needle")
        let acceptance = item(title: "Acceptance task", acceptanceCriteria: "Acceptance CRITERIA Needle")
        let prompt = item(title: "Prompt task", nextPrompt: "Ask the NEXT Prompt Needle")
        let source = item(title: "Source task", sourceGoal: "Release SOURCE Goal Needle")
        let items = [title, context, acceptance, prompt, source]

        XCTAssertEqual(matches(items, query: "  mixedcase  "), [title.id])
        XCTAssertEqual(matches(items, query: "  context needle  "), [context.id])
        XCTAssertEqual(matches(items, query: "  criteria needle  "), [acceptance.id])
        XCTAssertEqual(matches(items, query: "  next prompt needle  "), [prompt.id])
        XCTAssertEqual(matches(items, query: "  source goal needle  "), [source.id])
        XCTAssertEqual(Set(matches(items, query: "  \n\t ")), Set(items.map(\.id)))
    }

    func testCandidateCopiesDisplayFieldsAndTrimsItsTitle() throws {
        let source = item(
            title: "  Release 1.0  ",
            context: "Context",
            acceptanceCriteria: "Accepted",
            nextPrompt: "Next",
            taskType: .product,
            priority: 4,
            status: .doing,
            dueDate: date(42),
            sourceGoal: "Roadmap",
            updatedAt: date(7)
        )

        let candidate = try XCTUnwrap(AIGoalPickerCandidate(item: source))

        XCTAssertEqual(candidate.id, source.id)
        XCTAssertEqual(candidate.title, "Release 1.0")
        XCTAssertEqual(candidate.context, "Context")
        XCTAssertEqual(candidate.acceptanceCriteria, "Accepted")
        XCTAssertEqual(candidate.nextPrompt, "Next")
        XCTAssertEqual(candidate.sourceGoal, "Roadmap")
        XCTAssertEqual(candidate.taskType, .product)
        XCTAssertEqual(candidate.priority, 4)
        XCTAssertEqual(candidate.status, .doing)
        XCTAssertEqual(candidate.dueDate, date(42))
        XCTAssertEqual(candidate.updatedAt, date(7))
    }

    func testPickerCandidateAndSelectedContextShareEligibilityBehavior() {
        let cases = [
            item(title: "Todo", status: .todo),
            item(title: "Doing", status: .doing),
            item(title: "Done", status: .done),
            item(title: "Archived status", status: .archived),
            item(title: "Archived flag", status: .todo, isArchived: true),
            item(title: " \n\t ", status: .doing)
        ]

        for source in cases {
            XCTAssertEqual(
                AIGoalPickerCandidate(item: source) != nil,
                AISelectedGoalContext(item: source) != nil,
                source.title
            )
        }
    }

    func testCandidateRevisionIsOrderIndependentAndTracksReconciliationFields() {
        let first = item(
            id: "00000000-0000-0000-0000-000000000031",
            title: "First",
            status: .todo,
            updatedAt: date(1)
        )
        let second = item(
            id: "00000000-0000-0000-0000-000000000032",
            title: "Second",
            status: .doing,
            updatedAt: date(2)
        )
        let original = AIGoalPickerPresentation.candidateRevision(items: [first, second])

        XCTAssertEqual(
            original,
            AIGoalPickerPresentation.candidateRevision(items: [second, first])
        )

        first.status = .done
        XCTAssertNotEqual(original, AIGoalPickerPresentation.candidateRevision(items: [first, second]))
        first.status = .todo
        first.isArchived = true
        XCTAssertNotEqual(original, AIGoalPickerPresentation.candidateRevision(items: [first, second]))
        first.isArchived = false
        first.updatedAt = date(3)
        XCTAssertNotEqual(original, AIGoalPickerPresentation.candidateRevision(items: [first, second]))
    }

    private func matches(_ items: [TodoItem], query: String) -> [UUID] {
        AIGoalPickerPresentation(items: items, query: query).all.map(\.id)
    }

    private func date(_ seconds: TimeInterval) -> Date {
        Date(timeIntervalSince1970: seconds)
    }

    private func item(
        id: String = UUID().uuidString,
        title: String,
        context: String = "",
        acceptanceCriteria: String = "",
        nextPrompt: String = "",
        taskType: TaskType = .personal,
        priority: Int = 3,
        status: TodoStatus = .todo,
        dueDate: Date? = nil,
        isArchived: Bool = false,
        sourceGoal: String = "",
        updatedAt: Date? = nil
    ) -> TodoItem {
        let item = TodoItem(
            title: title,
            context: context,
            acceptanceCriteria: acceptanceCriteria,
            nextPrompt: nextPrompt,
            taskType: taskType,
            priority: priority,
            status: status,
            dueDate: dueDate,
            isArchived: isArchived,
            sourceGoal: sourceGoal
        )
        item.id = UUID(uuidString: id)!
        item.updatedAt = updatedAt ?? date(0)
        return item
    }
}
