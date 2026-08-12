import XCTest
@testable import TodoNative

@MainActor
final class AIBriefingViewModelTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_786_233_600)

    func testConcurrentAppearancesGenerateOnlyOnce() async {
        let service = ControlledAssistantService()
        let cache = MemoryBriefCache()
        let attempts = MemoryBriefAttemptTracker()
        let vm = AIBriefingViewModel(service: service, cache: cache, attemptTracker: attempts)

        let first = Task { await vm.appear(items: [], health: 50, now: now) }
        await service.waitForDailyBriefCalls(1)

        let second = Task {
            await vm.appear(items: [], health: 50, now: now.addingTimeInterval(60))
        }
        await second.value

        XCTAssertEqual(service.dailyBriefCalls.count, 1)
        XCTAssertTrue(attempts.hasAttemptedAutomaticGeneration(for: "2026-08-09"))

        service.completeNextDailyBrief()
        await first.value
    }

    func testAutomaticAttemptPersistsAcrossViewModelReconstructionAndManualRefreshCanRetry() async {
        let cache = MemoryBriefCache()
        let attempts = MemoryBriefAttemptTracker()
        let firstService = ImmediateAssistantService()
        firstService.dailyBriefError = QuotaError.quotaExceeded(kind: "daily")
        let firstVM = AIBriefingViewModel(
            service: firstService,
            cache: cache,
            attemptTracker: attempts
        )

        await firstVM.appear(items: [], health: 50, now: now)
        XCTAssertEqual(firstService.dailyBriefCalls.count, 1)

        let secondService = ImmediateAssistantService()
        let secondVM = AIBriefingViewModel(
            service: secondService,
            cache: cache,
            attemptTracker: attempts
        )
        await secondVM.appear(items: [], health: 50, now: now.addingTimeInterval(120))
        XCTAssertEqual(secondService.dailyBriefCalls.count, 0)

        await secondVM.refresh(items: [], health: 50, now: now.addingTimeInterval(180))
        XCTAssertEqual(secondService.dailyBriefCalls.count, 1)
    }

    func testAutomaticGenerationRunsAgainOnNextCalendarDay() async {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let firstDay = calendar.date(
            from: DateComponents(year: 2026, month: 8, day: 9, hour: 12)
        )!
        let nextDay = calendar.date(byAdding: .day, value: 1, to: firstDay)!
        let service = ImmediateAssistantService()
        let vm = AIBriefingViewModel(
            service: service,
            cache: MemoryBriefCache(),
            attemptTracker: MemoryBriefAttemptTracker()
        )

        await vm.appear(items: [], health: 50, now: firstDay, calendar: calendar)
        await vm.appear(items: [], health: 50, now: nextDay, calendar: calendar)

        XCTAssertEqual(service.dailyBriefCalls.count, 2)
    }

    func testAutomaticBriefAndManualRefreshUseDistinctRemoteIntents() async {
        let service = ImmediateAssistantService()
        let vm = AIBriefingViewModel(
            service: service,
            cache: MemoryBriefCache(),
            attemptTracker: MemoryBriefAttemptTracker()
        )

        await vm.appear(items: [], health: 50, now: now)
        await vm.refresh(items: [], health: 50, now: now.addingTimeInterval(60))

        XCTAssertEqual(service.dailyBriefIntents, [.automatic, .manual])
    }

    func testManualWorkbenchNeedsConsentPresentsAndRetainsRequestForResolutionRetry() async {
        let service = ImmediateAssistantService()
        let route = AIConsentRoute(
            identifier: "managed:worker.example:deepseek",
            recipientName: "Managed AI service and DeepSeek"
        )
        service.workbenchError = RemoteAIConsentError.needsConsent(route)
        let consent = AIConsentManager(
            consentVersion: "1",
            storage: UserDefaults(suiteName: "AIBriefingViewModelTests.consent.\(UUID().uuidString)")!
        )
        let vm = AIBriefingViewModel(
            service: service,
            cache: MemoryBriefCache(),
            attemptTracker: MemoryBriefAttemptTracker(),
            consentManager: consent
        )
        vm.goal = "发布版本"

        await vm.runWorkbench(items: [], health: 50, now: now)

        XCTAssertEqual(consent.pendingRoute, route)
        XCTAssertEqual(service.workbenchCalls.count, 1)
        XCTAssertEqual(vm.workbenchState, .idle)

        service.workbenchError = nil
        consent.acceptPendingConsent(at: now)
        await vm.resolvePendingConsent(consent.resolution)

        XCTAssertEqual(service.workbenchCalls.count, 2)
        guard case .result = vm.workbenchState else {
            return XCTFail("Expected retained workbench request to retry")
        }
    }

    func testSelectingTaskFillsEditableGoalAndRetainsSelectionAfterTextEdit() {
        let vm = makeViewModel()
        vm.mode = .breakdown
        let item = activeItem(title: "发布 1.0")

        vm.selectGoalTask(item)

        XCTAssertEqual(vm.selectedGoalTaskID, item.id)
        XCTAssertEqual(vm.goal, "发布 1.0")

        vm.goal = "先发布 iOS 版本"
        XCTAssertEqual(vm.selectedGoalTaskID, item.id)
    }

    func testClearingAndReplacingSelectionPreserveExplicitTextOwnership() {
        let vm = makeViewModel()
        vm.mode = .breakdown
        let first = activeItem(title: "发布 Web")
        let second = activeItem(title: "发布 iOS")

        vm.selectGoalTask(first)
        vm.goal = "保留用户编辑"
        vm.clearSelectedGoalTask()

        XCTAssertNil(vm.selectedGoalTaskID)
        XCTAssertEqual(vm.goal, "保留用户编辑")

        vm.selectGoalTask(first)
        vm.selectGoalTask(second)
        XCTAssertEqual(vm.selectedGoalTaskID, second.id)
        XCTAssertEqual(vm.goal, "发布 iOS")
    }

    func testLeavingBreakdownModeClearsSelectionButPreservesGoalText() {
        let vm = makeViewModel()
        vm.mode = .breakdown
        let item = activeItem(title: "发布 1.0")
        vm.selectGoalTask(item)
        vm.goal = "先发布 iOS"

        vm.mode = .review

        XCTAssertNil(vm.selectedGoalTaskID)
        XCTAssertEqual(vm.goal, "先发布 iOS")
    }

    func testReconcileClearsCompletedArchivedAndDeletedSelections() {
        let vm = makeViewModel()
        vm.mode = .breakdown

        let completed = activeItem(title: "已完成")
        vm.selectGoalTask(completed)
        completed.status = .done
        vm.reconcileSelectedGoal(in: [completed])
        XCTAssertNil(vm.selectedGoalTaskID)
        XCTAssertEqual(vm.goal, "已完成")

        let archived = activeItem(title: "已归档")
        vm.selectGoalTask(archived)
        archived.isArchived = true
        vm.reconcileSelectedGoal(in: [archived])
        XCTAssertNil(vm.selectedGoalTaskID)
        XCTAssertEqual(vm.goal, "已归档")

        let deleted = activeItem(title: "已删除")
        vm.selectGoalTask(deleted)
        vm.reconcileSelectedGoal(in: [])
        XCTAssertNil(vm.selectedGoalTaskID)
        XCTAssertEqual(vm.goal, "已删除")
    }

    func testInvalidSelectedGoalReconcilesBeforeBlankGenerationEligibility() {
        let vm = makeViewModel()
        vm.mode = .breakdown
        let item = activeItem(title: "发布 1.0")
        vm.selectGoalTask(item)
        vm.goal = " \n\t "

        item.status = .done
        vm.reconcileSelectedGoal(in: [item])

        let selectedGoalFingerprint = vm.selectedGoalContext(in: [item])?.fingerprint
        XCTAssertNil(vm.selectedGoalTaskID)
        XCTAssertNil(selectedGoalFingerprint)
        XCTAssertFalse(
            AIWorkbenchModePresentation(mode: vm.mode).canGenerate(
                goal: vm.goal,
                selectedGoalFingerprint: selectedGoalFingerprint
            )
        )
    }

    func testReconcileArchivedStatusClearsAssociationAndInvalidatesResultWithoutChangingGoal() async {
        let suggestion = suggestedTask(
            id: "00000000-0000-0000-0000-000000000094",
            title: "提交审核"
        )
        let service = ImmediateAssistantService()
        service.workbenchResult = AIWorkbenchResult(
            overview: "拆解结果",
            suggestedTasks: [suggestion],
            sections: [],
            source: .managed
        )
        let vm = makeViewModel(service: service)
        vm.mode = .breakdown
        let item = activeItem(title: "发布 1.0")
        vm.selectGoalTask(item)
        await vm.runWorkbench(items: [item], health: 50, now: now)
        guard case .result = vm.workbenchState else {
            return XCTFail("Expected workbench result before reconciliation")
        }

        item.status = .archived
        XCTAssertFalse(item.isArchived)
        vm.reconcileSelectedGoal(in: [item])

        XCTAssertNil(vm.selectedGoalTaskID)
        XCTAssertEqual(vm.goal, "发布 1.0")
        XCTAssertNil(vm.selectedGoalContext(in: [item]))
        XCTAssertEqual(vm.workbenchState, .idle)
        XCTAssertTrue(vm.selectedTaskIDs.isEmpty)
    }

    func testRunRestoresBlankGoalAndUsesLatestSelectedTaskSnapshot() async throws {
        let service = ImmediateAssistantService()
        let vm = makeViewModel(service: service)
        vm.mode = .breakdown
        let item = activeItem(title: "发布 1.0", acceptanceCriteria: "原验收")
        vm.selectGoalTask(item)
        vm.goal = " \n\t "
        item.acceptanceCriteria = "最新验收"

        await vm.runWorkbench(items: [item], health: 50, now: now)

        XCTAssertEqual(vm.goal, "发布 1.0")
        let selected = try XCTUnwrap(service.workbenchSelectedGoals.first ?? nil)
        XCTAssertEqual(selected.id, item.id)
        XCTAssertEqual(selected.acceptanceCriteria, "最新验收")
    }

    func testConsentRetryPreservesSelectedTaskRequestSnapshot() async throws {
        let service = ImmediateAssistantService()
        let route = AIConsentRoute(
            identifier: "managed:worker.example:deepseek:selected",
            recipientName: "Managed AI service and DeepSeek"
        )
        service.workbenchError = RemoteAIConsentError.needsConsent(route)
        let consent = AIConsentManager(
            consentVersion: "1",
            storage: UserDefaults(suiteName: "AIBriefingViewModelTests.selected-consent.\(UUID().uuidString)")!
        )
        let vm = AIBriefingViewModel(
            service: service,
            cache: MemoryBriefCache(),
            attemptTracker: MemoryBriefAttemptTracker(),
            consentManager: consent
        )
        vm.mode = .breakdown
        let item = activeItem(title: "发布 1.0", acceptanceCriteria: "原验收")
        vm.selectGoalTask(item)

        await vm.runWorkbench(items: [item], health: 50, now: now)
        let originalSnapshot = try XCTUnwrap(service.workbenchSelectedGoals.first ?? nil)
        item.acceptanceCriteria = "请求后变化"

        service.workbenchError = nil
        consent.acceptPendingConsent(at: now)
        await vm.resolvePendingConsent(consent.resolution)

        XCTAssertEqual(service.workbenchSelectedGoals.count, 2)
        XCTAssertEqual(service.workbenchSelectedGoals[1], originalSnapshot)
        XCTAssertEqual(originalSnapshot.acceptanceCriteria, "原验收")
    }

    func testClearingSelectedGoalCancelsPendingConsentRetry() async {
        let service = ImmediateAssistantService()
        let oldSuggestion = suggestedTask(
            id: "00000000-0000-0000-0000-000000000091",
            title: "旧任务"
        )
        service.workbenchResult = AIWorkbenchResult(
            overview: "旧结果",
            suggestedTasks: [oldSuggestion],
            sections: [],
            source: .managed
        )
        let route = AIConsentRoute(
            identifier: "managed:worker.example:clear-selected",
            recipientName: "Managed AI service and DeepSeek"
        )
        service.workbenchError = RemoteAIConsentError.needsConsent(route)
        let consent = AIConsentManager(
            consentVersion: "1",
            storage: UserDefaults(suiteName: "AIBriefingViewModelTests.clear-selected.\(UUID().uuidString)")!
        )
        let vm = AIBriefingViewModel(
            service: service,
            cache: MemoryBriefCache(),
            attemptTracker: MemoryBriefAttemptTracker(),
            consentManager: consent
        )
        vm.mode = .breakdown
        let oldGoal = activeItem(title: "旧目标")
        vm.selectGoalTask(oldGoal)
        await vm.runWorkbench(items: [oldGoal], health: 50, now: now)

        vm.clearSelectedGoalTask()
        service.workbenchError = nil
        consent.acceptPendingConsent(at: now)
        await vm.resolvePendingConsent(consent.resolution)

        XCTAssertEqual(service.workbenchCalls.count, 1)
        XCTAssertEqual(vm.workbenchState, .idle)
        XCTAssertFalse(vm.selectedTaskIDs.contains(oldSuggestion.id))
        XCTAssertNil(vm.selectedGoalTaskID)
    }

    func testReplacingSelectedGoalCancelsPendingConsentRetry() async {
        let service = ImmediateAssistantService()
        let oldSuggestion = suggestedTask(
            id: "00000000-0000-0000-0000-000000000092",
            title: "旧任务"
        )
        service.workbenchResult = AIWorkbenchResult(
            overview: "旧结果",
            suggestedTasks: [oldSuggestion],
            sections: [],
            source: .managed
        )
        let route = AIConsentRoute(
            identifier: "managed:worker.example:replace-selected",
            recipientName: "Managed AI service and DeepSeek"
        )
        service.workbenchError = RemoteAIConsentError.needsConsent(route)
        let consent = AIConsentManager(
            consentVersion: "1",
            storage: UserDefaults(suiteName: "AIBriefingViewModelTests.replace-selected.\(UUID().uuidString)")!
        )
        let vm = AIBriefingViewModel(
            service: service,
            cache: MemoryBriefCache(),
            attemptTracker: MemoryBriefAttemptTracker(),
            consentManager: consent
        )
        vm.mode = .breakdown
        let oldGoal = activeItem(title: "旧目标")
        let replacement = activeItem(title: "新目标")
        vm.selectGoalTask(oldGoal)
        await vm.runWorkbench(items: [oldGoal], health: 50, now: now)

        vm.selectGoalTask(replacement)
        service.workbenchError = nil
        consent.acceptPendingConsent(at: now)
        await vm.resolvePendingConsent(consent.resolution)

        XCTAssertEqual(service.workbenchCalls.count, 1)
        XCTAssertEqual(vm.workbenchState, .idle)
        XCTAssertFalse(vm.selectedTaskIDs.contains(oldSuggestion.id))
        XCTAssertEqual(vm.selectedGoalTaskID, replacement.id)
        XCTAssertEqual(vm.goal, replacement.title)
    }

    func testLeavingBreakdownModeCancelsPendingConsentRetry() async {
        let service = ImmediateAssistantService()
        let oldSuggestion = suggestedTask(
            id: "00000000-0000-0000-0000-000000000093",
            title: "旧任务"
        )
        service.workbenchResult = AIWorkbenchResult(
            overview: "旧结果",
            suggestedTasks: [oldSuggestion],
            sections: [],
            source: .managed
        )
        let route = AIConsentRoute(
            identifier: "managed:worker.example:leave-breakdown",
            recipientName: "Managed AI service and DeepSeek"
        )
        service.workbenchError = RemoteAIConsentError.needsConsent(route)
        let consent = AIConsentManager(
            consentVersion: "1",
            storage: UserDefaults(suiteName: "AIBriefingViewModelTests.leave-breakdown.\(UUID().uuidString)")!
        )
        let vm = AIBriefingViewModel(
            service: service,
            cache: MemoryBriefCache(),
            attemptTracker: MemoryBriefAttemptTracker(),
            consentManager: consent
        )
        vm.mode = .breakdown
        let oldGoal = activeItem(title: "旧目标")
        vm.selectGoalTask(oldGoal)
        await vm.runWorkbench(items: [oldGoal], health: 50, now: now)

        vm.mode = .review
        service.workbenchError = nil
        consent.acceptPendingConsent(at: now)
        await vm.resolvePendingConsent(consent.resolution)

        XCTAssertEqual(service.workbenchCalls.count, 1)
        XCTAssertEqual(vm.workbenchState, .idle)
        XCTAssertFalse(vm.selectedTaskIDs.contains(oldSuggestion.id))
        XCTAssertNil(vm.selectedGoalTaskID)
        XCTAssertEqual(vm.mode, .review)
    }

    func testTodayCacheWinsWithoutCallingService() async {
        let service = ImmediateAssistantService()
        let cache = MemoryBriefCache()
        let todayBrief = makeBrief(summary: "今天", fingerprint: "today")
        cache.save(makeBrief(summary: "昨天", fingerprint: "old"), for: "2026-08-08")
        cache.save(todayBrief, for: "2026-08-09")
        let vm = AIBriefingViewModel(
            service: service,
            cache: cache,
            attemptTracker: MemoryBriefAttemptTracker()
        )

        await vm.appear(items: [], health: 50, now: now)

        XCTAssertEqual(vm.briefState, .loaded(todayBrief))
        XCTAssertEqual(service.dailyBriefCalls.count, 0)
    }

    func testRepeatedAppearWithTodayCacheDoesNotCancelInFlightManualRefresh() async {
        let service = ControlledAssistantService()
        let cache = MemoryBriefCache()
        let contextFingerprint = AIAssistantContext(items: [], health: 50).fingerprint
        let cachedBrief = makeBrief(summary: "缓存简报", fingerprint: contextFingerprint)
        cache.save(cachedBrief, for: "2026-08-09")
        let vm = AIBriefingViewModel(
            service: service,
            cache: cache,
            attemptTracker: MemoryBriefAttemptTracker()
        )
        await vm.appear(items: [], health: 50, now: now)
        let refreshDate = now.addingTimeInterval(60)

        let refresh = Task {
            await vm.refresh(items: [], health: 50, now: refreshDate)
        }
        await service.waitForDailyBriefCalls(1)

        await vm.appear(items: [], health: 50, now: now.addingTimeInterval(120))

        XCTAssertEqual(vm.briefState, .loading(previous: cachedBrief))
        XCTAssertEqual(service.dailyBriefCalls.count, 1)

        service.completeNextDailyBrief()
        await refresh.value

        guard case .loaded(let refreshedBrief) = vm.briefState else {
            return XCTFail("Expected refresh response to replace the cached brief")
        }
        XCTAssertEqual(refreshedBrief.content.summary, "先发布")
        XCTAssertEqual(refreshedBrief.generatedAt, refreshDate)
        XCTAssertEqual(cache.load(for: "2026-08-09"), refreshedBrief)
    }

    func testQuotaFailureKeepsMostRecentBriefAndTypedRecoveryWithoutWritingTodayCache() async {
        let service = ImmediateAssistantService()
        service.dailyBriefError = QuotaError.quotaExceeded(kind: "free")
        let cache = MemoryBriefCache()
        let previous = makeBrief(summary: "昨日简报", fingerprint: "old")
        cache.save(previous, for: "2026-08-08")
        let vm = AIBriefingViewModel(
            service: service,
            cache: cache,
            attemptTracker: MemoryBriefAttemptTracker()
        )

        await vm.appear(items: [], health: 50, now: now)

        guard case .failed(let retained, let failure) = vm.briefState else {
            return XCTFail("Expected a failed brief state")
        }
        XCTAssertEqual(retained, previous)
        XCTAssertEqual(failure.kind, .quotaExceeded(kind: "free"))
        XCTAssertEqual(failure.recovery, [.manageSubscription, .configureProvider])
        XCTAssertNil(cache.load(for: "2026-08-09"))
        XCTAssertEqual(cache.loadMostRecent(), previous)
    }

    func testContextChangeDuringBriefRequestShowsResponseAsStale() async {
        let service = ControlledAssistantService()
        let vm = AIBriefingViewModel(
            service: service,
            cache: MemoryBriefCache(),
            attemptTracker: MemoryBriefAttemptTracker()
        )

        let request = Task { await vm.appear(items: [], health: 50, now: now) }
        await service.waitForDailyBriefCalls(1)
        vm.contextDidChange(items: [TodoItem(title: "新任务")], health: 50)
        service.completeNextDailyBrief()
        await request.value

        guard case .loaded(let brief) = vm.briefState else {
            return XCTFail("Expected the completed brief to remain visible")
        }
        XCTAssertEqual(brief.contextFingerprint, AIAssistantContext(items: [], health: 50).fingerprint)
        XCTAssertTrue(vm.isBriefStale)
    }

    func testWorkbenchCompletionDoesNotInvalidateInFlightBrief() async {
        let service = ControlledAssistantService()
        let vm = AIBriefingViewModel(
            service: service,
            cache: MemoryBriefCache(),
            attemptTracker: MemoryBriefAttemptTracker()
        )

        let briefRequest = Task { await vm.appear(items: [], health: 50, now: now) }
        await service.waitForDailyBriefCalls(1)
        let workbenchRequest = Task { await vm.runWorkbench(items: [], health: 50, now: now) }
        await service.waitForWorkbenchCalls(1)

        service.completeNextWorkbench()
        await workbenchRequest.value
        guard case .result = vm.workbenchState else {
            return XCTFail("Expected workbench result")
        }

        service.completeNextDailyBrief()
        await briefRequest.value
        guard case .loaded = vm.briefState else {
            return XCTFail("Workbench must not invalidate the brief request")
        }
    }

    func testModeSwitchInvalidatesOldWorkbenchResponseAndClearsSelectionWithoutChangingBrief() async {
        let service = ControlledAssistantService()
        let cache = MemoryBriefCache()
        let cachedBrief = makeBrief(
            summary: "保留简报",
            fingerprint: AIAssistantContext(items: [], health: 50).fingerprint
        )
        cache.save(cachedBrief, for: "2026-08-09")
        let vm = AIBriefingViewModel(
            service: service,
            cache: cache,
            attemptTracker: MemoryBriefAttemptTracker()
        )
        await vm.appear(items: [], health: 50, now: now)
        let briefStateBeforeRun = vm.briefState

        let request = Task { await vm.runWorkbench(items: [], health: 50, now: now) }
        await service.waitForWorkbenchCalls(1)
        vm.mode = .review

        XCTAssertEqual(vm.workbenchState, .idle)
        XCTAssertTrue(vm.selectedTaskIDs.isEmpty)
        XCTAssertEqual(vm.briefState, briefStateBeforeRun)

        service.completeNextWorkbench()
        await request.value
        XCTAssertEqual(vm.workbenchState, .idle)
        XCTAssertEqual(vm.briefState, briefStateBeforeRun)
    }

    func testModeSwitchCancelsInFlightWorkbenchServiceTask() async {
        let service = CancellationAwareAssistantService()
        let vm = AIBriefingViewModel(
            service: service,
            cache: MemoryBriefCache(),
            attemptTracker: MemoryBriefAttemptTracker()
        )

        let request = Task { await vm.runWorkbench(items: [], health: 50, now: now) }
        await service.waitForWorkbenchCalls(1)
        vm.mode = .review
        await yieldUntil { service.workbenchCancellations == 1 }

        XCTAssertEqual(service.workbenchCancellations, 1)
        request.cancel()
        await request.value
    }

    func testNewWorkbenchRequestCancelsPreviousServiceTask() async {
        let service = CancellationAwareAssistantService()
        let vm = AIBriefingViewModel(
            service: service,
            cache: MemoryBriefCache(),
            attemptTracker: MemoryBriefAttemptTracker()
        )

        let first = Task { await vm.runWorkbench(items: [], health: 50, now: now) }
        await service.waitForWorkbenchCalls(1)
        let second = Task {
            await vm.runWorkbench(items: [], health: 50, now: now.addingTimeInterval(60))
        }
        await service.waitForWorkbenchCalls(2)
        await yieldUntil { service.workbenchCancellations == 1 }

        XCTAssertEqual(service.workbenchCancellations, 1)
        first.cancel()
        second.cancel()
        await first.value
        await second.value
    }

    func testNewBriefRefreshCancelsPreviousServiceTask() async {
        let service = CancellationAwareAssistantService()
        let vm = AIBriefingViewModel(
            service: service,
            cache: MemoryBriefCache(),
            attemptTracker: MemoryBriefAttemptTracker()
        )

        let first = Task { await vm.refresh(items: [], health: 50, now: now) }
        await service.waitForDailyBriefCalls(1)
        let second = Task {
            await vm.refresh(items: [], health: 50, now: now.addingTimeInterval(60))
        }
        await service.waitForDailyBriefCalls(2)
        await yieldUntil { service.dailyBriefCancellations == 1 }

        XCTAssertEqual(service.dailyBriefCancellations, 1)
        first.cancel()
        second.cancel()
        await first.value
        await second.value
    }

    func testCancelledWorkbenchCallerDoesNotPublishFailure() async {
        let service = CancellationAwareAssistantService()
        let vm = AIBriefingViewModel(
            service: service,
            cache: MemoryBriefCache(),
            attemptTracker: MemoryBriefAttemptTracker()
        )

        let request = Task { await vm.runWorkbench(items: [], health: 50, now: now) }
        await service.waitForWorkbenchCalls(1)
        request.cancel()
        await request.value

        XCTAssertEqual(service.workbenchCancellations, 1)
        XCTAssertEqual(vm.workbenchState, .idle)
    }

    func testCancelledBriefCallerDoesNotPublishFailure() async {
        let service = CancellationAwareAssistantService()
        let vm = AIBriefingViewModel(
            service: service,
            cache: MemoryBriefCache(),
            attemptTracker: MemoryBriefAttemptTracker()
        )

        let request = Task { await vm.refresh(items: [], health: 50, now: now) }
        await service.waitForDailyBriefCalls(1)
        request.cancel()
        await request.value

        XCTAssertEqual(service.dailyBriefCancellations, 1)
        XCTAssertEqual(vm.briefState, .idle)
    }

    func testSegmentedModeChangePreservesGoalButExplicitOpenPrefillReplacesIt() {
        let vm = AIBriefingViewModel(
            service: ImmediateAssistantService(),
            cache: MemoryBriefCache(),
            attemptTracker: MemoryBriefAttemptTracker()
        )
        vm.goal = "用户正在编辑的目标"

        vm.mode = .breakdown
        XCTAssertEqual(vm.goal, "用户正在编辑的目标")

        vm.open(mode: .review, prefill: "复盘今天的阻塞")
        XCTAssertEqual(vm.mode, .review)
        XCTAssertEqual(vm.goal, "复盘今天的阻塞")

        vm.open(mode: .todayPlan)
        XCTAssertEqual(vm.goal, "复盘今天的阻塞")
    }

    func testEditedGoalKeepsSessionProvenanceStaleAcrossPresentationReconstruction() async {
        let context = AIAssistantContext(tasks: [], health: 50)
        let task = suggestedTask(
            id: "00000000-0000-0000-0000-000000000041",
            title: "发布 1.0"
        )
        let service = ImmediateAssistantService()
        service.workbenchResult = AIWorkbenchResult(
            overview: "旧建议",
            suggestedTasks: [task],
            sections: [],
            source: .managed
        )
        let vm = AIBriefingViewModel(
            service: service,
            cache: MemoryBriefCache(),
            attemptTracker: MemoryBriefAttemptTracker()
        )
        vm.goal = "发布 1.0"
        await vm.runWorkbench(items: [], health: 50, now: now)

        let fresh = AIWorkbenchSessionPresentation(
            state: vm.workbenchState,
            currentMode: vm.mode,
            currentGoal: vm.goal,
            currentContextFingerprint: context.fingerprint
        )
        XCTAssertTrue(fresh.isFresh)
        XCTAssertEqual(
            vm.selectedTasksForImport(existingTitles: [], currentContext: context).map(\.id),
            [task.id]
        )

        vm.goal = "发布 2.0"
        let rebuiltPresentation = AIWorkbenchSessionPresentation(
            state: vm.workbenchState,
            currentMode: vm.mode,
            currentGoal: vm.goal,
            currentContextFingerprint: context.fingerprint
        )

        XCTAssertEqual(rebuiltPresentation.session?.result.overview, "旧建议")
        XCTAssertFalse(rebuiltPresentation.isFresh)
        XCTAssertTrue(rebuiltPresentation.showsStaleResult)
        XCTAssertTrue(
            vm.selectedTasksForImport(existingTitles: [], currentContext: context).isEmpty
        )
        XCTAssertFalse(
            AIWorkbenchSessionPresentation(
                state: vm.workbenchState,
                currentMode: vm.mode,
                currentGoal: vm.goal,
                currentContextFingerprint: context.fingerprint
            ).isFresh
        )
    }

    func testSelectedTaskMetadataChangeMakesResultAndImportsStale() async throws {
        let suggestion = suggestedTask(
            id: "00000000-0000-0000-0000-000000000081",
            title: "提交审核"
        )
        let service = ImmediateAssistantService()
        service.workbenchResult = AIWorkbenchResult(
            overview: "拆解结果",
            suggestedTasks: [suggestion],
            sections: [],
            source: .managed
        )
        let vm = makeViewModel(service: service)
        vm.mode = .breakdown
        let item = activeItem(title: "发布 1.0", acceptanceCriteria: "TestFlight 通过")
        vm.selectGoalTask(item)
        await vm.runWorkbench(items: [item], health: 50, now: now)

        item.acceptanceCriteria = "App Store 审核通过"
        let context = AIAssistantContext(items: [item], health: 50)
        let currentSelected = try XCTUnwrap(vm.selectedGoalContext(in: [item]))
        let presentation = AIWorkbenchSessionPresentation(
            state: vm.workbenchState,
            currentMode: vm.mode,
            currentGoal: vm.goal,
            currentContextFingerprint: context.fingerprint,
            currentSelectedGoalFingerprint: currentSelected.fingerprint
        )

        XCTAssertFalse(presentation.isFresh)
        XCTAssertTrue(
            vm.selectedTasksForImport(
                existingTitles: [],
                currentContext: context,
                currentSelectedGoalFingerprint: currentSelected.fingerprint
            ).isEmpty
        )
        XCTAssertEqual(
            vm.selectedTasksForApplication(
                existingItems: [item],
                currentContext: context,
                currentSelectedGoalFingerprint: currentSelected.fingerprint
            ),
            AIWorkbenchApplication(existingTaskIDs: [], newTasks: [])
        )
    }

    func testRerunQuotaFailureRetainsPreviousSessionAndRecovery() async {
        let context = AIAssistantContext(tasks: [], health: 50)
        let service = ControlledAssistantService()
        let vm = AIBriefingViewModel(
            service: service,
            cache: MemoryBriefCache(),
            attemptTracker: MemoryBriefAttemptTracker()
        )
        vm.goal = "今天先发布"

        let first = Task { await vm.runWorkbench(items: [], health: 50, now: now) }
        await service.waitForWorkbenchCalls(1)
        service.completeNextWorkbench()
        await first.value
        guard case .result(let completedSession) = vm.workbenchState else {
            return XCTFail("Expected initial workbench session")
        }

        let rerun = Task {
            await vm.runWorkbench(items: [], health: 50, now: now.addingTimeInterval(60))
        }
        await service.waitForWorkbenchCalls(2)
        XCTAssertEqual(vm.workbenchState, .loading(previous: completedSession))

        service.failNextWorkbench(QuotaError.quotaExceeded(kind: "daily"))
        await rerun.value

        guard case .failed(let retained, let failure) = vm.workbenchState else {
            return XCTFail("Expected failed workbench with retained session")
        }
        XCTAssertEqual(retained, completedSession)
        XCTAssertEqual(failure.kind, .quotaExceeded(kind: "daily"))
        XCTAssertEqual(failure.recovery, [.manageSubscription, .configureProvider])

        let presentation = AIWorkbenchSessionPresentation(
            state: vm.workbenchState,
            currentMode: vm.mode,
            currentGoal: vm.goal,
            currentContextFingerprint: context.fingerprint
        )
        XCTAssertEqual(presentation.session, completedSession)
        XCTAssertTrue(presentation.isFresh)
        XCTAssertTrue(presentation.showsRetainedResult)
        XCTAssertEqual(presentation.failure, failure)
    }

    func testSuccessfulRerunReplacesPreviousSession() async {
        let service = ImmediateAssistantService()
        service.workbenchResult = AIWorkbenchResult(
            overview: "第一版",
            suggestedTasks: [],
            sections: [],
            source: .managed
        )
        let vm = AIBriefingViewModel(
            service: service,
            cache: MemoryBriefCache(),
            attemptTracker: MemoryBriefAttemptTracker()
        )
        vm.goal = "发布版本"
        await vm.runWorkbench(items: [], health: 50, now: now)
        guard case .result(let firstSession) = vm.workbenchState else {
            return XCTFail("Expected first workbench session")
        }

        service.workbenchResult = AIWorkbenchResult(
            overview: "第二版",
            suggestedTasks: [],
            sections: [],
            source: .custom
        )
        await vm.runWorkbench(items: [], health: 50, now: now.addingTimeInterval(60))

        guard case .result(let replacement) = vm.workbenchState else {
            return XCTFail("Expected replacement workbench session")
        }
        XCTAssertNotEqual(replacement, firstSession)
        XCTAssertEqual(replacement.result.overview, "第二版")
        XCTAssertEqual(replacement.provenance.mode, .todayPlan)
        XCTAssertEqual(replacement.provenance.goal, "发布版本")
        XCTAssertEqual(
            replacement.provenance.contextFingerprint,
            AIAssistantContext(tasks: [], health: 50).fingerprint
        )
    }

    func testSelectedTasksNormalizeTitlesAndDeduplicateAgainstResultsAndExistingTasks() async {
        let duplicateExisting = suggestedTask(
            id: "00000000-0000-0000-0000-000000000011",
            title: "  Launch   Plan "
        )
        let duplicateResult = suggestedTask(
            id: "00000000-0000-0000-0000-000000000012",
            title: "launch\nplan"
        )
        let importable = suggestedTask(
            id: "00000000-0000-0000-0000-000000000013",
            title: "  NEW\t Task  ",
            minutes: 40,
            priority: 5,
            dueDate: now.addingTimeInterval(3_600)
        )
        let blank = suggestedTask(
            id: "00000000-0000-0000-0000-000000000014",
            title: " \n\t "
        )
        let service = ImmediateAssistantService()
        service.workbenchResult = AIWorkbenchResult(
            overview: "建议",
            suggestedTasks: [duplicateExisting, duplicateResult, importable, blank],
            sections: [],
            source: .local
        )
        let vm = AIBriefingViewModel(
            service: service,
            cache: MemoryBriefCache(),
            attemptTracker: MemoryBriefAttemptTracker()
        )

        await vm.runWorkbench(items: [], health: 50, now: now)
        let context = AIAssistantContext(tasks: [], health: 50)
        let selected = vm.selectedTasksForImport(
            existingTitles: [" launch PLAN "],
            currentContext: context
        )

        XCTAssertEqual(selected.map(\.title), ["NEW Task"])
        XCTAssertEqual(selected.first?.estimatedMinutes, 40)
        XCTAssertEqual(selected.first?.priority, 5)
        XCTAssertEqual(selected.first?.dueDate, importable.dueDate)
        XCTAssertEqual(
            vm.selectedImportCount(existingTitles: [" launch PLAN "], currentContext: context),
            1
        )
    }

    func testSelectedTasksDeduplicateEquivalentTitlesInsideResult() async {
        let first = suggestedTask(
            id: "00000000-0000-0000-0000-000000000021",
            title: "Ship   Release"
        )
        let second = suggestedTask(
            id: "00000000-0000-0000-0000-000000000022",
            title: " ship release "
        )
        let service = ImmediateAssistantService()
        service.workbenchResult = AIWorkbenchResult(
            overview: "建议",
            suggestedTasks: [first, second],
            sections: [],
            source: .local
        )
        let vm = AIBriefingViewModel(
            service: service,
            cache: MemoryBriefCache(),
            attemptTracker: MemoryBriefAttemptTracker()
        )

        await vm.runWorkbench(items: [], health: 50, now: now)

        let context = AIAssistantContext(tasks: [], health: 50)
        XCTAssertEqual(
            vm.selectedTasksForImport(existingTitles: [], currentContext: context).map(\.id),
            [first.id]
        )
        XCTAssertEqual(vm.selectedImportCount(existingTitles: [], currentContext: context), 1)
    }

    func testLocalTodayPlanProducesNonzeroApplicationForExistingTaskWithoutImport() async {
        let existing = TodoItem(title: "发布版本", priority: 5)
        let service = ImmediateAssistantService()
        service.workbenchResult = LocalAIAssistantPlanner.workbench(
            mode: .todayPlan,
            goal: "",
            context: AIAssistantContext(items: [existing], health: 50),
            now: now
        )
        let vm = AIBriefingViewModel(
            service: service,
            cache: MemoryBriefCache(),
            attemptTracker: MemoryBriefAttemptTracker()
        )

        await vm.runWorkbench(items: [existing], health: 50, now: now)
        let application = vm.selectedTasksForApplication(
            existingItems: [existing],
            currentContext: AIAssistantContext(items: [existing], health: 50)
        )

        XCTAssertEqual(application.existingTaskIDs, [existing.id])
        XCTAssertTrue(application.newTasks.isEmpty)
        XCTAssertEqual(application.count, 1)
    }

    func testRemoteNewTodayPlanSuggestionRemainsImportable() async {
        let existing = TodoItem(title: "已有任务", priority: 5)
        let suggestion = suggestedTask(
            id: "00000000-0000-0000-0000-000000000071",
            title: "远端新建议",
            minutes: 25,
            priority: 4
        )
        let service = ImmediateAssistantService()
        service.workbenchResult = AIWorkbenchResult(
            overview: "建议",
            suggestedTasks: [suggestion],
            sections: [],
            source: .managed
        )
        let vm = AIBriefingViewModel(
            service: service,
            cache: MemoryBriefCache(),
            attemptTracker: MemoryBriefAttemptTracker()
        )

        await vm.runWorkbench(items: [existing], health: 50, now: now)
        let application = vm.selectedTasksForApplication(
            existingItems: [existing],
            currentContext: AIAssistantContext(items: [existing], health: 50)
        )

        XCTAssertTrue(application.existingTaskIDs.isEmpty)
        XCTAssertEqual(application.newTasks.map(\.id), [suggestion.id])
        XCTAssertEqual(application.count, 1)
    }

    func testWorkbenchQuotaFailureRetainsQuotaKindAndRecovery() async {
        let service = ImmediateAssistantService()
        service.workbenchError = QuotaError.quotaExceeded(kind: "daily")
        let vm = AIBriefingViewModel(
            service: service,
            cache: MemoryBriefCache(),
            attemptTracker: MemoryBriefAttemptTracker()
        )

        await vm.runWorkbench(items: [], health: 50, now: now)

        guard case .failed(previous: nil, failure: let failure) = vm.workbenchState else {
            return XCTFail("Expected workbench failure")
        }
        XCTAssertEqual(failure.kind, .quotaExceeded(kind: "daily"))
        XCTAssertEqual(failure.recovery, [.manageSubscription, .configureProvider])
    }

    func testStatesAndRequestSnapshotsAreSendable() {
        requireSendable(AIAssistantFailure.self)
        requireSendable(AIBriefState.self)
        requireSendable(AIWorkbenchState.self)
        requireSendable(AIWorkbenchProvenance.self)
        requireSendable(AIWorkbenchSession.self)
        requireSendable(AIBriefRequest.self)
        requireSendable(AIWorkbenchRequest.self)
        requireSendable(AIWorkbenchApplication.self)
    }

    private func makeBrief(summary: String, fingerprint: String) -> AIDailyBrief {
        AIDailyBrief(
            content: .init(summary: summary, detail: "详情", evidence: ["依据"]),
            generatedAt: now,
            source: .managed,
            contextFingerprint: fingerprint
        )
    }

    private func suggestedTask(
        id: String,
        title: String,
        minutes: Int? = nil,
        priority: Int? = nil,
        dueDate: Date? = nil
    ) -> AISuggestedTask {
        AISuggestedTask(
            id: UUID(uuidString: id)!,
            title: title,
            rationale: "原因",
            estimatedMinutes: minutes,
            priority: priority,
            dueDate: dueDate
        )
    }

    private func requireSendable<T: Sendable>(_: T.Type) {}

    private func makeViewModel(
        service: any AIAssistantServing = ImmediateAssistantService()
    ) -> AIBriefingViewModel {
        AIBriefingViewModel(
            service: service,
            cache: MemoryBriefCache(),
            attemptTracker: MemoryBriefAttemptTracker()
        )
    }

    private func activeItem(
        title: String,
        acceptanceCriteria: String = ""
    ) -> TodoItem {
        TodoItem(title: title, acceptanceCriteria: acceptanceCriteria)
    }

    private func yieldUntil(_ predicate: () -> Bool) async {
        for _ in 0..<50 where !predicate() {
            await Task.yield()
        }
    }
}

