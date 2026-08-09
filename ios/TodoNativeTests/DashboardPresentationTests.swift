import XCTest
@testable import TodoNative

final class DashboardPresentationTests: XCTestCase {
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

    func testAIPlanRoutesEligibleAccessToWorkbench() {
        XCTAssertEqual(DashboardSheet.aiRoute(canUseAIPlan: true), .aiPlan)
    }

    func testAIPlanRoutesFreeAccessToPaywall() {
        XCTAssertEqual(DashboardSheet.aiRoute(canUseAIPlan: false), .paywall)
    }

    func testPremiumMembershipBadgeDoesNotOpenPaywall() {
        XCTAssertNil(DashboardSheet.membershipRoute(accessStatus: .premium))
    }

    func testFreeMembershipBadgeOpensPaywall() {
        XCTAssertEqual(DashboardSheet.membershipRoute(accessStatus: .free), .paywall)
    }
}
