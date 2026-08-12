# App Store Bilingual Screenshot Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a deterministic Debug-only screenshot harness, capture 24 complete bilingual iPhone/iPad screenshots, validate them automatically, and replace the four App Store Connect screenshot sets.

**Architecture:** A launch-argument parser selects language, scene, fixed time, and device layout. In screenshot mode the app uses an in-memory SwiftData container, localized seed content, deterministic AI/chat fixtures, reduced motion, and direct routing into the same production views; Release follows the existing bootstrap unchanged. XCUITest launches every scene independently, writes raw screenshots, and a local validation tool checks count, ordering, dimensions, alpha, language anchors, privacy strings, and SHA-256 before any portal upload.

**Tech Stack:** SwiftUI, SwiftData, XCTest/XCUITest, StoreKit Test, Vision OCR, ImageIO, CryptoKit, XcodeGen, App Store Connect Media Manager.

## Global Constraints

- Produce exactly four storefront/device groups: `zh-Hans/iphone-6.9`, `zh-Hans/ipad-13`, `en-US/iphone-6.9`, and `en-US/ipad-13`.
- Produce exactly six ordered screenshots per group: Today, capture/list, task detail, AI breakdown, AI companion, reminders/premium.
- Use only the approved synthetic release-project data; never read or display the developer's normal SwiftData database, chat history, email, device identifier, API key, endpoint, or notification content.
- English screenshots must contain English UI, dates, statuses, task data, AI input, and AI output. Chinese screenshots must contain the equivalent Chinese content.
- Re-seed data after every language change; never reuse Chinese persistent records for an English capture.
- Use Light appearance, fixed time, reduced motion, stable status bar, and portrait orientation for all 24 screenshots.
- iPhone output must be `1320 x 2868`; iPad output must be `2064 x 2752` or `2048 x 2732`.
- Images must have no alpha channel, no debug banners, no recording indicators, no private notifications, and no bottom navigation obscuring task content.
- Screenshot mode must be compiled and reachable only in Debug/UI-test builds; Release must not expose demo data or screenshot routes.
- Use the existing StoreKit product identifiers and confirmed prices; do not change subscription products, price tiers, sales regions, or entitlements.
- Do not create synthetic device frames, marketing overlays, or composite product UI.
- Do not stage `dist/`, unrelated `.superpowers/`, Xcode user data, or pre-existing untracked plan files.
- The final App Store submission action remains confirmation-gated even after media upload.

---

## File Structure

### New production-support files

- `ios/TodoNative/Screenshot/ScreenshotConfiguration.swift` — Debug-only launch argument parsing and scene/language enums.
- `ios/TodoNative/Screenshot/ScreenshotSeed.swift` — approved bilingual seed records, fixed UUIDs, fixed clock, companion messages, and workbench result fixtures.
- `ios/TodoNative/Screenshot/ScreenshotBootstrap.swift` — in-memory container, isolated defaults suite, deterministic services, and environment objects.
- `ios/TodoNative/Screenshot/ScreenshotRootView.swift` — direct scene routing into real product views.

### Modified app files

- `ios/TodoNative/TodoNativeApp.swift` — select normal or screenshot bootstrap before constructing state objects.
- `ios/TodoNative/Views/MainTabView.swift` — accept an initial tab without changing the production default.
- `ios/TodoNative/Views/SettingsView.swift` — support a real medium Paywall sheet for the approved reminders/premium frame.
- `ios/TodoNative/Views/PaywallView.swift` — expose stable screenshot identifiers and keep products/actions above the medium-sheet fold.
- `ios/TodoNative/Views/AIWorkbenchView.swift` — expose stable identifiers for goal/result readiness.
- `ios/TodoNative/Views/CompanionView.swift` — expose stable identifiers for seeded conversation readiness.
- `ios/TodoNative/Localization/Localization.swift` — make the Chinese inbox label Chinese and add a screenshot-safe support label only if an existing key is missing.
- `ios/TodoNative/Models/SubscriptionPresentation.swift` — keep plans/actions above disclosures in the real Paywall hierarchy.
- `ios/project.yml` — register UI-test target and localized StoreKit test resources.

### New tests and capture tooling