@MainActor
private final class ImmediateAssistantService: AIAssistantServing {
    private(set) var dailyBriefCalls: [(AIAssistantContext, Date)] = []
    private(set) var workbenchCalls: [(AIWorkbenchMode, String, AIAssistantContext, Date)] = []
    private(set) var workbenchSelectedGoals: [AISelectedGoalContext?] = []
    private(set) var dailyBriefIntents: [RemoteAIRequestIntent] = []
    var dailyBriefError: Error?
    var workbenchError: Error?
    var dailyBriefContent = AIDailyBriefContent(
        summary: "先发布",
        detail: "保护截止任务",
        evidence: ["1 个截止"]
    )
    var workbenchResult = AIWorkbenchResult(
        overview: "建议",
        suggestedTasks: [],
        sections: [],
        source: .managed
    )

    func dailyBrief(
        context: AIAssistantContext,
        now: Date,
        intent: RemoteAIRequestIntent
    ) async throws -> (AIDailyBriefContent, AIAssistantSource) {
        dailyBriefCalls.append((context, now))
        dailyBriefIntents.append(intent)
        if let dailyBriefError { throw dailyBriefError }
        return (dailyBriefContent, .managed)
    }

    func workbench(
        mode: AIWorkbenchMode,
        goal: String,
        selectedGoal: AISelectedGoalContext?,
        context: AIAssistantContext,
        now: Date,
        intent: RemoteAIRequestIntent
    ) async throws -> AIWorkbenchResult {
        workbenchCalls.append((mode, goal, context, now))
        workbenchSelectedGoals.append(selectedGoal)
        if let workbenchError { throw workbenchError }
        return workbenchResult
    }
}

