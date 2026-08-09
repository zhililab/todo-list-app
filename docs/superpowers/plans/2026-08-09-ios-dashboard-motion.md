# iOS Dashboard and Motion Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove the duplicate Dashboard title, bring the first task into the first screen, eliminate launch-time Paywall interruption, and unify restrained motion with Reduce Motion support.

**Architecture:** Dashboard resolves membership and sheet routing through small testable value types, renders one compact execution summary followed by the Today Plan, and consumes centralized `AppTheme.Motion` tokens. MainTab no longer owns Paywall presentation.

**Tech Stack:** Swift 5.10, SwiftUI, XCTest, iOS 17+

## Global Constraints

- The page has one navigation title: `今日` / `Today`.
- Today Plan is the largest content region and its first task is visible on a normal iPhone first screen.
- App launch never automatically presents Paywall; access remains gated at point of use.
- No spring/scale/offset/numeric rolling remains when Reduce Motion is enabled.
- `TodoCardView` business callbacks and immediate persistence remain unchanged.

---

### Task 1: Motion tokens and static card style

**Files:**
- Modify: `ios/TodoNative/Design/Theme.swift`
- Modify: `ios/TodoNative/Components/TodoCardView.swift`

**Interfaces:**
- Produces: `AppTheme.Motion.press/stateChange/content/progress/settle/resolved`, insertion/removal transitions.

- [ ] **Step 1: Add centralized tokens**

```swift
enum Motion {
    static let press = Animation.easeOut(duration: 0.12)
    static let stateChange = Animation.easeInOut(duration: 0.18)
    static let content = Animation.easeOut(duration: 0.24)
    static let progress = Animation.easeOut(duration: 0.32)
    static let settle = Animation.spring(response: 0.32, dampingFraction: 0.86)
    static func resolved(_ animation: Animation, reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : animation
    }
}
```

- [ ] **Step 2: Remove blanket card entrance and scattered button durations**

Delete `AppCardStyle.appeared/onAppear`; route button press animations through `Motion.press`. Pressed scale is 0.98 only when Reduce Motion is off.

- [ ] **Step 3: Tame TodoCard completion feedback**

Remove high-bounce two-stage pop and ensure explicit `withAnimation` paths also respect Reduce Motion. Keep parent list removal as the authoritative completion transition.

- [ ] **Step 4: Build to catch SwiftUI type errors**

Run: `xcodebuild -project ios/TodoNative.xcodeproj -scheme TodoNative -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=27.0' build`

Expected: `BUILD SUCCEEDED`.

### Task 2: Access presentation model and point-of-use routing

**Files:**
- Modify: `ios/TodoNative/Views/DashboardView.swift`
- Modify: `ios/TodoNative/Views/MainTabView.swift`
- Create: `ios/TodoNativeTests/DashboardPresentationTests.swift`

**Interfaces:**
- Produces: `DashboardAccessStatus.resolve(hasPremium:trialState:)`, `DashboardSheet`, Dashboard AI/Paywall routing.
- Consumes: `PurchaseManager.hasPremium/canUse(.aiPlan)`, `TrialManager.trialState`.

- [ ] **Step 1: Add failing access-state tests**

```swift
func testPremiumTakesPrecedenceOverTrial() {
    XCTAssertEqual(DashboardAccessStatus.resolve(hasPremium: true, trialState: .trial(remainingDays: 3)), .premium)
}

func testFreeStateDoesNotRenderZeroDayTrial() {
    XCTAssertEqual(DashboardAccessStatus.resolve(hasPremium: false, trialState: .free), .free)
}
```

Also cover active trial and AI route for premium/trial/free.

- [ ] **Step 2: Run focused tests and confirm red**

Run: `xcodebuild -project ios/TodoNative.xcodeproj -scheme TodoNative -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=27.0' -only-testing:TodoNativeTests/DashboardPresentationTests test`

- [ ] **Step 3: Implement status/sheet types and remove MainTab auto-Paywall**

```swift
enum DashboardSheet: String, Identifiable { case aiPlan, paywall; var id: String { rawValue } }
```

Delete MainTab's unused environment objects, `showingPaywall`, `onAppear`, and sheet. Dashboard opens AI only when `canUse(.aiPlan)`; otherwise it opens Paywall.

- [ ] **Step 4: Run focused tests and confirm green**

### Task 3: Compact execution summary and Today Plan hierarchy

**Files:**
- Modify: `ios/TodoNative/Views/DashboardView.swift`
- Modify: `ios/TodoNative/Localization/Localization.swift`
- Modify: `ios/TodoNativeTests/LocalizationTests.swift`

**Interfaces:**
- Produces: one compact summary, membership capsule, Today Plan CTA/menu, accessible progress.

- [ ] **Step 1: Add failing localization tests**

Require zh/en keys for Premium/Trial/Free capsule, plan action menu, regenerate, AI optimize, generate plan, and progress accessibility value.

- [ ] **Step 2: Remove duplicate header and four equal StatCards**

Render only navigation title, then completion rate/progress plus compact active/completed/health values and one-line membership action. Keep the plan full width on compact and regular size classes.

- [ ] **Step 3: Make Today Plan the primary content**

When non-empty, show tasks immediately and put regenerate/AI optimize in `Menu`. When empty, show one primary “生成今日计划” action. Replace `scale(0.85)` removal with opacity and use offset-by-8 insertion only when motion is allowed.

- [ ] **Step 4: Apply accessible motion**

Progress uses `Motion.progress` with no overshoot; values use numeric transition only outside Reduce Motion; progress exposes localized percent via `accessibilityValue`.

- [ ] **Step 5: Run localization and full iOS tests**

Run:

```bash
cd ios && xcodegen generate
xcodebuild -project TodoNative.xcodeproj -scheme TodoNative -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=27.0' -only-testing:TodoNativeTests/DashboardPresentationTests -only-testing:TodoNativeTests/LocalizationTests test
xcodebuild -project TodoNative.xcodeproj -scheme TodoNative -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=27.0' test
```

Expected: tests pass; manual simulator review confirms one title and first task on the first screen.
