import XCTest
import UIKit
@testable import TodoNative

final class AIWorkbenchPresentationTests: XCTestCase {
    func testSuggestedTaskRowUsesVerticalLayoutAtAccessibilitySizes() {
        XCTAssertEqual(
            AIWorkbenchTaskRowLayoutPresentation(isAccessibilitySize: false).axis,
            .horizontal
        )
        XCTAssertEqual(
            AIWorkbenchTaskRowLayoutPresentation(isAccessibilitySize: true).axis,
            .vertical
        )
    }

    func testSuggestedTaskRowBackgroundPolicyUsesAdaptiveSemanticColors() {
        let selected = AIWorkbenchTaskRowAppearancePresentation(isSelected: true)
        let unselected = AIWorkbenchTaskRowAppearancePresentation(isSelected: false)

        XCTAssertEqual(selected.background, .selectedSoft)
        XCTAssertEqual(unselected.background, .card)

        for background in [selected.background, unselected.background] {
            let light = background.semanticUIColor.resolvedColor(
                with: UITraitCollection(userInterfaceStyle: .light)
            )
            let dark = background.semanticUIColor.resolvedColor(
                with: UITraitCollection(userInterfaceStyle: .dark)
            )
            XCTAssertFalse(light.isEqual(dark))
        }
    }

    func testModePresentationUsesDistinctCopyAndGoalPolicies() {
        let today = AIWorkbenchModePresentation(mode: .todayPlan)
        let breakdown = AIWorkbenchModePresentation(mode: .breakdown)
        let review = AIWorkbenchModePresentation(mode: .review)

        XCTAssertEqual(today.titleKey, "ai.workbench.todayPlan")
        XCTAssertEqual(today.primaryActionKey, "ai.workbench.generatePlan")
        XCTAssertTrue(today.canGenerate(goal: ""))

        XCTAssertEqual(breakdown.titleKey, "ai.workbench.breakdown")
        XCTAssertEqual(breakdown.primaryActionKey, "ai.workbench.generateBreakdown")
        XCTAssertFalse(breakdown.canGenerate(goal: "  \n "))
        XCTAssertTrue(breakdown.canGenerate(goal: "发布新版本"))

        XCTAssertEqual(review.titleKey, "ai.workbench.review")
        XCTAssertEqual(review.primaryActionKey, "ai.workbench.generateReview")
        XCTAssertTrue(review.canGenerate(goal: ""))
    }

    func testModePresentationProvidesModeSpecificQuestionsAndPromptChips() {
        XCTAssertEqual(
            AIWorkbenchModePresentation(mode: .todayPlan).questionKey,
            "ai.workbench.todayPlanQuestion"
        )
        XCTAssertEqual(
            AIWorkbenchModePresentation(mode: .breakdown).questionKey,
            "ai.workbench.breakdownQuestion"
        )
        XCTAssertEqual(
            AIWorkbenchModePresentation(mode: .review).questionKey,
            "ai.workbench.reviewQuestion"
        )
        XCTAssertEqual(AIWorkbenchModePresentation(mode: .todayPlan).chipKeys.count, 3)
        XCTAssertEqual(AIWorkbenchModePresentation(mode: .breakdown).chipKeys.count, 3)
        XCTAssertEqual(AIWorkbenchModePresentation(mode: .review).chipKeys.count, 3)
    }

    func testCustomServicePresentationIsConfiguredWithoutClaimingRemoteSuccess() {
        let presentation = AIWorkbenchServicePresentation(
            apiKey: "secret",
            managedBaseURL: "https://quota.example",
            providerName: "Moonshot (Kimi)",
            model: "kimi-k2.6",
            latestResultSource: nil
        )

        XCTAssertEqual(presentation.kind, .custom)
        XCTAssertEqual(presentation.status, .configured)
        XCTAssertEqual(presentation.statusKey, "ai.workbench.status.configured")
        XCTAssertEqual(presentation.tone, .neutral)
        XCTAssertEqual(presentation.detail, "Moonshot (Kimi) · kimi-k2.6")
    }

    func testManagedServicePresentsRemainingFreeQuotaFromSnapshot() {
        let managed = AIWorkbenchServicePresentation(
            apiKey: "",
            managedBaseURL: " https://quota.example ",
            providerName: "OpenAI",
            model: "gpt-5-mini",
            latestResultSource: nil,
            quotaSnapshot: QuotaSnapshot(
                freeUsed: 3,
                freeLimit: 10,
                proUsed: 0,
                proLimit: 20,
                isPro: false,
                today: "2026-08-10"
            )
        )
        XCTAssertEqual(managed.kind, .managed)
        XCTAssertEqual(managed.status, .managedQuota)
        XCTAssertEqual(managed.statusKey, "ai.workbench.status.managedQuota")
        XCTAssertEqual(managed.tone, .neutral)
        XCTAssertEqual(managed.quotaRemaining, 7)
        XCTAssertEqual(managed.quotaLimit, 10)
    }