@MainActor
private final class ControlledAssistantService: AIAssistantServing {
    private(set) var dailyBriefCalls: [(AIAssistantContext, Date)] = []
    private(set) var workbenchCalls: [(AIWorkbenchMode, String, AIAssistantContext, Date)] = []

    private var pendingDailyBriefs: [CheckedContinuation<(AIDailyBriefContent, AIAssistantSource), Error>] = []
    private var pendingWorkbenches: [CheckedContinuation<AIWorkbenchResult, Error>] = []
    private var dailyCallWaiters: [(Int, CheckedContinuation<Void, Never>)] = []
    private var workbenchCallWaiters: [(Int, CheckedContinuation<Void, Never>)] = []

    func dailyBrief(
        context: AIAssistantContext,
        now: Date,
        intent: RemoteAIRequestIntent
    ) async throws -> (AIDailyBriefContent, AIAssistantSource) {
        dailyBriefCalls.append((context, now))
        resumeSatisfiedDailyCallWaiters()
        return try await withCheckedThrowingContinuation { continuation in
            pendingDailyBriefs.append(continuation)
        }
    }

    func workbench(
        mode: AIWorkbenchMode,
        goal: String,
        selectedGoal: AISelectedGoalContext?,
        context: AIAssistantContext,
        now: Date,
        intent: RemoteAIRequestIntent
    ) async throws -> AIWorkbenchResult {
        workbenchCalls.append((mode, goal, context, now))
        resumeSatisfiedWorkbenchCallWaiters()
        return try await withCheckedThrowingContinuation { continuation in
            pendingWorkbenches.append(continuation)
        }
    }