- `ios/TodoNativeTests/ScreenshotConfigurationTests.swift`
- `ios/TodoNativeTests/ScreenshotSeedTests.swift`
- `ios/TodoNativeUITests/AppStoreScreenshotTests.swift`
- `ios/TodoNativeUITests/ScreenshotWriter.swift`
- `ios/TodoNativeUITests/Resources/ScreenshotStore.zh.storekit`
- `ios/TodoNativeUITests/Resources/ScreenshotStore.en.storekit`
- `ios/scripts/capture_app_store_screenshots.sh`
- `ios/scripts/validate_app_store_screenshots.swift`
- `ios/AppStoreConnect/screenshots/manifest.json` — tracked metadata and hashes, not binary screenshots.
- `ios/AppStoreConnect/screenshots/README.md` — reproduction and upload instructions.

Raw images are written to ignored `ios/build/app-store-screenshots/`. The manifest records hashes and App Store upload order without adding 24 large binaries to git.

---

### Task 1: Screenshot configuration and bilingual seed contract

**Files:**
- Create: `ios/TodoNative/Screenshot/ScreenshotConfiguration.swift`
- Create: `ios/TodoNative/Screenshot/ScreenshotSeed.swift`
- Create: `ios/TodoNativeTests/ScreenshotConfigurationTests.swift`
- Create: `ios/TodoNativeTests/ScreenshotSeedTests.swift`

**Interfaces:**
- Produces: `ScreenshotConfiguration(arguments:environment:) -> ScreenshotConfiguration?`
- Produces: `ScreenshotLanguage` with `.zhHans` and `.enUS`.
- Produces: `ScreenshotScene: String, CaseIterable` with `today`, `tasks`, `detail`, `breakdown`, `companion`, `premium`.
- Produces: `ScreenshotSeed.content(language:now:) -> ScreenshotSeed.Content`.
- Produces: fixed `ScreenshotSeed.now == 2026-08-13 02:00:00 UTC` (10:00 Asia/Shanghai).

- [ ] **Step 1: Write parser and seed RED tests**

```swift
import XCTest
@testable import TodoNative

final class ScreenshotConfigurationTests: XCTestCase {
    func testParsesCompleteScreenshotLaunch() throws {
        let value = try XCTUnwrap(ScreenshotConfiguration(
            arguments: [
                "TodoNative", "--app-store-screenshot",
                "--screenshot-language", "en-US",
                "--screenshot-scene", "breakdown"
            ],
            environment: ["SCREENSHOT_OUTPUT_DIR": "/tmp/screens"]
        ))
        XCTAssertEqual(value.language, .enUS)
        XCTAssertEqual(value.scene, .breakdown)
        XCTAssertEqual(value.outputDirectory, "/tmp/screens")
        XCTAssertEqual(value.now, ScreenshotSeed.now)
    }

    func testNormalLaunchDoesNotEnableScreenshotMode() {
        XCTAssertNil(ScreenshotConfiguration(arguments: ["TodoNative"], environment: [:]))
    }

    func testRejectsUnknownLanguageOrScene() {
        XCTAssertNil(ScreenshotConfiguration(arguments: [
            "TodoNative", "--app-store-screenshot",
            "--screenshot-language", "fr",
            "--screenshot-scene", "today"
        ], environment: [:]))
    }
}
```

```swift
import XCTest
@testable import TodoNative

final class ScreenshotSeedTests: XCTestCase {
    func testEnglishSeedContainsNoHanCharacters() {
        let content = ScreenshotSeed.content(language: .enUS, now: ScreenshotSeed.now)
        XCTAssertFalse(content.searchableText.unicodeScalars.contains { scalar in
            (0x4E00...0x9FFF).contains(Int(scalar.value))
        })
        XCTAssertEqual(content.primaryGoal, "Launch AI Native Todo 1.0")
        XCTAssertEqual(content.dueDate, ScreenshotSeed.now.addingTimeInterval(8 * 60 * 60))
    }

    func testChineseAndEnglishSeedsTellTheSameSizedStory() {
        let zh = ScreenshotSeed.content(language: .zhHans, now: ScreenshotSeed.now)
        let en = ScreenshotSeed.content(language: .enUS, now: ScreenshotSeed.now)
        XCTAssertEqual(zh.tasks.count, 4)
        XCTAssertEqual(en.tasks.count, 4)
        XCTAssertEqual(zh.tasks.map(\.status), en.tasks.map(\.status))
        XCTAssertEqual(zh.tasks.map(\.estimatedMinutes), en.tasks.map(\.estimatedMinutes))
        XCTAssertTrue(zh.searchableText.contains("发布 AI Native Todo 1.0"))
    }

    func testSeedNeverContainsReleaseSecretsOrPersonalData() {
        for language in ScreenshotLanguage.allCases {
            let text = ScreenshotSeed.content(language: language, now: ScreenshotSeed.now).searchableText
            XCTAssertFalse(text.contains("lz123321"))
            XCTAssertFalse(text.contains("workers.dev"))
            XCTAssertFalse(text.contains("000081"))
            XCTAssertFalse(text.lowercased().contains("api key"))
        }
    }
}
```