    func testLocalServicePresentationFollowsMissingRemoteConfiguration() {
        let local = AIWorkbenchServicePresentation(
            apiKey: " \n ",
            managedBaseURL: "  ",
            providerName: "OpenAI",
            model: "gpt-5-mini",
            latestResultSource: nil
        )
        XCTAssertEqual(local.kind, .local)
        XCTAssertEqual(local.status, .localOnly)
        XCTAssertEqual(local.statusKey, "ai.workbench.service.local")
        XCTAssertEqual(local.tone, .neutral)
        XCTAssertNil(local.detail)
    }

    func testLatestRemoteAndLocalFallbackHaveDistinctStatusTones() {
        let remote = AIWorkbenchServicePresentation(
            apiKey: "secret",
            managedBaseURL: nil,
            providerName: "OpenAI",
            model: "gpt-5-mini",
            latestResultSource: .custom
        )
        XCTAssertEqual(remote.status, .remoteSuccess)
        XCTAssertEqual(remote.statusKey, "ai.workbench.status.remoteSuccess")
        XCTAssertEqual(remote.tone, .success)

        let fallback = AIWorkbenchServicePresentation(
            apiKey: "secret",
            managedBaseURL: nil,
            providerName: "OpenAI",
            model: "gpt-5-mini",
            latestResultSource: .local
        )
        XCTAssertEqual(fallback.status, .localFallback)
        XCTAssertEqual(fallback.statusKey, "ai.workbench.status.localFallback")
        XCTAssertEqual(fallback.tone, .warning)
    }

    func testQuotaFailureOverridesRetainedResultStatus() {
        let presentation = AIWorkbenchServicePresentation(
            apiKey: "",
            managedBaseURL: "https://quota.example",
            providerName: "OpenAI",
            model: "gpt-5-mini",
            latestResultSource: .managed,
            failure: AIAssistantFailure(error: QuotaError.quotaExceeded(kind: "free"))
        )

        XCTAssertEqual(presentation.status, .quotaExceeded)
        XCTAssertEqual(presentation.statusKey, "ai.workbench.status.quotaExceeded")
        XCTAssertEqual(presentation.tone, .critical)
    }

    func testOrdinaryFailureDoesNotMislabelRetainedRemoteResultAsCurrentSuccess() {
        let presentation = AIWorkbenchServicePresentation(
            apiKey: "secret",
            managedBaseURL: nil,
            providerName: "OpenAI",
            model: "gpt-5-mini",
            latestResultSource: .custom,
            failure: AIAssistantFailure(error: URLError(.timedOut))
        )

        XCTAssertEqual(presentation.status, .configured)
        XCTAssertEqual(presentation.statusKey, "ai.workbench.status.configured")
        XCTAssertEqual(presentation.tone, .neutral)
    }

    func testContextPresentationCountsVisibleTasksDeadlinesAndStatuses() {
        let context = AIAssistantContext(
            tasks: [
                task(status: "todo", dueDate: Date(timeIntervalSince1970: 100), isArchived: false),
                task(status: "doing", dueDate: nil, isArchived: false),
                task(status: "done", dueDate: Date(timeIntervalSince1970: 200), isArchived: false),
                task(status: "todo", dueDate: Date(timeIntervalSince1970: 300), isArchived: true)
            ],
            health: 68
        )

        let presentation = AIWorkbenchContextPresentation(context: context)

        XCTAssertEqual(presentation.taskCount, 3)
        XCTAssertEqual(presentation.deadlineCount, 2)
        XCTAssertEqual(presentation.todoCount, 1)
        XCTAssertEqual(presentation.doingCount, 1)
        XCTAssertEqual(presentation.doneCount, 1)
        XCTAssertEqual(presentation.health, 68)
    }

