import XCTest
@testable import TodoNative

@MainActor
final class DashboardPresentationTests: XCTestCase {
    func testAppOwnsOneBriefingViewModelAndDashboardConsumesItFromEnvironment() {
        let appStorage = Mirror(reflecting: TodoNativeApp()).children
            .map { (label: $0.label, type: String(reflecting: type(of: $0.value))) }
        let briefingOwners = appStorage.filter {
            $0.type.contains("StateObject") && $0.type.contains("AIBriefingViewModel")
        }

        XCTAssertEqual(briefingOwners.count, 1)

        let dashboardBriefingStorage = Mirror(reflecting: DashboardView()).children
            .first { $0.label == "_briefing" }
            .map { String(reflecting: type(of: $0.value)) }

        XCTAssertTrue(dashboardBriefingStorage?.contains("EnvironmentObject") == true)
        XCTAssertFalse(dashboardBriefingStorage?.contains("StateObject") == true)
    }

    func testWorkbenchAndProviderSettingsDeclareCompleteSharedEnvironmentDependencies() {
        let workbenchStorage = propertyWrapperTypeNames(in: AIWorkbenchView())
        let workbenchEnvironment = workbenchStorage.filter { $0.contains("EnvironmentObject") }
        XCTAssertTrue(workbenchEnvironment.contains { $0.contains("TodoViewModel") })
        XCTAssertTrue(workbenchEnvironment.contains { $0.contains("AIViewModel") })
        XCTAssertTrue(workbenchEnvironment.contains { $0.contains("AIBriefingViewModel") })
        XCTAssertTrue(workbenchEnvironment.contains { $0.contains("LanguageEnvironment") })
        XCTAssertFalse(workbenchStorage.contains {
            $0.contains("StateObject") && $0.contains("AIBriefingViewModel")
        })

        let settingsEnvironment = propertyWrapperTypeNames(in: SettingsView())
            .filter { $0.contains("EnvironmentObject") }
        for dependency in [
            "TrialManager",
            "PurchaseManager",
            "TodoViewModel",
            "AIViewModel",
            "LanguageEnvironment",
            "NotificationService"
        ] {
            XCTAssertTrue(
                settingsEnvironment.contains { $0.contains(dependency) },
                "Settings is missing shared \(dependency)"
            )
        }
    }

    func testPremiumTakesPrecedenceOverTrial() {
        XCTAssertEqual(
            DashboardAccessStatus.resolve(hasPremium: true, trialState: .trial(remainingDays: 3)),
            .premium
        )
    }

    func testFreeStateDoesNotRenderZeroDayTrial() {
        XCTAssertEqual(
            DashboardAccessStatus.resolve(hasPremium: false, trialState: .free),
            .free
        )
    }

    func testActiveTrialPreservesRemainingDays() {
        XCTAssertEqual(
            DashboardAccessStatus.resolve(hasPremium: false, trialState: .trial(remainingDays: 3)),
            .trial(remainingDays: 3)
        )
    }

    func testBriefEntryRoutesToWorkbenchWithModeAndPrefill() {
        let route = DashboardAIRoute(mode: .review, prefill: "复盘今天")

        XCTAssertEqual(
            DashboardSheet.aiRoute(route: route),
            .aiWorkbench(route)
        )
    }

    func testLifecycleAlwaysLoadsWhileContextChangeOnlyMarksStale() {
        let automaticTriggers: [DashboardAIBriefTrigger] = [
            .firstTodayAppearance,
            .sceneBecameActive,
            .calendarDayChanged
        ]

        for trigger in automaticTriggers {
            XCTAssertEqual(
                DashboardAIBriefLifecycle.action(for: trigger),
                .loadIfNeeded
            )
        }
        XCTAssertEqual(
            DashboardAIBriefLifecycle.action(for: .contextChanged),
            .markStale
        )
    }

    func testActiveAndCalendarLifecycleRefreshLocalTodayPlan() {
        for trigger in [
            DashboardAIBriefTrigger.firstTodayAppearance,
            .sceneBecameActive,
            .calendarDayChanged
        ] {
            XCTAssertTrue(DashboardAIBriefLifecycle.refreshesTodayPlan(for: trigger))
        }
        XCTAssertFalse(DashboardAIBriefLifecycle.refreshesTodayPlan(for: .contextChanged))
    }

    func testFreeMembershipStillUsesTheSameAIBriefLifecycle() {
        XCTAssertEqual(
            DashboardAccessStatus.resolve(hasPremium: false, trialState: .free),
            .free
        )
        XCTAssertEqual(
            DashboardAIBriefLifecycle.action(for: .firstTodayAppearance),
            .loadIfNeeded
        )
    }

    func testQuickActionsMapToModeAndPrefill() {
        let plan = DashboardAIRoute.quickAction(.generatePlan)
        let prioritize = DashboardAIRoute.quickAction(.prioritize)
        let breakdown = DashboardAIRoute.quickAction(.breakdown)

        XCTAssertEqual(plan.mode, .todayPlan)
        XCTAssertEqual(plan.prefill, Localization.t("ai.brief.planPrefill"))
        XCTAssertEqual(prioritize.mode, .review)
        XCTAssertEqual(prioritize.prefill, Localization.t("ai.brief.prioritizePrefill"))
        XCTAssertEqual(breakdown.mode, .breakdown)
        XCTAssertEqual(breakdown.prefill, Localization.t("ai.brief.breakdownPrefill"))
    }

    func testQuotaRecoveryUsesTypedDashboardDestinations() {
        XCTAssertEqual(
            DashboardSheet.recoveryRoute(.manageSubscription),
            .paywall
        )
        XCTAssertEqual(
            DashboardSheet.recoveryRoute(.configureProvider),
            .aiSettings
        )
    }

    func testPremiumMembershipBadgeDoesNotOpenPaywall() {
        XCTAssertNil(DashboardSheet.membershipRoute(accessStatus: .premium))
    }

    func testFreeMembershipBadgeOpensPaywall() {
        XCTAssertEqual(DashboardSheet.membershipRoute(accessStatus: .free), .paywall)
    }

    func testRouteOpensImmediatelyWithoutPurchaseState() {
        let route = DashboardAIRoute(mode: .review, prefill: "复盘今天")

        XCTAssertEqual(
            DashboardSheet.aiRoute(route: route),
            .aiWorkbench(route)
        )
    }

    func testSharedMotionAndWorkbenchLayoutPoliciesRespectAccessibilitySettings() {
        XCTAssertNil(AppTheme.Motion.resolved(AppTheme.Motion.content, reduceMotion: true))
        XCTAssertNotNil(AppTheme.Motion.resolved(AppTheme.Motion.content, reduceMotion: false))
        XCTAssertEqual(
            AIWorkbenchTaskRowLayoutPresentation(isAccessibilitySize: true).axis,
            .vertical
        )
        XCTAssertEqual(
            AIWorkbenchTaskRowLayoutPresentation(isAccessibilitySize: false).axis,
            .horizontal
        )
    }

    private func propertyWrapperTypeNames(in value: Any) -> [String] {
        Mirror(reflecting: value).children.compactMap { child in
            guard child.label?.hasPrefix("_") == true else { return nil }
            return String(reflecting: type(of: child.value))
        }
    }
}
