import XCTest
@testable import TodoNative

final class SupportIdentifierTests: XCTestCase {
    func testSupportIDUsesExistingAnonymousDeviceIDWithoutCreatingAnotherIdentity() {
        let deviceID = "6B5EBC37-1D6D-4F10-8C41-E884C6C18A4B"

        XCTAssertEqual(
            SupportIdentifier.displayValue(for: deviceID),
            "TD-6B5EBC37-1D6D-4F10-8C41-E884C6C18A4B"
        )
        XCTAssertEqual(
            SupportIdentifier.deviceID(from: "TD-6B5EBC37-1D6D-4F10-8C41-E884C6C18A4B"),
            deviceID
        )
    }

    func testSupportIDRejectsMalformedValues() {
        XCTAssertNil(SupportIdentifier.deviceID(from: "TD-not-a-device-id"))
        XCTAssertNil(SupportIdentifier.deviceID(from: "6B5EBC37-1D6D-4F10-8C41-E884C6C18A4B"))
    }

    func testSupportIDPreservesLegacyLowercaseDeviceIDExactly() {
        let deviceID = "6b5ebc37-1d6d-4f10-8c41-e884c6c18a4b"
        let supportID = SupportIdentifier.displayValue(for: deviceID)

        XCTAssertEqual(supportID, "TD-\(deviceID)")
        XCTAssertEqual(SupportIdentifier.deviceID(from: supportID), deviceID)
    }
}