- [ ] **Step 2: Generate the project and verify RED**

Run:

```bash
cd ios
xcodegen generate
xcodebuild -project TodoNative.xcodeproj -scheme TodoNative \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=27.0' \
  -only-testing:TodoNativeTests/ScreenshotConfigurationTests \
  -only-testing:TodoNativeTests/ScreenshotSeedTests test
```

Expected: compilation fails because `ScreenshotConfiguration`, `ScreenshotLanguage`, `ScreenshotScene`, and `ScreenshotSeed` do not exist.

- [ ] **Step 3: Implement the minimal deterministic model**

```swift
#if DEBUG
import Foundation

enum ScreenshotLanguage: String, CaseIterable, Sendable {
    case zhHans = "zh-Hans"
    case enUS = "en-US"

    var appLanguage: String { self == .zhHans ? "zh" : "en" }
}

enum ScreenshotScene: String, CaseIterable, Sendable {
    case today, tasks, detail, breakdown, companion, premium
}

struct ScreenshotConfiguration: Equatable, Sendable {
    let language: ScreenshotLanguage
    let scene: ScreenshotScene
    let outputDirectory: String?
    let now: Date

    init?(arguments: [String], environment: [String: String]) {
        guard arguments.contains("--app-store-screenshot") else { return nil }
        func value(after flag: String) -> String? {
            guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else { return nil }
            return arguments[index + 1]
        }
        guard
            let language = value(after: "--screenshot-language").flatMap(ScreenshotLanguage.init(rawValue:)),
            let scene = value(after: "--screenshot-scene").flatMap(ScreenshotScene.init(rawValue:))
        else { return nil }
        self.language = language
        self.scene = scene
        outputDirectory = environment["SCREENSHOT_OUTPUT_DIR"]
        now = ScreenshotSeed.now
    }
}
#endif
```

Implement `ScreenshotSeed.Content` with the exact approved titles, task details, three executable AI suggestions, two assistant messages, statuses `[.doing, .todo, .todo, .done]`, priorities `[5, 4, 3, 2]`, estimates `[30, 20, 15, 10]`, and deterministic UUIDs `00000000-0000-0000-0000-000000000001` through `00000000-0000-0000-0000-000000000004`. Build `searchableText` by concatenating every visible fixture string.

- [ ] **Step 4: Run focused tests and verify GREEN**

Run the command from Step 2.

Expected: both test classes pass with zero failures.

- [ ] **Step 5: Commit the contract**

```bash
git add ios/TodoNative/Screenshot/ScreenshotConfiguration.swift \
  ios/TodoNative/Screenshot/ScreenshotSeed.swift \
  ios/TodoNativeTests/ScreenshotConfigurationTests.swift \
  ios/TodoNativeTests/ScreenshotSeedTests.swift \
  ios/TodoNative.xcodeproj/project.pbxproj
git commit -m "feat(ios): add deterministic screenshot fixtures"
```

---

### Task 2: Isolated Debug bootstrap and real-view routing

**Files:**
- Create: `ios/TodoNative/Screenshot/ScreenshotBootstrap.swift`
- Create: `ios/TodoNative/Screenshot/ScreenshotRootView.swift`
- Modify: `ios/TodoNative/TodoNativeApp.swift`
- Modify: `ios/TodoNative/Views/MainTabView.swift`
- Modify: `ios/TodoNative/Views/SettingsView.swift`
- Modify: `ios/TodoNative/Views/PaywallView.swift`
- Modify: `ios/TodoNative/Views/AIWorkbenchView.swift`
- Modify: `ios/TodoNative/Views/CompanionView.swift`
- Modify: `ios/TodoNative/Localization/Localization.swift`
- Modify: `ios/TodoNative/Models/SubscriptionPresentation.swift`
- Modify: `ios/TodoNativeTests/LocalizationTests.swift`
- Modify: `ios/TodoNativeTests/SubscriptionPresentationTests.swift`
- Test: `ios/TodoNativeTests/ScreenshotSeedTests.swift`

