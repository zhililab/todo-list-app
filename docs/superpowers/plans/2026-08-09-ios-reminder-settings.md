# iOS Reminder Settings Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an App-level reminder Toggle that gates scheduling, cancels and restores task reminders correctly, and hides diagnostics from Release builds.

**Architecture:** Replace the static notification enum with an injectable `@MainActor` service backed by a small notification-center client protocol. `TodoViewModel` depends only on `ReminderScheduling`; `SettingsView` binds to the shared service while system authorization remains a separate state.

**Tech Stack:** Swift 5.10, SwiftUI, UserNotifications, SwiftData, XCTest, XcodeGen, iOS 17+

## Global Constraints

- Release UI and compiled Settings helpers must not expose test notifications or pending diagnostic counts.
- Disabling reminders cancels all task reminders and prevents future scheduling.
- Re-enabling restores only future, incomplete, unarchived tasks.
- New identifiers use `task-reminder.<UUID>` while cancellation also removes legacy bare UUID identifiers.
- Do not change `DueDateParser` behavior.
- New source files require one `cd ios && xcodegen generate` after parallel edits settle.

---

### Task 1: Injectable notification state and identifier rules

**Files:**
- Create: `ios/TodoNative/Services/NotificationCenterClient.swift`
- Modify: `ios/TodoNative/Services/NotificationService.swift`
- Modify: `ios/TodoNativeTests/NotificationServiceTests.swift`

**Interfaces:**
- Produces: `NotificationCenterClient`, `SystemNotificationCenterClient`, `ReminderScheduling`, `NotificationService`, `ReminderEnableResult`.
- Consumes: `UNUserNotificationCenter`, `UserDefaults`.

- [ ] **Step 1: Add failing identifier and preference tests**

```swift
func testReminderIdentifierUsesTaskPrefix() {
    let id = UUID()
    XCTAssertEqual(NotificationService.reminderIdentifier(for: id), "task-reminder.\(id.uuidString)")
}

func testDebugIdentifierIsNotCountedAsReminder() {
    XCTAssertFalse(NotificationService.isReminderIdentifier("test-notification-123"))
}
```

- [ ] **Step 2: Run the focused test target and confirm red**

Run: `xcodebuild -project ios/TodoNative.xcodeproj -scheme TodoNative -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=27.0' -only-testing:TodoNativeTests/NotificationServiceTests test`

Expected: `TEST FAILED` because the instance service and identifier helpers do not exist.

- [ ] **Step 3: Add the client and service interfaces**

```swift
@MainActor
protocol NotificationCenterClient: AnyObject {
    func authorizationStatus() async -> UNAuthorizationStatus
    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool
    func add(_ request: UNNotificationRequest) async throws
    func pendingRequests() async -> [UNNotificationRequest]
    func removePendingRequests(withIdentifiers identifiers: [String])
}

@MainActor
protocol ReminderScheduling: AnyObject {
    func scheduleDueReminder(taskID: UUID, title: String, dueDate: Date)
    func cancelReminder(taskID: UUID)
}
```

Implement `NotificationService` with `enabledKey`, `reminderPrefix`, `testPrefix`, published app/system/count state, injected client/defaults, and pure identifier helpers. Keep the existing `triggerDate` semantics.

- [ ] **Step 4: Run focused tests and confirm green**

Expected: `TEST SUCCEEDED` for identifier, initial preference, and existing trigger-date tests.

### Task 2: Permission gate, cancellation, and race safety

**Files:**
- Modify: `ios/TodoNative/Services/NotificationService.swift`
- Modify: `ios/TodoNativeTests/NotificationServiceTests.swift`

**Interfaces:**
- Produces: `refresh() async`, `setRemindersEnabled(_:) async -> ReminderEnableResult`, `cancelAllReminders() async`.
- Consumes: Task 1 client/service contracts.

- [ ] **Step 1: Add failing permission matrix tests**

Cover authorized, provisional, notDetermined/granted, notDetermined/denied, denied, restricted, revoked-on-refresh, enabled scheduling, disabled scheduling, dual identifier cancellation, bulk cancellation preserving unrelated requests, and an in-flight schedule losing to disable.

- [ ] **Step 2: Run focused tests and confirm red**

Expected: failures on missing enable flow and race generation.

- [ ] **Step 3: Implement the enable flow and scheduling generation**