    func testTaskResultUsesActualImportableCountAndDisablesZeroCount() {
        let importable = AIWorkbenchResultPresentation(
            mode: .todayPlan,
            importableCount: 2,
            hasSuggestedTasks: true
        )
        XCTAssertEqual(importable.importKey, "ai.workbench.addToToday")
        XCTAssertEqual(importable.importCount, 2)
        XCTAssertTrue(importable.showsImport)
        XCTAssertTrue(importable.canImport)
        XCTAssertEqual(importable.importAnnouncementKey, "ai.workbench.appliedToToday")

        let allDuplicates = AIWorkbenchResultPresentation(
            mode: .todayPlan,
            importableCount: 0,
            hasSuggestedTasks: true
        )
        XCTAssertEqual(allDuplicates.importKey, "ai.workbench.addToToday")
        XCTAssertEqual(allDuplicates.importCount, 0)
        XCTAssertTrue(allDuplicates.showsImport)
        XCTAssertFalse(allDuplicates.canImport)
        XCTAssertNil(allDuplicates.importAnnouncementKey)
    }

    func testBreakdownImportsToTasksAndReviewNeverShowsImport() {
        let breakdown = AIWorkbenchResultPresentation(
            mode: .breakdown,
            importableCount: 3,
            hasSuggestedTasks: true
        )
        XCTAssertEqual(breakdown.importKey, "ai.workbench.addToTodo")
        XCTAssertEqual(breakdown.importAnnouncementKey, "ai.workbench.imported")

        let review = AIWorkbenchResultPresentation(
            mode: .review,
            importableCount: 0,
            hasSuggestedTasks: false
        )
        XCTAssertNil(review.importKey)
        XCTAssertFalse(review.showsImport)
        XCTAssertFalse(review.canImport)
    }

    func testSuccessfulApplicationsProduceModeSpecificVisibleConfirmations() {
        let today = AIWorkbenchConfirmationPresentation(
            mode: .todayPlan,
            appliedCount: 2
        )
        XCTAssertTrue(today.isVisible)
        XCTAssertEqual(today.messageKey, "ai.workbench.confirmation.today")
        XCTAssertEqual(today.count, 2)

        let breakdown = AIWorkbenchConfirmationPresentation(
            mode: .breakdown,
            appliedCount: 3
        )
        XCTAssertTrue(breakdown.isVisible)
        XCTAssertEqual(breakdown.messageKey, "ai.workbench.confirmation.tasks")
        XCTAssertEqual(breakdown.count, 3)
    }

    func testZeroAppliedItemsNeverProducesSuccessConfirmation() {
        for mode in AIWorkbenchMode.allCases {
            let presentation = AIWorkbenchConfirmationPresentation(
                mode: mode,
                appliedCount: 0
            )
            XCTAssertFalse(presentation.isVisible)
            XCTAssertNil(presentation.messageKey)
            XCTAssertEqual(presentation.count, 0)
        }
    }

    func testSessionFreshnessComesFromPersistentProvenance() {
        let result = AIWorkbenchResult(
            overview: "旧建议",
            suggestedTasks: [],
            sections: [],
            source: .managed
        )
        let session = AIWorkbenchSession(
            provenance: AIWorkbenchProvenance(
                mode: .breakdown,
                goal: "发布 1.0",
                contextFingerprint: "context-a"
            ),
            result: result
        )

        let stale = AIWorkbenchSessionPresentation(
            state: .result(session),
            currentMode: .breakdown,
            currentGoal: "发布 2.0",
            currentContextFingerprint: "context-a"
        )
        XCTAssertEqual(stale.session, session)
        XCTAssertFalse(stale.isFresh)
        XCTAssertTrue(stale.showsStaleResult)

        let fresh = AIWorkbenchSessionPresentation(
            state: .failed(
                previous: session,
                failure: AIAssistantFailure(error: QuotaError.quotaExceeded(kind: "daily"))
            ),
            currentMode: .breakdown,
            currentGoal: "发布 1.0",
            currentContextFingerprint: "context-a"
        )
        XCTAssertTrue(fresh.isFresh)
        XCTAssertTrue(fresh.showsRetainedResult)
        XCTAssertFalse(fresh.showsStaleResult)
        XCTAssertNil(fresh.currentResultSource)

        let current = AIWorkbenchSessionPresentation(
            state: .result(session),
            currentMode: .breakdown,
            currentGoal: "发布 1.0",
            currentContextFingerprint: "context-a"
        )
        XCTAssertEqual(current.currentResultSource, .managed)
    }

    private func task(status: String, dueDate: Date?, isArchived: Bool) -> AIAssistantTaskSnapshot {
        AIAssistantTaskSnapshot(
            id: UUID(),
            title: "任务",
            status: status,
            priority: 3,
            estimatedMinutes: 30,
            dueDate: dueDate,
            isArchived: isArchived
        )
    }
}