**Interfaces:**
- Consumes: `ScreenshotConfiguration`, `ScreenshotSeed.Content`.
- Produces: `@MainActor ScreenshotBootstrap(configuration:) throws` with in-memory `ModelContainer` and all app environment objects.
- Produces: `ScreenshotRootView(configuration:bootstrap:)`.
- Produces: accessibility readiness identifiers `screenshot.today.ready`, `screenshot.tasks.ready`, `screenshot.detail.ready`, `screenshot.breakdown.ready`, `screenshot.companion.ready`, and `screenshot.premium.ready`.

- [ ] **Step 1: Add RED tests for in-memory isolation and exact seed values**

```swift
@MainActor
func testBootstrapSeedsOnlySelectedLanguageIntoInMemoryStore() throws {
    let config = ScreenshotConfiguration.test(language: .enUS, scene: .tasks)
    let bootstrap = try ScreenshotBootstrap(configuration: config)
    XCTAssertEqual(bootstrap.todoViewModel.items.count, 4)
    XCTAssertEqual(bootstrap.todoViewModel.items.first?.title, "Launch AI Native Todo 1.0")
    XCTAssertEqual(bootstrap.languageEnvironment.language, "en")
    XCTAssertTrue(bootstrap.storeIsInMemory)
}
```

- [ ] **Step 2: Run focused tests and verify RED**

Run:

```bash
cd ios
xcodegen generate
xcodebuild -project TodoNative.xcodeproj -scheme TodoNative \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=27.0' \
  -only-testing:TodoNativeTests/ScreenshotSeedTests test
```

Expected: compilation fails because `ScreenshotBootstrap` and `.test(language:scene:)` do not exist.

- [ ] **Step 3: Implement isolated bootstrap before constructing normal app state**

`ScreenshotBootstrap` must:

```swift
let schema = Schema([TodoItem.self])
let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
modelContainer = try ModelContainer(for: schema, configurations: [config])
defaults = UserDefaults(suiteName: "com.zhili.todo-native.screenshots.\(configuration.language.rawValue)")!
defaults.removePersistentDomain(forName: defaultsSuiteName)
Localization.setLanguage(configuration.language.appLanguage)
```

Insert the four seeded `TodoItem`s, copy the fixed UUID/created/updated/completed timestamps after initialization, and save once. Expose `let storeIsInMemory = true` on the screenshot bootstrap so the test asserts the selected construction path instead of relying on unavailable ModelContainer configuration introspection. Use a no-op reminder scheduler, a deterministic `AIAssistantServing` that returns the approved brief/workbench fixtures, and a `CompanionViewModel` initialized from the approved messages without writing chat history to `UserDefaults.standard`. The screenshot runner uses dedicated simulators, and every independent launch sets `Localization` before creating `LanguageEnvironment`, so a language switch cannot retain seed records or localized view state from the prior launch.

Refactor `TodoNativeApp.init()` so it first parses:

```swift
#if DEBUG
let screenshotConfiguration = ScreenshotConfiguration(
    arguments: ProcessInfo.processInfo.arguments,
    environment: ProcessInfo.processInfo.environment
)
#else
let screenshotConfiguration: Never? = nil
#endif
```

When present, construct the screenshot bootstrap and skip `NotificationService.setup()`, `purchaseManager.initialize()`, quota calls, AI consent presentation, and persistent database initialization. When absent, retain the existing production path byte-for-byte in behavior.

- [ ] **Step 4: Route six scenes through real product views**

Add:

```swift
enum MainTab: Int { case today, tasks, companion, settings }

struct MainTabView: View {
    @State private var selectedTab: Int
    init(initialTab: MainTab = .today) {
        _selectedTab = State(initialValue: initialTab.rawValue)
    }
    // existing TabView remains unchanged
}
```

`ScreenshotRootView` routes:

```swift
switch configuration.scene {
case .today: MainTabView(initialTab: .today)
case .tasks: MainTabView(initialTab: .tasks)
case .detail: TaskEditView(item: bootstrap.primaryGoal)
case .breakdown: ScreenshotWorkbenchScene(primaryGoal: bootstrap.primaryGoal)
case .companion: CompanionView(buddy: bootstrap.companionViewModel)
case .premium: SettingsView(initiallyShowsPaywall: true, screenshotPaywallDetent: .medium)
}
```

