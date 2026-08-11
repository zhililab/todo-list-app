import XCTest
@testable import TodoNative

@MainActor
final class PurchaseManagerTests: XCTestCase {
    private final class AvailabilityBox {
        var value: ManagedAIAvailability = .unavailable(.missingEndpoint)
    }

    private func makeTrialManager() -> TrialManager {
        TrialManager(defaults: UserDefaults(suiteName: "test.purchase.\(UUID().uuidString)")!)
    }

    func testUnavailableManagedRegistrationDoesNotOverwriteApplePurchaseStatus() async {
        let manager = PurchaseManager(
            trialManager: makeTrialManager(),
            registrationAvailability: { .unavailable(.missingEndpoint) },
            registerPro: { _ in XCTFail("Registration must not run without a managed endpoint") }
        )
        manager.errorMessage = "Apple purchase status"

        await manager.registerVerifiedTransaction(jwsRepresentation: "signed-transaction")

        XCTAssertEqual(manager.errorMessage, "Apple purchase status")
        XCTAssertEqual(manager.registrationStatus, .unavailable(.missingEndpoint))
    }

    func testRegistrationRetriesWhenManagedEndpointBecomesAvailable() async {
        let availability = AvailabilityBox()
        var registeredTransactions: [String] = []
        let manager = PurchaseManager(
            trialManager: makeTrialManager(),
            registrationAvailability: { availability.value },
            registerPro: { registeredTransactions.append($0) }
        )

        await manager.registerVerifiedTransaction(jwsRepresentation: "signed-transaction")
        availability.value = .available(URL(string: "https://quota.test")!)
        await manager.registerVerifiedTransaction(jwsRepresentation: "signed-transaction")

        XCTAssertEqual(registeredTransactions, ["signed-transaction"])
        XCTAssertEqual(manager.registrationStatus, .registered)
    }

    func testRegistrationFailureIsSeparateAndRetryable() async {
        var attempts = 0
        let manager = PurchaseManager(
            trialManager: makeTrialManager(),
            registrationAvailability: { .available(URL(string: "https://quota.test")!) },
            registerPro: { _ in
                attempts += 1
                if attempts == 1 { throw URLError(.cannotConnectToHost) }
            }
        )
        manager.hasPremium = true

        await manager.registerVerifiedTransaction(jwsRepresentation: "signed-transaction")
        XCTAssertEqual(manager.registrationStatus, .failed)
        XCTAssertTrue(manager.hasPremium, "Managed registration failure must not revoke the Apple entitlement")

        await manager.registerVerifiedTransaction(jwsRepresentation: "signed-transaction")
        XCTAssertEqual(attempts, 2)
        XCTAssertEqual(manager.registrationStatus, .registered)
    }

    func testOnlyApprovedProductIDsAreProcessedFromTransactionUpdates() {
        XCTAssertTrue(PurchaseManager.shouldProcessTransaction(
            productID: "com.zhili.todo.premium.monthly"
        ))
        XCTAssertTrue(PurchaseManager.shouldProcessTransaction(
            productID: "com.zhili.todo.premium.yearly"
        ))
        XCTAssertFalse(PurchaseManager.shouldProcessTransaction(productID: "unrelated.product"))
    }
}
