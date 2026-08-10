import XCTest

@testable import TodoNative

final class ProjectConfigurationTests: XCTestCase {
    func testProjectDoesNotForceLightAppearance() throws {
        XCTAssertNil(
            Bundle.main.object(forInfoDictionaryKey: "UIUserInterfaceStyle"),
            "Omitting UIUserInterfaceStyle lets the app follow the system Light/Dark appearance."
        )
    }
}