`ScreenshotWorkbenchScene` renders the real `AIWorkbenchView` and runs this one-time setup in `.task`:

```swift
briefing.open(mode: .breakdown, prefill: primaryGoal.title)
briefing.selectGoalTask(primaryGoal)
await briefing.runWorkbench(items: vm.items, health: vm.healthScore, now: ScreenshotSeed.now)
```

For the premium scene, use the existing Settings reminder content and present the real `PaywallView` as a medium sheet. Change the real `PaywallPresentation.sectionOrder` to `[.header, .products, .billingActions, .legalLinks, .renewalAndCancellation, .status]`, add the already-configured Support URL beside Privacy and Terms, and allow the production sheet to be dragged between medium and large while keeping large as its normal default. `SettingsView(initiallyShowsPaywall:screenshotPaywallDetent:)` selects medium only for the Debug screenshot route. This makes monthly/yearly prices, Restore, and all three public links visible without changing products, entitlements, or pricing.

Update the Chinese localization value:

```swift
"tasks.inboxTag": "自然语言收件箱"
```

Add a localization test asserting that `tasks.inboxTag` contains Han text in Chinese and equals `Natural language inbox` in English. Update `SubscriptionPresentationTests` to assert the new real section order and that all three public links are available in the Paywall presentation.

Add the readiness identifiers to the last stable container for each scene. Use `.transaction { $0.animation = nil }` only when screenshot mode is active and set accessibility Reduce Motion through launch arguments.

- [ ] **Step 5: Verify Debug path and Release exclusion**

Run:

```bash
cd ios
xcodegen generate
xcodebuild -project TodoNative.xcodeproj -scheme TodoNative \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=27.0' \
  -only-testing:TodoNativeTests/ScreenshotSeedTests test
xcodebuild -project TodoNative.xcodeproj -scheme TodoNative \
  -configuration Release -destination 'generic/platform=iOS Simulator' build
```

Expected: focused tests pass; Release builds; searching the Release binary for `--app-store-screenshot` returns zero matches.

- [ ] **Step 6: Commit the Debug harness**

```bash
git add ios/TodoNative/Screenshot ios/TodoNative/TodoNativeApp.swift \
  ios/TodoNative/Views/MainTabView.swift ios/TodoNative/Views/SettingsView.swift \
  ios/TodoNative/Views/PaywallView.swift ios/TodoNative/Views/AIWorkbenchView.swift \
  ios/TodoNative/Views/CompanionView.swift ios/TodoNative/Localization/Localization.swift \
  ios/TodoNative/Models/SubscriptionPresentation.swift \
  ios/TodoNativeTests/ScreenshotSeedTests.swift ios/TodoNativeTests/LocalizationTests.swift \
  ios/TodoNativeTests/SubscriptionPresentationTests.swift \
  ios/TodoNative.xcodeproj/project.pbxproj
git commit -m "feat(ios): add reproducible App Store scenes"
```

---

### Task 3: UI-test capture matrix and localized StoreKit data

**Files:**
- Create: `ios/TodoNativeUITests/AppStoreScreenshotTests.swift`
- Create: `ios/TodoNativeUITests/ScreenshotWriter.swift`
- Create: `ios/TodoNativeUITests/Resources/ScreenshotStore.zh.storekit`
- Create: `ios/TodoNativeUITests/Resources/ScreenshotStore.en.storekit`
- Modify: `ios/project.yml`

**Interfaces:**
- Produces: UI-test target `TodoNativeUITests`.
- Produces: `ScreenshotWriter.write(_:name:to:) throws`.
- Consumes environment: `SCREENSHOT_LANGUAGE`, `SCREENSHOT_DEVICE_CLASS`, `SCREENSHOT_OUTPUT_DIR`.

- [ ] **Step 1: Add UI-test target and the first capture RED test**

Add to `project.yml`:

```yaml
  TodoNativeUITests:
    type: bundle.ui-testing
    platform: iOS
    deploymentTarget: "17.0"
    sources:
      - path: TodoNativeUITests
    resources:
      - path: TodoNativeUITests/Resources
    dependencies:
      - target: TodoNative
    settings:
      base:
        GENERATE_INFOPLIST_FILE: YES
        PRODUCT_BUNDLE_IDENTIFIER: com.zhili.todo-native.uitests
        TEST_TARGET_NAME: TodoNative
```