    func waitForDailyBriefCalls(_ count: Int) async {
        guard dailyBriefCalls.count < count else { return }
        await withCheckedContinuation { continuation in
            dailyCallWaiters.append((count, continuation))
        }
    }

    func waitForWorkbenchCalls(_ count: Int) async {
        guard workbenchCalls.count < count else { return }
        await withCheckedContinuation { continuation in
            workbenchCallWaiters.append((count, continuation))
        }
    }

    func completeNextDailyBrief() {
        pendingDailyBriefs.removeFirst().resume(
            returning: (
                AIDailyBriefContent(
                    summary: "先发布",
                    detail: "保护截止任务",
                    evidence: ["1 个截止"]
                ),
                .managed
            )
        )
    }

    func completeNextWorkbench() {
        pendingWorkbenches.removeFirst().resume(
            returning: AIWorkbenchResult(
                overview: "建议",
                suggestedTasks: [
                    AISuggestedTask(
                        id: UUID(uuidString: "00000000-0000-0000-0000-000000000031")!,
                        title: "执行下一步",
                        rationale: "保持推进",
                        estimatedMinutes: 20,
                        priority: 4,
                        dueDate: nil
                    )
                ],
                sections: [],
                source: .managed
            )
        )
    }

    func failNextWorkbench(_ error: Error) {
        pendingWorkbenches.removeFirst().resume(throwing: error)
    }

