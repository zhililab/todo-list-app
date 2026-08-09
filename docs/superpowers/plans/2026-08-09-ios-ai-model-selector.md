# iOS AI Model Selector Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add provider-specific preset model selection plus custom model input, migrate legacy preferences safely, and repair the obsolete managed DeepSeek model.

**Architecture:** `OpenAIService` owns a typed provider/model catalog and provider-scoped persistence. `AIViewModel` exposes selection state for Settings. Managed quota remains a single fixed model, updated consistently in Worker, Web copy/request, and iOS.

**Tech Stack:** Swift 5.10, SwiftUI, XCTest, JavaScript Worker, Node test runner

## Global Constraints

- Preset catalogs use only model IDs verified against official provider documentation on 2026-08-09.
- Selecting one provider must not overwrite another provider's selection or custom value.
- Custom Base URL is required only for the Custom provider.
- Managed quota remains fixed-model and must say so explicitly.
- Worker model compatibility repair is allowed; multi-model proxying is out of scope.

---

### Task 1: Typed provider catalog and scoped persistence

**Files:**
- Modify: `ios/TodoNative/Services/OpenAIService.swift`
- Modify: `ios/TodoNativeTests/OpenAIServiceTests.swift`

**Interfaces:**
- Produces: `AIModelOption`, `AIModelSelection`, provider `models/defaultModelID`, scoped storage helpers.
- Consumes: `UserDefaults`.

- [ ] **Step 1: Add failing catalog and isolation tests**

```swift
func testDeepSeekUsesCurrentV4Models() {
    XCTAssertEqual(AIProvider.provider(id: "deepseek").models.map(\.id), [
        "deepseek-v4-flash", "deepseek-v4-pro"
    ])
}

func testProviderSelectionsAreIndependent() {
    OpenAIService.saveModelSelection(.preset("gpt-5-mini"), providerID: "openai")
    OpenAIService.saveModelSelection(.custom, providerID: "deepseek")
    XCTAssertEqual(OpenAIService.modelSelection(providerID: "openai"), .preset("gpt-5-mini"))
    XCTAssertEqual(OpenAIService.modelSelection(providerID: "deepseek"), .custom)
}
```

Also test Custom Base URL validation, legacy `ai_model`/`ai_base_url` one-time migration, unknown preset fallback, and active config.

- [ ] **Step 2: Run focused tests and confirm red**

Run: `xcodebuild -project ios/TodoNative.xcodeproj -scheme TodoNative -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=27.0' -only-testing:TodoNativeTests/OpenAIServiceTests test`

- [ ] **Step 3: Implement the typed catalog**

```swift
struct AIModelOption: Identifiable, Equatable {
    let id: String
    let displayName: String
}

enum AIModelSelection: Equatable {
    case preset(String)
    case custom
}
```

Use provider-scoped keys `ai_model_selection.<id>`, `ai_custom_model.<id>`, and `ai_custom_base_url.<id>`. Store selection as `preset:<modelID>` or `custom`; perform legacy migration behind one boolean migration key.

- [ ] **Step 4: Run focused tests and confirm green**

### Task 2: ViewModel and native Settings selector

**Files:**
- Modify: `ios/TodoNative/ViewModels/AIViewModel.swift`
- Modify: `ios/TodoNative/Views/SettingsView.swift`
- Modify: `ios/TodoNative/Localization/Localization.swift`
- Modify: `ios/TodoNativeTests/LocalizationTests.swift`

**Interfaces:**
- Consumes: Task 1 catalog and persistence.
- Produces: `modelSelection`, `availableModels`, `usesCustomModel`, `showsCustomBaseURL`, provider reload behavior.

- [ ] **Step 1: Add failing zh/en key tests**

Require keys for Custom, managed fixed model, model selector hint, custom model placeholder, and custom Base URL explanation.

- [ ] **Step 2: Implement provider-change reload**

On `providerID.didSet`, persist provider then load that provider's selection/model/Base URL without writing the previous provider values into the new keys. Use an `isLoadingProviderConfiguration` guard around published `didSet` persistence.

- [ ] **Step 3: Replace free-form rows with native selection**

```swift
Picker(Localization.t("ai.model"), selection: $aiVM.modelSelection) {
    ForEach(aiVM.availableModels) { option in
        Text(option.displayName).tag(AIModelSelection.preset(option.id))
    }
    Text(Localization.t("ai.model.custom")).tag(AIModelSelection.custom)
}
.pickerStyle(.navigationLink)
```

Show model TextField only for `.custom`; show Base URL only when `providerID == "custom"`; show managed fixed-model copy when API Key is empty.

- [ ] **Step 4: Run OpenAI and localization tests**

Expected: focused targets pass and switching providers restores independent choices.

### Task 3: Managed DeepSeek compatibility repair

**Files:**
- Modify: `workers/quota-proxy/src/index.js`
- Modify: `workers/quota-proxy/test.mjs`
- Modify: `app.js`
- Modify: `ios/TodoNative/Services/OpenAIService.swift`
- Modify: `ios/TodoNative/Services/QuotaClient.swift`
- Modify: `ios/TodoNativeTests/OpenAIServiceTests.swift`
- Modify: `ios/TodoNativeTests/QuotaClientTests.swift`

**Interfaces:**
- Produces: one shared behavior—managed requests resolve to `deepseek-v4-flash`.

- [ ] **Step 1: Add failing Worker/iOS assertions**

Assert Worker overwrites an incoming model to `deepseek-v4-flash`, iOS managed body uses that ID, and stale user-facing hints no longer mention `deepseek-chat`.

- [ ] **Step 2: Run current Worker/Web/iOS focused tests and confirm red**

Run:

```bash
cd workers/quota-proxy && npm test
cd ../.. && node --test
xcodebuild -project ios/TodoNative.xcodeproj -scheme TodoNative -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=27.0' -only-testing:TodoNativeTests/OpenAIServiceTests -only-testing:TodoNativeTests/QuotaClientTests test
```

- [ ] **Step 3: Replace the obsolete fixed identifier and copy**

Set every managed quota request/override/hint/comment to `deepseek-v4-flash`; do not alter direct custom-key calls.

- [ ] **Step 4: Run all three suites and confirm green**

Expected: Worker, Web, and focused iOS tests pass.