Write `test01Today()` to launch the app in screenshot mode, wait for `screenshot.today.ready`, call the not-yet-existing `ScreenshotWriter.write`, and assert the expected file exists. Run XcodeGen and expect compilation failure until the writer exists.

- [ ] **Step 2: Implement exact file naming and conversion**

```swift
enum ScreenshotWriter {
    static func write(_ screenshot: XCUIScreenshot, name: String, to directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let png = screenshot.pngRepresentation
        guard
            let source = CGImageSourceCreateWithData(png as CFData, nil),
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
            let destination = CGImageDestinationCreateWithURL(
                directory.appendingPathComponent(name + ".jpg") as CFURL,
                UTType.jpeg.identifier as CFString,
                1,
                nil
            )
        else { throw ScreenshotWriterError.encodingFailed }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.94] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw ScreenshotWriterError.encodingFailed }
    }
}
```

- [ ] **Step 3: Add exact localized StoreKit fixtures**

Copy the two approved v2 product IDs into both StoreKit files. Configure:

- Chinese: locale `zh_CN`, storefront `CHN`, monthly `18.00`, yearly `128.00`.
- English: locale `en_US`, storefront `USA`, monthly `2.99`, yearly `19.99`.
- No introductory Apple offer; group/product copy matches the approved Chinese and English subscription metadata.

The UI test selects `ScreenshotStore.zh.storekit` for `zh-Hans` and `ScreenshotStore.en.storekit` for `en-US` with `SKTestSession`, clears transactions, disables dialogs, and launches the app only after the session is active.

- [ ] **Step 4: Implement six independent capture tests**

```swift
private enum CaptureScene: String {
    case today, tasks, detail, breakdown, companion, premium
}

private func capture(scene: CaptureScene, index: Int) throws {
    let app = XCUIApplication()
    app.launchArguments = [
        "--app-store-screenshot",
        "--screenshot-language", language,
        "--screenshot-scene", scene.rawValue,
        "-AppleLanguages", language == "en-US" ? "(en)" : "(zh-Hans)",
        "-AppleLocale", language == "en-US" ? "en_US" : "zh_CN",
        "-UIUserInterfaceStyle", "Light",
        "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryM"
    ]
    app.launchEnvironment["SCREENSHOT_OUTPUT_DIR"] = outputDirectory.path
    app.launch()
    XCTAssertTrue(app.otherElements["screenshot.\(scene.rawValue).ready"].waitForExistence(timeout: 15))
    try ScreenshotWriter.write(
        XCUIScreen.main.screenshot(),
        name: String(format: "%02d-%@", index, scene.rawValue),
        to: outputDirectory
    )
    app.terminate()
}
```

Create six XCTest methods so a failed scene is reported individually. Do not scroll opportunistically inside the test; the corresponding screenshot scene must render its acceptance content in the initial stable viewport.

- [ ] **Step 5: Run one language/device matrix and verify GREEN**

Run:

```bash
cd ios
xcodegen generate
SCREENSHOT_LANGUAGE=en-US \
SCREENSHOT_DEVICE_CLASS=iphone-6.9 \
SCREENSHOT_OUTPUT_DIR="$PWD/build/app-store-screenshots/en-US/iphone-6.9" \
xcodebuild -project TodoNative.xcodeproj -scheme TodoNative \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max,OS=27.0' \
  -only-testing:TodoNativeUITests/AppStoreScreenshotTests test
```

Expected: six UI tests pass and six ordered JPEGs are created.

- [ ] **Step 6: Commit capture tests**

```bash
git add ios/project.yml ios/TodoNativeUITests ios/TodoNative.xcodeproj/project.pbxproj
git commit -m "feat(ios): automate bilingual store screenshots"
```

This commit is temporary during implementation and must be squashed into the screenshot feature commit before push, per repository policy.

---

### Task 4: Four-matrix capture runner and asset validator

**Files:**
- Create: `ios/scripts/capture_app_store_screenshots.sh`
- Create: `ios/scripts/validate_app_store_screenshots.swift`
- Create: `ios/AppStoreConnect/screenshots/README.md`
- Create: `ios/AppStoreConnect/screenshots/manifest.json`