    private func resumeSatisfiedDailyCallWaiters() {
        let satisfied = dailyCallWaiters.filter { $0.0 <= dailyBriefCalls.count }
        dailyCallWaiters.removeAll { $0.0 <= dailyBriefCalls.count }
        satisfied.forEach { $0.1.resume() }
    }

    private func resumeSatisfiedWorkbenchCallWaiters() {
        let satisfied = workbenchCallWaiters.filter { $0.0 <= workbenchCalls.count }
        workbenchCallWaiters.removeAll { $0.0 <= workbenchCalls.count }
        satisfied.forEach { $0.1.resume() }
    }
}

@MainActor
private final class CancellationAwareAssistantService: AIAssistantServing {
    private(set) var dailyBriefCalls = 0
    private(set) var workbenchCalls = 0
    private(set) var dailyBriefCancellations = 0
    private(set) var workbenchCancellations = 0

    private var dailyCallWaiters: [(Int, CheckedContinuation<Void, Never>)] = []
    private var workbenchCallWaiters: [(Int, CheckedContinuation<Void, Never>)] = []

    func dailyBrief(
        context: AIAssistantContext,
        now: Date,
        intent: RemoteAIRequestIntent
    ) async throws -> (AIDailyBriefContent, AIAssistantSource) {
        dailyBriefCalls += 1
        resumeSatisfiedDailyCallWaiters()
        do {
            try await Task.sleep(for: .seconds(3_600))
        } catch is CancellationError {
            dailyBriefCancellations += 1
            throw CancellationError()
        }
        return (.init(summary: "简报", detail: "详情", evidence: ["依据"]), .managed)
    }

