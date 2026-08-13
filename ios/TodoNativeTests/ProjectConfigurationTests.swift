import XCTest

@testable import TodoNative

final class ProjectConfigurationTests: XCTestCase {
    private let privacyURL = URL(string: "https://todo-list-app.zhili1993.chatgpt.site/privacy.html")!
    private let termsURL = URL(string: "https://todo-list-app.zhili1993.chatgpt.site/terms.html")!
    private let supportURL = URL(string: "https://todo-list-app.zhili1993.chatgpt.site/support.html")!

    func testCompiledTargetUsesReplacementBuildNumber() {
        XCTAssertEqual(
            Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String,
            "4",
            "Build 3 was rejected by App Store Connect and must never be uploaded again."
        )
    }

    func testProjectDoesNotForceLightAppearance() throws {
        XCTAssertNil(
            Bundle.main.object(forInfoDictionaryKey: "UIUserInterfaceStyle"),
            "Omitting UIUserInterfaceStyle lets the app follow the system Light/Dark appearance."
        )
    }

    func testCompiledTargetDeclaresAllPhoneAndPadOrientations() throws {
        let infoURL = Bundle.main.bundleURL.appendingPathComponent("Info.plist")
        let data = try Data(contentsOf: infoURL)
        let info = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        )
        let expected = Set([
            "UIInterfaceOrientationPortrait",
            "UIInterfaceOrientationPortraitUpsideDown",
            "UIInterfaceOrientationLandscapeLeft",
            "UIInterfaceOrientationLandscapeRight"
        ])
        XCTAssertEqual(Set(try XCTUnwrap(
            info["UISupportedInterfaceOrientations"] as? [String]
        )), expected)

        let padOrientations = try XCTUnwrap(
            info["UISupportedInterfaceOrientations~ipad"] as? [String]
        )
        XCTAssertEqual(Set(padOrientations), expected)
    }

    func testReleaseConfigurationUsesCanonicalLegalURLsAndConsentVersion() {
        let configuration = AppConfiguration(infoDictionary: [:], buildMode: .release)

        XCTAssertEqual(configuration.privacyPolicyURL, privacyURL)
        XCTAssertEqual(configuration.termsOfUseURL, termsURL)
        XCTAssertEqual(configuration.supportURL, supportURL)
        XCTAssertNil(configuration.aiConsentVersion)

        XCTAssertEqual(Bundle.main.object(forInfoDictionaryKey: "PrivacyPolicyURL") as? String, privacyURL.absoluteString)
        XCTAssertEqual(Bundle.main.object(forInfoDictionaryKey: "TermsOfUseURL") as? String, termsURL.absoluteString)
        XCTAssertEqual(Bundle.main.object(forInfoDictionaryKey: "SupportURL") as? String, supportURL.absoluteString)
        XCTAssertEqual(Bundle.main.object(forInfoDictionaryKey: "AIConsentVersion") as? String, "1")
    }

    func testCompiledTargetUsesVerifiedManagedAIEndpoint() {
        XCTAssertEqual(
            Bundle.main.object(forInfoDictionaryKey: "ManagedAIBaseURL") as? String,
            "https://todo-quota-proxy.todo-quota-proxy.workers.dev"
        )
    }

    func testCompiledTargetDeclaresNoNonExemptEncryption() {
        XCTAssertEqual(
            Bundle.main.object(forInfoDictionaryKey: "ITSAppUsesNonExemptEncryption") as? Bool,
            false,
            "The app only relies on exempt encryption supplied by the operating system for HTTPS transport."
        )
    }

    func testReleaseConfigurationAcceptsOnlyHTTPSManagedEndpoints() {
        let available = AppConfiguration(
            infoDictionary: ["ManagedAIBaseURL": "https://quota.example/v1"],
            buildMode: .release
        )
        XCTAssertEqual(available.managedAIBaseURL, URL(string: "https://quota.example/v1"))
        XCTAssertEqual(
            available.managedAIAvailability,
            .available(URL(string: "https://quota.example/v1")!)
        )

        let insecure = AppConfiguration(
            infoDictionary: ["ManagedAIBaseURL": "http://quota.example"],
            buildMode: .release
        )
        XCTAssertNil(insecure.managedAIBaseURL)
        XCTAssertEqual(insecure.managedAIAvailability, .unavailable(.invalidEndpoint))
    }

    func testReleaseConfigurationDistinguishesMissingAndInvalidManagedEndpoints() {
        let missing = AppConfiguration(infoDictionary: [:], buildMode: .release)
        XCTAssertNil(missing.managedAIBaseURL)
        XCTAssertEqual(missing.managedAIAvailability, .unavailable(.missingEndpoint))

        let invalid = AppConfiguration(
            infoDictionary: ["ManagedAIBaseURL": "not a URL"],
            buildMode: .release
        )
        XCTAssertNil(invalid.managedAIBaseURL)
        XCTAssertEqual(invalid.managedAIAvailability, .unavailable(.invalidEndpoint))
    }

    func testCompiledTargetContainsMinimalUserDefaultsPrivacyManifest() throws {
        let manifestURL = try XCTUnwrap(
            Bundle.main.url(forResource: "PrivacyInfo", withExtension: "xcprivacy")
        )
        let data = try Data(contentsOf: manifestURL)
        let manifest = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        )
        let accessedTypes = try XCTUnwrap(manifest["NSPrivacyAccessedAPITypes"] as? [[String: Any]])

        XCTAssertEqual(accessedTypes.count, 1)
        XCTAssertEqual(
            accessedTypes.first?["NSPrivacyAccessedAPIType"] as? String,
            "NSPrivacyAccessedAPICategoryUserDefaults"
        )
        XCTAssertEqual(accessedTypes.first?["NSPrivacyAccessedAPITypeReasons"] as? [String], ["CA92.1"])
        XCTAssertEqual((manifest["NSPrivacyCollectedDataTypes"] as? [Any])?.count, 0)
        XCTAssertEqual(manifest["NSPrivacyTracking"] as? Bool, false)
    }

    func testCompiledTargetContainsLocalizedPermissionStrings() throws {
        let expected: [String: [String: String]] = [
            "en": [
                "NSMicrophoneUsageDescription": "Use the microphone to dictate tasks and messages to your AI companion.",
                "NSSpeechRecognitionUsageDescription": "Convert your speech to text for tasks and conversations with your AI companion."
            ],
            "zh-Hans": [
                "NSMicrophoneUsageDescription": "用于语音输入待办任务与伙伴聊天，方便你快速捕捉想法。",
                "NSSpeechRecognitionUsageDescription": "把语音转为文字，用于添加待办任务与伙伴对话。"
            ]
        ]

        for (language, strings) in expected {
            let localizationPath = try XCTUnwrap(
                Bundle.main.path(forResource: language, ofType: "lproj")
            )
            let localizationBundle = try XCTUnwrap(Bundle(path: localizationPath))
            let stringsURL = try XCTUnwrap(
                localizationBundle.url(forResource: "InfoPlist", withExtension: "strings")
            )
            let data = try Data(contentsOf: stringsURL)
            let localizedInfo = try XCTUnwrap(
                PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String]
            )

            XCTAssertEqual(localizedInfo, strings, "Unexpected \(language) permission copy")
        }
    }
}