**Interfaces:**
- Produces command: `ios/scripts/capture_app_store_screenshots.sh`.
- Produces command: `xcrun swift ios/scripts/validate_app_store_screenshots.swift <asset-root> <manifest-path>`.

- [ ] **Step 1: Write validator RED fixtures**

The validator must fail independently for:

1. not exactly 24 files;
2. wrong ordered filename;
3. wrong dimensions;
4. alpha channel;
5. Han characters in an `en-US` image after Vision OCR;
6. missing expected Chinese/English scene anchor;
7. forbidden patterns `workers.dev`, `API Key`, `000081`, `lz123321`, and raw localization keys matching `(tab|dashboard|tasks|card|settings|notice|ai|buddy|paywall|common)\.[A-Za-z.]+`;
8. duplicate SHA-256 across different scene indices.

Create generated 100x100 fixtures inside `/tmp` during the script's `--self-test`; do not commit binary fixture images.

- [ ] **Step 2: Implement the capture runner**

The shell script must:

```bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="$ROOT/ios/build/app-store-screenshots"
rm -rf "$OUT"
mkdir -p "$OUT"
cd "$ROOT/ios"
xcodegen generate
```

Discover an available `iPhone 17 Pro Max` and a 13-inch iPad simulator, boot each, set portrait orientation, Light appearance, and a deterministic status bar (`9:41`, full Wi-Fi, 100% battery). Run the UI-test class for both languages on both devices. Never erase a user's physical device or normal app data.

- [ ] **Step 3: Implement Vision/ImageIO/CryptoKit validation**

For every output:

```swift
struct AssetRecord: Codable {
    let language: String
    let deviceClass: String
    let order: Int
    let scene: String
    let width: Int
    let height: Int
    let sha256: String
    let recognizedText: String
}
```

Use `CGImageSourceCopyPropertiesAtIndex` for dimensions/alpha, `VNRecognizeTextRequest` with `.accurate` for OCR, and `SHA256.hash(data:)` for the digest. Require English anchors `Today`, `Tasks`, `Context`, `Break down`, `Companion`, `Reminders`; require Chinese anchors `今日`, `任务`, `上下文`, `拆解`, `伙伴`, `提醒` by scene. Allow product name `AI Native Todo` and URLs.

- [ ] **Step 4: Run self-test, capture, and validation**

Run:

```bash
xcrun swift ios/scripts/validate_app_store_screenshots.swift --self-test
ios/scripts/capture_app_store_screenshots.sh
xcrun swift ios/scripts/validate_app_store_screenshots.swift \
  ios/build/app-store-screenshots \
  ios/AppStoreConnect/screenshots/manifest.json
```

Expected: self-test reports every intended rejection; capture produces 24 files; validation reports `24/24 PASS` and writes the manifest.

- [ ] **Step 5: Add reproduction documentation**

Document the exact command, output tree, simulator model/OS, fixed time, language flags, App Store order, manifest schema, and the requirement to visually inspect before upload. State explicitly that raw assets are local release artifacts and not committed.

- [ ] **Step 6: Commit tooling and manifest**

```bash
git add ios/scripts/capture_app_store_screenshots.sh \
  ios/scripts/validate_app_store_screenshots.swift \
  ios/AppStoreConnect/screenshots/README.md \
  ios/AppStoreConnect/screenshots/manifest.json
git commit -m "docs(ios): record App Store screenshot evidence"
```

---

### Task 5: Visual QA and product regression

**Files:**
- Modify if required by observed layout defect: the smallest relevant file under `ios/TodoNative/Views/`.
- Modify after approved recapture: `ios/AppStoreConnect/screenshots/manifest.json`.

**Interfaces:**
- Consumes: all 24 validated files and manifest.
- Produces: a visually approved, regression-tested capture set.

- [ ] **Step 1: Build a 4x6 contact sheet outside git**

Use ImageIO or `sips` to create:

`ios/build/app-store-screenshots/contact-sheet.jpg`

Rows are `zh iPhone`, `zh iPad`, `en iPhone`, `en iPad`; columns are the six fixed scenes. Label only outside the screenshot pixels in the contact sheet; labels are not uploaded.

- [ ] **Step 2: Inspect every scene against the approved spec**

Reject and recapture if any of these are observed:

- iPad first screen has meaningless blank area, clipped primary action, or only a partial task list;
- tab bar covers task content;
- English contains Han characters or Chinese seed data;
- Chinese contains English sample sentences or raw localization keys;
- task state, priority, duration, or due time differs between list/detail;
- AI result is loading, empty, stale, or exposes endpoint/debug text;
- companion text is private, location-specific, or unrelated to the launch project;
- premium frame omits reminder control, monthly/yearly StoreKit prices, Restore, Privacy, Terms, or Support.

- [ ] **Step 3: Fix only observed defects with a RED test first**

For a layout defect, add a pure presentation/layout test or screenshot readiness assertion that reproduces the failure, run it to RED, make the smallest production-view adjustment, then rerun only that scene on all four matrices. Do not redesign unrelated app navigation or cards.

- [ ] **Step 4: Run complete regression**

Run:

```bash
node --test
cd ios
xcodegen generate
xcodebuild -project TodoNative.xcodeproj -scheme TodoNative \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=27.0' test
xcodebuild -project TodoNative.xcodeproj -scheme TodoNative \
  -configuration Release -destination 'generic/platform=iOS Simulator' build
```

Expected: Web and iOS tests pass; Release builds; screenshot validation remains `24/24 PASS`.

- [ ] **Step 5: Consolidate implementation history**

Before push, consolidate the temporary Task 1–4 implementation commits into at most:

1. `feat(ios): automate bilingual App Store screenshots`
2. `docs(ios): record App Store screenshot evidence`

Create a backup branch first, verify pre/post-squash trees are identical, and never rewrite a pushed branch without `--force-with-lease`.

---

### Task 6: Replace App Store Connect media and verify storefront previews

**Files:**
- Modify after portal verification: `ios/AppStoreConnect/release-evidence.md`
- Modify after portal verification: `ios/AppStoreConnect/screenshots/manifest.json`

**Interfaces:**
- Consumes: `ios/build/app-store-screenshots/` and its validated manifest.
- Produces: four App Store Connect screenshot sets in the approved order.

- [ ] **Step 1: Re-open the exact App Store version and localizations**

Open App Store Connect app `AI Native Todo`, iOS version `1.0`, then verify the editable localizations are Simplified Chinese and English (U.S.). Do not alter the macOS platform record.

- [ ] **Step 2: Upload one group at a time**

Upload in this order:

1. `zh-Hans/iphone-6.9`
2. `zh-Hans/ipad-13`
3. `en-US/iphone-6.9`
4. `en-US/ipad-13`

Within each group upload `01` through `06` in filename order. Wait for all six previews to finish processing before moving to the next group.

- [ ] **Step 3: Verify previews before removing old media**

For every group, confirm:

- exactly six screenshots;
- correct language and device family;
- order matches the approved narrative;
- no crop, rotation, scaling, duplicate image, or blank processing tile.

Only after all four groups pass should old screenshots be removed/replaced.

- [ ] **Step 4: Save media metadata without submitting the version**

Save the App Store version metadata. Do not click the final submission action in this step.

- [ ] **Step 5: Record external evidence**

Add the observed upload timestamp, App Store version, four group counts, manifest SHA-256, and portal preview result to `release-evidence.md`. Mark the final submission action as `BLOCKED — requires product-owner confirmation at action time`.

- [ ] **Step 6: Commit evidence**

```bash
git add ios/AppStoreConnect/release-evidence.md \
  ios/AppStoreConnect/screenshots/manifest.json
git commit -m "docs(ios): record bilingual screenshot upload"
```

---

## Final Verification Gate

Before asking for submission confirmation, all conditions must be true:

- [ ] Screenshot parser/seed tests pass.
- [ ] UI screenshot tests pass on both target simulator families.
- [ ] Exactly 24 validated assets exist.
- [ ] All four groups pass OCR, dimensions, alpha, forbidden-data, and ordering checks.
- [ ] Contact-sheet review confirms complete iPad scenes and fully English U.S. screenshots.
- [ ] Full Web and iOS test suites pass.
- [ ] Release build succeeds and contains no screenshot launch marker.
- [ ] App Store Connect shows six processed screenshots in each of four groups.
- [ ] Release evidence references the exact tested product commit and manifest hash.
- [ ] Branch history is consolidated into a small number of logical commits.
- [ ] Final “Submit for Review” remains unclicked until the product owner confirms.