    func workbench(
        mode: AIWorkbenchMode,
        goal: String,
        selectedGoal: AISelectedGoalContext?,
        context: AIAssistantContext,
        now: Date,
        intent: RemoteAIRequestIntent
    ) async throws -> AIWorkbenchResult {
        workbenchCalls += 1
        resumeSatisfiedWorkbenchCallWaiters()
        do {
            try await Task.sleep(for: .seconds(3_600))
        } catch is CancellationError {
            workbenchCancellations += 1
            throw CancellationError()
        }
        return AIWorkbenchResult(
            overview: "建议",
            suggestedTasks: [],
            sections: [],
            source: .managed
        )
    }

    func waitForDailyBriefCalls(_ count: Int) async {
        guard dailyBriefCalls < count else { return }
        await withCheckedContinuation { continuation in
            dailyCallWaiters.append((count, continuation))
        }
    }

    func waitForWorkbenchCalls(_ count: Int) async {
        guard workbenchCalls < count else { return }
        await withCheckedContinuation { continuation in
            workbenchCallWaiters.append((count, continuation))
        }
    }

    private func resumeSatisfiedDailyCallWaiters() {
        let satisfied = dailyCallWaiters.filter { $0.0 <= dailyBriefCalls }
        dailyCallWaiters.removeAll { $0.0 <= dailyBriefCalls }
        satisfied.forEach { $0.1.resume() }
    }

    private func resumeSatisfiedWorkbenchCallWaiters() {
        let satisfied = workbenchCallWaiters.filter { $0.0 <= workbenchCalls }
        workbenchCallWaiters.removeAll { $0.0 <= workbenchCalls }
        satisfied.forEach { $0.1.resume() }
    }
}

@MainActor
private final class MemoryBriefCache: AIBriefCaching {
    private var values: [String: AIDailyBrief] = [:]

    func load(for dayKey: String) -> AIDailyBrief? {
        values[dayKey]
    }

    func loadMostRecent() -> AIDailyBrief? {
        values.sorted { $0.key > $1.key }.first?.value
    }

    func save(_ brief: AIDailyBrief, for dayKey: String) {
        values[dayKey] = brief
    }
}

@MainActor
private final class MemoryBriefAttemptTracker: AIBriefAutoAttemptTracking {
    private var attemptedDays: Set<String> = []

    func hasAttemptedAutomaticGeneration(for dayKey: String) -> Bool {
        attemptedDays.contains(dayKey)
    }

    func markAutomaticGenerationAttempted(for dayKey: String) {
        attemptedDays.insert(dayKey)
    }
}
