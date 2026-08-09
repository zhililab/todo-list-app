# iOS Companion Input Modes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the simultaneous mic/text UI with icon-only keyboard/voice modes and a safe tap-to-start, tap-to-stop transcription flow.

**Architecture:** A pure `CompanionComposerState` owns mode and draft merging. An injectable `CompanionVoiceRecorder` state machine owns permission and recording behavior through `CompanionVoiceRuntime`; `CompanionViewModel.input/send` remain unchanged.

**Tech Stack:** Swift 5.10, SwiftUI, Speech, AVFoundation, XCTest, iOS 17+

## Global Constraints

- Toggle icons use SF Symbols `waveform` and `keyboard`; no visible mode text.
- Final transcription enters the composer, appends to existing draft, and never auto-sends.
- Partial transcription never mutates `CompanionViewModel.input`.
- Stop and cancel remain available after recording starts, even if AI becomes busy.
- Microphone and speech-recognition permission failures remain distinct.
- Every interactive icon has a 44×44pt target and localized VoiceOver semantics.

---

### Task 1: Pure composer state

**Files:**
- Create: `ios/TodoNative/ViewModels/CompanionComposerState.swift`
- Create: `ios/TodoNativeTests/CompanionComposerStateTests.swift`

**Interfaces:**
- Produces: `CompanionComposerState.Mode`, mode switching, draft snapshot, merge/cancel functions.

- [ ] **Step 1: Write failing mode and draft tests**

Cover default keyboard, switch-to-voice preservation, empty/existing draft finish, empty transcript, cancel restoration, and switch-back-before-recording.

- [ ] **Step 2: Generate the project and confirm red**

Run:

```bash
cd ios && xcodegen generate
xcodebuild -project TodoNative.xcodeproj -scheme TodoNative -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=27.0' -only-testing:TodoNativeTests/CompanionComposerStateTests test
```

- [ ] **Step 3: Implement the pure state**

```swift
struct CompanionComposerState: Equatable {
    enum Mode: Equatable { case keyboard, voice }
    private(set) var mode: Mode = .keyboard
    private var draftBeforeRecording: String?

    mutating func switchToVoice()
    mutating func switchToKeyboard()
    mutating func beginRecording(currentDraft: String)
    mutating func finishRecording(transcript: String) -> String
    mutating func cancelRecording() -> String?
    static func mergedDraft(existing: String, transcript: String) -> String
}
```

Trim transcript; join two non-empty values with one space; always return to keyboard after finish/cancel.

- [ ] **Step 4: Run focused tests and confirm green**

### Task 2: Injectable recording runtime and recorder state machine

**Files:**
- Create: `ios/TodoNative/Services/CompanionVoiceRuntime.swift`
- Modify: `ios/TodoNative/Services/CompanionVoiceRecorder.swift`
- Create: `ios/TodoNativeTests/CompanionVoiceRecorderTests.swift`

**Interfaces:**
- Produces: typed permissions/errors/events, runtime protocol, recorder states `idle/requestingPermission/recording/finalizing`.

- [ ] **Step 1: Add failing permission and re-entry tests with a fake runtime**

Test speech-then-mic order, each denial, unavailable recognizer, double start, and cancel while permission awaits.

- [ ] **Step 2: Run focused tests and confirm red**

Run: `xcodebuild -project ios/TodoNative.xcodeproj -scheme TodoNative -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=27.0' -only-testing:TodoNativeTests/CompanionVoiceRecorderTests test`

- [ ] **Step 3: Implement the contracts**

```swift
enum CompanionVoiceRuntimeEvent: Equatable, Sendable {
    case partial(String), final(String), failure(CompanionVoiceError)
}

@MainActor
protocol CompanionVoiceRuntime: AnyObject {
    func requestSpeechPermission() async -> CompanionVoicePermission
    func requestMicrophonePermission() async -> CompanionVoicePermission
    func isRecognizerAvailable(locale: Locale) -> Bool
    func start(locale: Locale, onEvent: @escaping @MainActor @Sendable (CompanionVoiceRuntimeEvent) -> Void) throws
    func stop()
    func cancel()
}
```

After every permission await, re-check recorder state so a late permission result cannot restart cancelled input.

- [ ] **Step 4: Add partial/final/stop/cancel/error tests**

Assert partial-only publication, exactly-once finish, no-speech error, final event, cancellation without finish, recognition failure, idempotence, and callback cleanup.

- [ ] **Step 5: Implement System runtime cleanup**

All stop/cancel/error/start-failure paths end the audio request, stop the engine, remove the tap, cancel task, clear owned objects, and deactivate `AVAudioSession`. Apple callbacks dispatch events on MainActor.

- [ ] **Step 6: Run recorder tests and confirm green**

### Task 3: Mutually exclusive Companion UI

**Files:**
- Modify: `ios/TodoNative/Views/CompanionView.swift`
- Modify: `ios/TodoNative/Localization/Localization.swift`
- Modify: `ios/TodoNativeTests/LocalizationTests.swift`

**Interfaces:**
- Consumes: Tasks 1–2 state/recorder.
- Produces: keyboard composer, voice composer, lifecycle cancellation, settings action, accessibility identifiers.

- [ ] **Step 1: Add failing zh/en voice key tests**

Require `common.ok`, error title, mode switch labels, cancel-and-switch label, start/recording/finalizing, Open Settings, two permission errors, recognition error, no speech, and transcript-ready copy.

- [ ] **Step 2: Implement the two composer branches**

Keyboard branch: `waveform` toggle + existing TextField + send. Voice branch: `keyboard` toggle + wide record button; use `ProgressView` only for requesting/finalizing and `stop.circle.fill` when recording.

Success handler:

```swift
let finalDraft = composer.finishRecording(transcript: transcript)
buddy.input = finalDraft
composerFocused = false
```

Do not call `buddy.send` from this path.

- [ ] **Step 3: Add lifecycle and accessibility behavior**

Cancel voice input on disappear and whenever scene phase leaves active. Set identifiers `companion.inputModeToggle`, `companion.composer`, `companion.send`, and `companion.voiceRecord`; use 44pt frames/content shapes and localized labels.

- [ ] **Step 4: Regenerate and verify focused/full tests**

Run:

```bash
cd ios && xcodegen generate
xcodebuild -project TodoNative.xcodeproj -scheme TodoNative -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=27.0' -only-testing:TodoNativeTests/CompanionComposerStateTests -only-testing:TodoNativeTests/CompanionVoiceRecorderTests -only-testing:TodoNativeTests/LocalizationTests test
xcodebuild -project TodoNative.xcodeproj -scheme TodoNative -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=27.0' test
```

Expected: tests pass; strict concurrency introduces no new warnings.