```swift
enum ReminderEnableResult: Equatable {
    case enabled, disabled, permissionDenied, restricted
}
```

On disable, persist `false`, increment `schedulingGeneration`, remove namespaced and parseable legacy UUID requests, then refresh the task-only count. Before and after `client.add`, verify enabled state, authorized state, and captured generation; remove a late request if disable won.

- [ ] **Step 4: Run focused tests and confirm green**

Expected: all `NotificationServiceTests` pass without touching the real notification center.

### Task 3: TodoViewModel scheduling dependency and restoration

**Files:**
- Modify: `ios/TodoNative/ViewModels/TodoViewModel.swift`
- Modify: `ios/TodoNativeTests/TodoViewModelTests.swift`

**Interfaces:**
- Consumes: `ReminderScheduling`.
- Produces: `init(modelContainer:reminderScheduler:)`, `restoreDueReminders(now:)`.

- [ ] **Step 1: Inject a fake scheduler and add failing behavior tests**

```swift
@MainActor
final class FakeReminderScheduler: ReminderScheduling {
    var scheduled: [(UUID, String, Date)] = []
    var cancelled: [UUID] = []
    func scheduleDueReminder(taskID: UUID, title: String, dueDate: Date) {
        scheduled.append((taskID, title, dueDate))
    }
    func cancelReminder(taskID: UUID) { cancelled.append(taskID) }
}
```

Assert add, natural-language capture, edit, due-date removal, complete, archive, delete, and restoration filters.

- [ ] **Step 2: Run `TodoViewModelTests` and confirm red**

Run: `xcodebuild -project ios/TodoNative.xcodeproj -scheme TodoNative -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=27.0' -only-testing:TodoNativeTests/TodoViewModelTests test`

- [ ] **Step 3: Replace static calls with the injected scheduler**

```swift
func restoreDueReminders(now: Date = Date()) {
    for item in items where !item.isArchived && !item.isCompleted {
        guard let dueDate = item.dueDate, dueDate > now else { continue }
        reminderScheduler.scheduleDueReminder(taskID: item.id, title: item.title, dueDate: dueDate)
    }
}
```

- [ ] **Step 4: Run focused tests and confirm green**

### Task 4: Settings Toggle, lifecycle, DEBUG isolation

**Files:**
- Modify: `ios/TodoNative/TodoNativeApp.swift`
- Modify: `ios/TodoNative/Views/SettingsView.swift`
- Modify: `ios/TodoNative/Localization/Localization.swift`
- Modify: `ios/TodoNativeTests/LocalizationTests.swift`

**Interfaces:**
- Consumes: shared `NotificationService`, `TodoViewModel.restoreDueReminders()`.
- Produces: app-level Toggle, system status row, denied-settings action, Debug-only diagnostics.

- [ ] **Step 1: Add failing localization key tests**

Require zh/en keys for reminder toggle, allowed/denied/notDetermined system state, settings action, permission explanation, and Debug pending count.

- [ ] **Step 2: Run `LocalizationTests` and confirm red**

- [ ] **Step 3: Inject service and remove launch-time permission request**

Create `NotificationService` before `TodoViewModel`, inject it as scheduler and environment object, call `setup()`, refresh on task and when `scenePhase == .active`, and delete unconditional `requestAuthorization()`.

- [ ] **Step 4: Implement the explicit Toggle binding**

```swift
Toggle(Localization.t("noticeEnable"), isOn: Binding(
    get: { notificationService.isRemindersEnabled },
    set: { requested in
        Task {
            let result = await notificationService.setRemindersEnabled(requested)
            if result == .enabled { vm.restoreDueReminders() }
            if result == .permissionDenied || result == .restricted {
                showNotificationSettingsPrompt = true
            }
        }
    }
))
```

Wrap the test button, test-result state/helper, and pending count in `#if DEBUG`.

- [ ] **Step 5: Regenerate, test, and verify Release isolation**

Run:

```bash
cd ios && xcodegen generate
xcodebuild -project TodoNative.xcodeproj -scheme TodoNative -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=27.0' test
xcodebuild -project TodoNative.xcodeproj -scheme TodoNative -configuration Release -destination 'generic/platform=iOS Simulator' build
```

Expected: all tests pass; Release builds and the diagnostic controls are inside `#if DEBUG`.
