import XCTest
@testable import TodoNative

@MainActor
final class TrialManagerTests: XCTestCase {
    private let referenceDate = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeDefaults() -> UserDefaults {
        UserDefaults(suiteName: "test.trial.\(UUID().uuidString)")!
    }

    func testFirstLaunchStartsTrial() {
        let defaults = makeDefaults()
        let manager = TrialManager(defaults: defaults, now: { self.referenceDate })

        XCTAssertTrue(manager.isTrialActive)
        XCTAssertEqual(manager.remainingDays, 7)
        XCTAssertEqual(defaults.object(forKey: "todo_app_trial_start_date") as? Double, referenceDate.timeIntervalSince1970)
    }

    func testSevenDayTrialIsExplicitlyDeviceLocalExperience() {
        let defaults = makeDefaults()
        let manager = TrialManager(defaults: defaults, now: { self.referenceDate })

        XCTAssertTrue(manager.isTrialActive, "This is a device-local feature access window, not a StoreKit offer")
        XCTAssertEqual(manager.remainingDays, 7)
    }

    func testTrialExpiresAfterSevenDays() {
        let defaults = makeDefaults()
        defaults.set(referenceDate.timeIntervalSince1970 - 8 * 86400, forKey: "todo_app_trial_start_date")

        let manager = TrialManager(defaults: defaults, now: { self.referenceDate })
        XCTAssertFalse(manager.isTrialActive)
        XCTAssertEqual(manager.remainingDays, 0)
    }

    func testRemainingDaysDecreases() {
        let defaults = makeDefaults()
        defaults.set(referenceDate.timeIntervalSince1970 - 2 * 86400, forKey: "todo_app_trial_start_date")

        let manager = TrialManager(defaults: defaults, now: { self.referenceDate })
        XCTAssertTrue(manager.isTrialActive)
        XCTAssertEqual(manager.remainingDays, 5)
    }

    func testTrialStateIsFreeAfterExpiry() {
        let defaults = makeDefaults()
        defaults.set(referenceDate.timeIntervalSince1970 - 10 * 86400, forKey: "todo_app_trial_start_date")

        let manager = TrialManager(defaults: defaults, now: { self.referenceDate })
        if case .free = manager.trialState {
            XCTAssertTrue(true)
        } else {
            XCTFail("Expected free trial state, got \(manager.trialState)")
        }
    }

    func testReasoningReciprocalOfDayCalculation() {
        let defaults = makeDefaults()
        let start = referenceDate.timeIntervalSince1970
        defaults.set(start, forKey: "todo_app_trial_start_date")

        let dayAfter = referenceDate.addingTimeInterval(86400)
        let manager = TrialManager(defaults: defaults, now: { dayAfter })
        XCTAssertEqual(manager.remainingDays, 6)
    }
}
