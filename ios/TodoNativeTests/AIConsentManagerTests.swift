import XCTest
@testable import TodoNative

@MainActor
final class AIConsentManagerTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName = ""
    private let storageKey = "ai_remote_consent.test"
    private let managedRoute = AIConsentRoute(
        identifier: "managed:worker.example:deepseek",
        recipientName: "Managed AI service and DeepSeek"
    )
    private let openAIRoute = AIConsentRoute(
        identifier: "byok:openai",
        recipientName: "OpenAI"
    )

    override func setUp() {
        super.setUp()
        suiteName = "AIConsentManagerTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = ""
        super.tearDown()
    }

    func testFirstUseNeedsConsent() {
        let manager = makeManager(version: "1")

        XCTAssertEqual(manager.decision(for: managedRoute), .needsConsent)
    }

    func testAcceptedCurrentVersionAndRouteIsAllowed() {
        let manager = makeManager(version: "1")
        manager.accept(managedRoute, at: Date(timeIntervalSince1970: 100))

        XCTAssertEqual(manager.decision(for: managedRoute), .allowed)
    }

    func testDeclinedRouteRemainsLocalForCurrentSession() {
        let manager = makeManager(version: "1")
        manager.decline(managedRoute)

        XCTAssertEqual(manager.decision(for: managedRoute), .declined)
        XCTAssertNil(defaults.object(forKey: storageKey))
    }

    func testRevokingAcceptedConsentRequiresConsentAgain() {
        let manager = makeManager(version: "1")
        manager.accept(managedRoute, at: Date(timeIntervalSince1970: 100))

        manager.revoke()

        XCTAssertEqual(manager.decision(for: managedRoute), .needsConsent)
        XCTAssertNil(defaults.object(forKey: storageKey))
    }

    func testConsentVersionChangeRequiresRenewedConsent() {
        let versionOne = makeManager(version: "1")
        versionOne.accept(managedRoute, at: Date(timeIntervalSince1970: 100))

        let versionTwo = makeManager(version: "2")

        XCTAssertEqual(versionTwo.decision(for: managedRoute), .needsConsent)
    }

    func testManagedToBYOKProviderChangeRequiresRenewedConsent() {
        let manager = makeManager(version: "1")
        manager.accept(managedRoute, at: Date(timeIntervalSince1970: 100))

        XCTAssertEqual(manager.decision(for: openAIRoute), .needsConsent)
    }

    func testPersistedConsentContainsOnlyVersionRouteAndTimestamp() throws {
        let manager = makeManager(version: "1")
        manager.accept(managedRoute, at: Date(timeIntervalSince1970: 100))

        let data = try XCTUnwrap(defaults.data(forKey: storageKey))
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )

        XCTAssertEqual(Set(object.keys), ["version", "routeIdentifier", "timestamp"])
        XCTAssertEqual(object["version"] as? String, "1")
        XCTAssertEqual(object["routeIdentifier"] as? String, managedRoute.identifier)
    }

    func testGateDoesNotInvokeRemoteTransportBeforeConsent() async {
        let manager = makeManager(version: "1")
        let gate = RemoteAIGate(consentManager: manager)
        var transportCallCount = 0

        do {
            _ = try await gate.perform(for: managedRoute) {
                transportCallCount += 1
                return "remote"
            }
            XCTFail("Expected consent requirement")
        } catch RemoteAIConsentError.needsConsent(let route) {
            XCTAssertEqual(route, managedRoute)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertEqual(transportCallCount, 0)
    }

    func testGateInvokesRemoteTransportOnlyAfterCurrentRouteApproval() async throws {
        let manager = makeManager(version: "1")
        let gate = RemoteAIGate(consentManager: manager)
        manager.accept(managedRoute, at: Date(timeIntervalSince1970: 100))
        var transportCallCount = 0

        let value = try await gate.perform(for: managedRoute) {
            transportCallCount += 1
            return "remote"
        }

        XCTAssertEqual(value, "remote")
        XCTAssertEqual(transportCallCount, 1)
    }

    func testProviderChangeBlocksTransportUntilRenewedConsent() async throws {
        let manager = makeManager(version: "1")
        let gate = RemoteAIGate(consentManager: manager)
        manager.accept(managedRoute, at: Date(timeIntervalSince1970: 100))
        var transportCallCount = 0

        do {
            _ = try await gate.perform(for: openAIRoute) {
                transportCallCount += 1
                return "remote"
            }
            XCTFail("Expected renewed consent")
        } catch RemoteAIConsentError.needsConsent(let route) {
            XCTAssertEqual(route, openAIRoute)
        }
        XCTAssertEqual(transportCallCount, 0)

        manager.accept(openAIRoute, at: Date(timeIntervalSince1970: 200))
        _ = try await gate.perform(for: openAIRoute) {
            transportCallCount += 1
            return "remote"
        }
        XCTAssertEqual(transportCallCount, 1)
    }

    func testPresentedConsentPublishesAcceptedResolutionAndClearsRoute() {
        let manager = makeManager(version: "1")
        manager.requestConsent(for: managedRoute)

        XCTAssertEqual(manager.pendingRoute, managedRoute)

        manager.acceptPendingConsent(at: Date(timeIntervalSince1970: 100))

        XCTAssertNil(manager.pendingRoute)
        XCTAssertEqual(manager.resolution?.route, managedRoute)
        XCTAssertEqual(manager.resolution?.outcome, .accepted)
        XCTAssertEqual(manager.decision(for: managedRoute), .allowed)
    }

    func testPresentedDeclinePublishesDeclinedResolution() {
        let manager = makeManager(version: "1")
        manager.requestConsent(for: managedRoute)

        manager.declinePendingConsent()

        XCTAssertNil(manager.pendingRoute)
        XCTAssertEqual(manager.resolution?.route, managedRoute)
        XCTAssertEqual(manager.resolution?.outcome, .declined)
        XCTAssertEqual(manager.decision(for: managedRoute), .declined)
    }

    private func makeManager(version: String) -> AIConsentManager {
        AIConsentManager(
            consentVersion: version,
            storage: defaults,
            storageKey: storageKey
        )
    }
}
