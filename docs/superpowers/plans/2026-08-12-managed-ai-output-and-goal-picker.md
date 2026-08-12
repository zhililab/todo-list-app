# Managed AI Output Cap and Goal Picker Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Force managed AI completions to 2,048 tokens and let iOS users either type a breakdown goal or select an active task whose structured context is sent with the request.

**Architecture:** The Worker owns the managed-model output cap and overwrites every client value before the DeepSeek call. The iOS app adds a pure value snapshot for selected-task context, carries its fingerprint through workbench request provenance, and presents a searchable sheet backed by active `TodoItem` values without changing SwiftData. Worker deployment is verified before the iOS feature is packaged.

**Tech Stack:** Cloudflare Workers, JavaScript, Node test runner, Wrangler 4.120.1, Swift 5.10, SwiftUI, SwiftData, CryptoKit, XCTest, XcodeGen.

## Global Constraints

- Managed requests always use model `deepseek-v4-flash` and `max_tokens: 2048`.
- Free lifetime 10 and Pro daily 20 quota rules do not change.
- BYOK requests do not receive the managed output override.
- Goal selection appears only in `AIWorkbenchMode.breakdown`.
- Candidates must be unarchived, unfinished, and have a non-empty trimmed title.
- Selecting a task fills its title but the goal text remains editable.
- Editing goal text retains the selected task context until explicit clear, replacement, invalidation, or leaving breakdown mode.
- Selected task context is in-memory only; do not change the SwiftData schema.
- Do not log task content, prompts, responses, API keys, JWS values, or device identifiers.
- Discover an available physical device at runtime; never record its destination or CoreDevice identifier in tracked files.
- Preserve Dynamic Type, VoiceOver, Reduce Motion, light mode, and dark mode behavior.
- Do not change App Store subscription Product IDs in this feature.

---

## File Structure

- `workers/quota-proxy/src/contract.js`: defines and applies the managed completion-token cap.
- `workers/quota-proxy/test.mjs`: proves all client `max_tokens` variants become `2048` upstream.
- `workers/quota-proxy/README.md`: documents the enforced model and output cap.
- `ios/TodoNative/Models/AISelectedGoalContext.swift`: owns the selected-task value snapshot, eligibility, and stable fingerprint.
- `ios/TodoNative/Services/AIAssistantService.swift`: accepts selected context and serializes it into breakdown prompts only.
- `ios/TodoNative/ViewModels/AIBriefingViewModel.swift`: owns selected task ID, request provenance, reconciliation, and cancellation-safe execution.
- `ios/TodoNative/Components/AIGoalPicker.swift`: owns candidate filtering, sorting, search, grouped sheet UI, and selected summary UI.
- `ios/TodoNative/Components/AIWorkbenchResultView.swift`: compares selected-goal fingerprint when deciding whether a result is fresh.
- `ios/TodoNative/Views/AIWorkbenchView.swift`: connects the picker, task list, workbench execution, and sheet lifecycle.
- `ios/TodoNative/Localization/Localization.swift`: adds direct Simplified Chinese and English picker copy.
- `ios/TodoNativeTests/AISelectedGoalContextTests.swift`: validates snapshot eligibility and fingerprint dependencies.
- `ios/TodoNativeTests/AIGoalPickerPresentationTests.swift`: validates filtering, sorting, grouping, and search.
- `ios/TodoNativeTests/AIAssistantServiceTests.swift`: validates prompt inclusion and exclusion.
- `ios/TodoNativeTests/AIBriefingViewModelTests.swift`: validates selection lifecycle and provenance.
- `ios/TodoNativeTests/AIWorkbenchPresentationTests.swift`: validates selected-goal freshness.
- `ios/TodoNativeTests/LocalizationTests.swift`: prevents missing bilingual picker keys.

### Task 1: Enforce the Worker completion-token cap

**Files:**
- Modify: `workers/quota-proxy/test.mjs`
- Modify: `workers/quota-proxy/src/contract.js`
- Modify: `workers/quota-proxy/README.md`

**Interfaces:**
- Consumes: `parseChatBody(request: Request): Promise<object>` and the existing captured `lastUpstreamBody` test transport.
- Produces: exported `MAX_COMPLETION_TOKENS = 2048`; every parsed managed chat body contains `model: MANAGED_MODEL` and `max_tokens: MAX_COMPLETION_TOKENS`.

- [ ] **Step 1: Write the failing Worker contract test**

Add a table-driven test beside `client model is ignored and provider model is always deepseek-v4-flash`:

```js
test('managed requests force max_tokens to the fixed completion cap', async () => {
  const clientValues = [undefined, 8192, 128, 0, -1, '4096', null];
  for (const maxTokens of clientValues) {
    const { env } = makeEnv();
    const body = {
      messages: [{ role: 'user', content: 'make a short plan' }],
      ...(maxTokens === undefined ? {} : { max_tokens: maxTokens }),
    };
    assert.equal((await chatCompletions(env, chatReq(VALID_DEVICE_ID, body))).status, 200);
    assert.equal(lastUpstreamBody.max_tokens, 2048);
  }
});
```

- [ ] **Step 2: Run the focused Worker test to verify RED**

Run:

```bash
cd workers/quota-proxy
node --test --test-name-pattern='managed requests force max_tokens' test.mjs
```

Expected: FAIL because `lastUpstreamBody.max_tokens` is missing or preserves the client value.

- [ ] **Step 3: Implement the fixed override**

In `contract.js`, add the exported constant and overwrite the value after validation:

```js
export const MAX_COMPLETION_TOKENS = 2048;

export async function parseChatBody(request) {
  const body = await parseJsonObject(request);
  // Keep the existing message validation unchanged.
  return {
    ...body,
    model: MANAGED_MODEL,
    max_tokens: MAX_COMPLETION_TOKENS,
  };
}
```

Update `README.md` to state that both `model` and `max_tokens` are Worker-owned and cannot be changed by clients.

- [ ] **Step 4: Run Worker verification to verify GREEN**

Run:

```bash
cd workers/quota-proxy
node --test --test-name-pattern='managed requests force max_tokens|client model is ignored' test.mjs
node --test test.mjs
npx wrangler deploy --dry-run
cd ../..
node --test
```

Expected: focused tests pass; Worker suite and root suite pass; dry-run lists `QUOTA`, `ENTITLEMENTS`, and `DEVICE_PRIVACY` with migrations `v1` and `v2`.

- [ ] **Step 5: Commit the Worker guard**

```bash
git add workers/quota-proxy/src/contract.js workers/quota-proxy/test.mjs workers/quota-proxy/README.md
git commit -m 'fix(worker): cap managed AI completion tokens'
```

### Task 2: Add selected-task context and remote prompt serialization

**Files:**
- Create: `ios/TodoNative/Models/AISelectedGoalContext.swift`
- Create: `ios/TodoNativeTests/AISelectedGoalContextTests.swift`
- Modify: `ios/TodoNative/Services/AIAssistantService.swift`
- Modify: `ios/TodoNativeTests/AIAssistantServiceTests.swift`

**Interfaces:**
- Consumes: `TodoItem`, `AIWorkbenchMode`, `AIAssistantContext`, `AIAssistantServing`.
- Produces: `AISelectedGoalContext`, `AISelectedGoalContext.init?(item:)`, `fingerprint: String`, `promptJSON: String`, and `AIAssistantServing.workbench(mode:goal:selectedGoal:context:now:intent:)`.

- [ ] **Step 1: Write failing context-model tests**

Create `AISelectedGoalContextTests.swift` with fixed dates and UUIDs. Cover active eligibility, completed/archived/blank rejection, and every fingerprint field:

```swift
func testActiveTaskCreatesStructuredSelectedGoalContext() throws {
    let item = TodoItem(
        title: "发布 1.0",
        context: "面向首批用户",
        acceptanceCriteria: "TestFlight 通过",
        nextPrompt: "列出发布检查项",
        taskType: .product,
        estimatedMinutes: 45,
        priority: 5,
        status: .doing,
        dueDate: Date(timeIntervalSince1970: 1_786_291_200)
    )
    let selected = try XCTUnwrap(AISelectedGoalContext(item: item))
    XCTAssertEqual(selected.id, item.id)
    XCTAssertEqual(selected.title, "发布 1.0")
    XCTAssertEqual(selected.context, "面向首批用户")
    XCTAssertEqual(selected.acceptanceCriteria, "TestFlight 通过")
    XCTAssertEqual(selected.nextPrompt, "列出发布检查项")
    XCTAssertEqual(selected.taskType, TaskType.product.rawValue)
    XCTAssertEqual(selected.priority, 5)
    XCTAssertEqual(selected.estimatedMinutes, 45)
    XCTAssertEqual(selected.dueDate, item.dueDate)
}
```

Use a helper that clones one selected value while changing exactly one of title, context, acceptance criteria, next prompt, type, priority, minutes, or due date; assert every mutation changes `fingerprint`.

- [ ] **Step 2: Run model tests to verify RED**

Run:

```bash
cd ios
xcodegen generate
xcodebuild -project TodoNative.xcodeproj -scheme TodoNative -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=27.0' -only-testing:TodoNativeTests/AISelectedGoalContextTests test
```

Expected: compile failure because `AISelectedGoalContext` does not exist.

- [ ] **Step 3: Implement the immutable selected context**

Create `AISelectedGoalContext.swift` as a `Codable`, `Equatable`, `Sendable` value. The failable initializer must trim the title and reject archived/done/blank items. Encode a private payload with `JSONEncoder.outputFormatting = [.sortedKeys]`; encode dates using `timeIntervalSince1970.bitPattern`; hash with SHA-256 exactly as the existing assistant context does.

Expose deterministic JSON for the remote prompt:

```swift
struct AISelectedGoalContext: Codable, Equatable, Sendable {
    let id: UUID
    let title: String
    let context: String
    let acceptanceCriteria: String
    let nextPrompt: String
    let taskType: String
    let priority: Int
    let estimatedMinutes: Int
    let dueDate: Date?

    init?(item: TodoItem) {
        let title = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !item.isArchived, !item.isCompleted, !title.isEmpty else { return nil }
        id = item.id
        self.title = title
        context = item.context
        acceptanceCriteria = item.acceptanceCriteria
        nextPrompt = item.nextPrompt
        taskType = item.taskTypeRaw
        priority = item.priority
        estimatedMinutes = item.estimatedMinutes
        dueDate = item.dueDate
    }
}
```

- [ ] **Step 4: Write failing service boundary tests**

Update the transport spy in `AIAssistantServiceTests.swift`. Add assertions that breakdown with a selected task includes a `selectedTask=` JSON line containing all structured fields, while today plan, review, and free-input breakdown omit that line. Also assert the prompt contains no object memory address or `Optional(...)` rendering.

- [ ] **Step 5: Run service tests to verify RED**

Run:

```bash
cd ios
xcodegen generate
xcodebuild -project TodoNative.xcodeproj -scheme TodoNative -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=27.0' -only-testing:TodoNativeTests/AIAssistantServiceTests test
```

Expected: compile failures because the protocol and live service do not accept `selectedGoal`.

- [ ] **Step 6: Extend the service protocol and prompt**

Change the protocol and implementations to the exact signature:

```swift
func workbench(
    mode: AIWorkbenchMode,
    goal: String,
    selectedGoal: AISelectedGoalContext?,
    context: AIAssistantContext,
    now: Date,
    intent: RemoteAIRequestIntent
) async throws -> AIWorkbenchResult
```

In `LiveAIAssistantService`, append `selectedTask=<canonical JSON>` only when `mode == .breakdown` and `selectedGoal != nil`. Pass `nil` from all existing non-picker call sites and test fakes until Task 3 connects the selection.

- [ ] **Step 7: Run model and service tests to verify GREEN**

Run:

```bash
cd ios
xcodegen generate
xcodebuild -project TodoNative.xcodeproj -scheme TodoNative -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=27.0' -only-testing:TodoNativeTests/AISelectedGoalContextTests -only-testing:TodoNativeTests/AIAssistantServiceTests test
```

Expected: all selected-context and service tests pass.

- [ ] **Step 8: Commit the domain and service boundary**

```bash
git add ios/TodoNative/Models/AISelectedGoalContext.swift ios/TodoNative/Services/AIAssistantService.swift ios/TodoNativeTests/AISelectedGoalContextTests.swift ios/TodoNativeTests/AIAssistantServiceTests.swift ios/TodoNative.xcodeproj/project.pbxproj
git commit -m 'feat(ai): carry selected task context into breakdowns'
```

### Task 3: Make selection lifecycle and provenance deterministic

**Files:**
- Modify: `ios/TodoNative/ViewModels/AIBriefingViewModel.swift`
- Modify: `ios/TodoNative/Components/AIWorkbenchResultView.swift`
- Modify: `ios/TodoNativeTests/AIBriefingViewModelTests.swift`
- Modify: `ios/TodoNativeTests/AIWorkbenchPresentationTests.swift`

**Interfaces:**
- Consumes: `AISelectedGoalContext.init?(item:)` and the extended service method from Task 2.
- Produces: `selectedGoalTaskID: UUID?`, `selectGoalTask(_:)`, `clearSelectedGoalTask()`, `reconcileSelectedGoal(in:)`, `selectedGoalContext(in:)`, and provenance field `selectedGoalFingerprint: String?`.

- [ ] **Step 1: Write failing ViewModel selection tests**

Add tests that prove:

```swift
func testSelectingTaskFillsEditableGoalAndRetainsSelectionAfterTextEdit() {
    let vm = makeViewModel()
    vm.mode = .breakdown
    let item = activeItem(title: "发布 1.0")
    vm.selectGoalTask(item)
    XCTAssertEqual(vm.selectedGoalTaskID, item.id)
    XCTAssertEqual(vm.goal, "发布 1.0")

    vm.goal = "先发布 iOS 版本"
    XCTAssertEqual(vm.selectedGoalTaskID, item.id)
}
```

Also cover explicit clear preserving goal text, replacement, leaving breakdown mode, completed/archived/deleted invalidation, blank goal restoration from the selected title, and consent retry preserving the same selected snapshot.

- [ ] **Step 2: Write failing provenance tests**

Run a successful breakdown with a selected task, mutate only its `acceptanceCriteria`, rebuild the current selected context, and assert `AIWorkbenchSessionPresentation.isFresh == false` and imports are empty. Assert editing only the goal text also remains stale under the existing goal provenance rule.

- [ ] **Step 3: Run focused tests to verify RED**

Run:

```bash
cd ios
xcodegen generate
xcodebuild -project TodoNative.xcodeproj -scheme TodoNative -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=27.0' -only-testing:TodoNativeTests/AIBriefingViewModelTests -only-testing:TodoNativeTests/AIWorkbenchPresentationTests test
```

Expected: compile failures for the selection API and selected-goal fingerprint.

- [ ] **Step 4: Implement selection ownership and request snapshotting**

Add:

```swift
@Published private(set) var selectedGoalTaskID: UUID?

func selectGoalTask(_ item: TodoItem) {
    guard mode == .breakdown, let selected = AISelectedGoalContext(item: item) else { return }
    invalidateWorkbench()
    selectedGoalTaskID = selected.id
    goal = selected.title
}

func clearSelectedGoalTask() {
    guard selectedGoalTaskID != nil else { return }
    selectedGoalTaskID = nil
    invalidateWorkbench()
}
```

Keep `invalidateWorkbench()` from clearing `selectedGoalTaskID`; mode changes and explicit selection APIs own selection clearing. In `runWorkbench`, resolve the latest item, restore a blank goal from its title, and construct `AIWorkbenchRequest` with `selectedGoal: AISelectedGoalContext?`.

Extend request and provenance:

```swift
struct AIWorkbenchProvenance: Equatable, Sendable {
    let mode: AIWorkbenchMode
    let goal: String
    let contextFingerprint: String
    let selectedGoalFingerprint: String?
}

struct AIWorkbenchRequest: Equatable, Sendable {
    let id: UUID
    let mode: AIWorkbenchMode
    let goal: String
    let contextFingerprint: String
    let selectedGoal: AISelectedGoalContext?
}
```

- [ ] **Step 5: Thread fingerprint through freshness and import guards**

Add `currentSelectedGoalFingerprint: String?` to `AIWorkbenchSessionPresentation.init`. Include it in every provenance comparison in presentation, `selectedTasksForImport`, and `selectedTasksForApplication`. Store `request.selectedGoal?.fingerprint` in the completed session. Pass the selected context to `service.workbench` and preserve it inside `PendingConsentRequest.workbench` through the request value.

- [ ] **Step 6: Run focused tests to verify GREEN**

Run:

```bash
cd ios
xcodegen generate
xcodebuild -project TodoNative.xcodeproj -scheme TodoNative -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=27.0' -only-testing:TodoNativeTests/AIBriefingViewModelTests -only-testing:TodoNativeTests/AIWorkbenchPresentationTests test
```

Expected: selection lifecycle, cancellation, consent retry, provenance, retained-result, and import tests all pass.

- [ ] **Step 7: Commit the state machine**

```bash
git add ios/TodoNative/ViewModels/AIBriefingViewModel.swift ios/TodoNative/Components/AIWorkbenchResultView.swift ios/TodoNativeTests/AIBriefingViewModelTests.swift ios/TodoNativeTests/AIWorkbenchPresentationTests.swift
git commit -m 'feat(ai): track selected breakdown goals safely'
```

### Task 4: Build the searchable existing-task picker

**Files:**
- Create: `ios/TodoNative/Components/AIGoalPicker.swift`
- Create: `ios/TodoNativeTests/AIGoalPickerPresentationTests.swift`
- Modify: `ios/TodoNative/Views/AIWorkbenchView.swift`
- Modify: `ios/TodoNative/Localization/Localization.swift`
- Modify: `ios/TodoNativeTests/LocalizationTests.swift`

**Interfaces:**
- Consumes: `TodoItem`, `AIBriefingViewModel.selectGoalTask`, `clearSelectedGoalTask`, and `selectedGoalTaskID`.
- Produces: `AIGoalPickerCandidate`, `AIGoalPickerPresentation`, `AIGoalPicker`, and `AISelectedGoalSummary`.

- [ ] **Step 1: Write failing pure presentation tests**

Create candidates representing doing, todo, done, archived, blank-title, different priorities, due dates, and update times. Assert exact candidate order and grouping. Search each of title, context, acceptance criteria, next prompt, and source goal with mixed case and surrounding whitespace.

```swift
func testCandidatesFilterGroupAndSortDeterministically() {
    let presentation = AIGoalPickerPresentation(items: fixtures, query: "")
    XCTAssertEqual(presentation.doing.map(\.id), [doingHigh.id, doingLow.id])
    XCTAssertEqual(presentation.todo.map(\.id), [dueSoon.id, dueLater.id, noDue.id])
    XCTAssertFalse(presentation.all.contains(where: { $0.id == done.id }))
    XCTAssertFalse(presentation.all.contains(where: { $0.id == archived.id }))
}
```

- [ ] **Step 2: Run picker presentation tests to verify RED**

Run:

```bash
cd ios
xcodegen generate
xcodebuild -project TodoNative.xcodeproj -scheme TodoNative -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=27.0' -only-testing:TodoNativeTests/AIGoalPickerPresentationTests test
```

Expected: compile failure because picker presentation types do not exist.

- [ ] **Step 3: Implement candidate filtering, search, and sorting**

Define an immutable candidate copied from `TodoItem`. The comparator must apply, in order: doing before todo, priority descending, non-nil due date before nil, due date ascending, updated date descending, UUID string ascending. Normalize search with `trimmingCharacters(in:)` and `localizedCaseInsensitiveContains` over the five approved text fields.

- [ ] **Step 4: Implement the SwiftUI sheet and selected summary**

`AIGoalPicker` owns `@State private var query = ""`, renders `searchable`, a “direct input” action, and separate doing/todo sections. Each row shows title, localized task type, priority, and localized due date. Use `ViewThatFits` or a vertical layout for accessibility sizes; use semantic app colors and minimum 44-point controls.

`AISelectedGoalSummary` renders the selected title with “Change” and “Clear” actions and combines its accessibility children.

- [ ] **Step 5: Connect the picker to the workbench**

In `AIWorkbenchView`, add `@State private var isGoalPickerPresented = false`. Compute `AIGoalPickerPresentation(items: vm.items, query: "")` and the selected item by exact UUID. In `promptCard`, render the picker entry or selected summary only for `.breakdown`, before the existing editable `TextField`. Present the sheet and call `briefing.selectGoalTask(item)` after revalidating against the latest `vm.items`; direct input calls `clearSelectedGoalTask()`.

Before building `assistantContext`, call reconciliation through view lifecycle when task IDs/status/archive values change, without mutating state from a computed property. Use `.onChange(of: goalCandidateRevision)` where the revision is a stable string derived from candidate IDs, status, archive, and updated timestamps.

- [ ] **Step 6: Add direct bilingual localization keys**

Add Simplified Chinese and English keys for picker title, search placeholder, choose existing task, direct input, selected task, change, clear, doing, todo, empty state, priority, due date, and VoiceOver selection status. Extend `LocalizationTests.requiredDirectKeys` so both dictionaries must contain every new key.

- [ ] **Step 7: Run picker and localization tests to verify GREEN**

Run:

```bash
cd ios
xcodegen generate
xcodebuild -project TodoNative.xcodeproj -scheme TodoNative -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=27.0' -only-testing:TodoNativeTests/AIGoalPickerPresentationTests -only-testing:TodoNativeTests/LocalizationTests -only-testing:TodoNativeTests/AIBriefingViewModelTests -only-testing:TodoNativeTests/AIWorkbenchPresentationTests test
```

Expected: all picker, localization, selection, and provenance tests pass.

- [ ] **Step 8: Commit the picker UI**

```bash
git add ios/TodoNative/Components/AIGoalPicker.swift ios/TodoNative/Views/AIWorkbenchView.swift ios/TodoNative/Localization/Localization.swift ios/TodoNativeTests/AIGoalPickerPresentationTests.swift ios/TodoNativeTests/LocalizationTests.swift ios/TodoNative.xcodeproj/project.pbxproj
git commit -m 'feat(ios): add searchable breakdown goal picker'
```

### Task 5: Complete regression, deployment, and device validation

**Files:**
- Modify only if evidence needs correction: `workers/quota-proxy/README.md`
- Modify only if release evidence is recorded: `ios/AppStoreConnect/release-evidence.md`

**Interfaces:**
- Consumes: Tasks 1–4 complete and committed.
- Produces: green repository verification, online Worker evidence, simulator builds, and a real-device build with the picker.

- [ ] **Step 1: Regenerate the Xcode project and run full local verification**

```bash
cd ios
xcodegen generate
xcodebuild -project TodoNative.xcodeproj -scheme TodoNative -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=27.0' test
xcodebuild -project TodoNative.xcodeproj -scheme TodoNative -configuration Debug -destination 'generic/platform=iOS Simulator' build
xcodebuild -project TodoNative.xcodeproj -scheme TodoNative -configuration Release -destination 'generic/platform=iOS Simulator' build
cd ..
node --test
cd workers/quota-proxy
node --test test.mjs
npm audit --omit=dev
npx wrangler deploy --dry-run
```

Expected: complete iOS, root Node, and Worker suites pass; Debug and Release builds succeed; audit reports zero vulnerabilities; Wrangler dry-run succeeds.

- [ ] **Step 2: Fetch before external deployment**

```bash
git fetch origin
git status --short
git rev-list --left-right --count HEAD...origin/master
```

Expected: unrelated `.superpowers/` and pre-existing untracked plan files remain unstaged; if remote is ahead, rebase the feature commits before deployment.

- [ ] **Step 3: Record the current healthy Worker version and deploy production**

```bash
cd workers/quota-proxy
npx wrangler deployments list --name todo-quota-proxy --json
npx wrangler deploy --name todo-quota-proxy
npx wrangler deployments list --name todo-quota-proxy --json
```

Expected: deployment succeeds with existing `QUOTA`, `ENTITLEMENTS`, and `DEVICE_PRIVACY` bindings; no secret values are printed or changed.

- [ ] **Step 4: Deploy the existing Sandbox Worker and verify both routes**

```bash
npx wrangler deploy --name todo-quota-proxy-sandbox
curl -sS -o /dev/null -w '%{http_code}\n' https://todo-quota-proxy.todo-quota-proxy.workers.dev/proxy/quota
curl -sS -o /dev/null -w '%{http_code}\n' https://todo-quota-proxy-sandbox.todo-quota-proxy.workers.dev/proxy/quota
```

Expected: both routes respond; unauthenticated quota probes return the stable authentication error rather than `404`, `500`, or an HTML page. Do not send a real DeepSeek request merely to inspect `max_tokens`; rely on the contract test and deployed version hash.

- [ ] **Step 5: Build, install, and launch on the registered iPhone**

```bash
cd ../../ios
xcodebuild -project TodoNative.xcodeproj -scheme TodoNative -showdestinations
xcrun devicectl list devices
xcodebuild -project TodoNative.xcodeproj -scheme TodoNative -destination 'id=<AVAILABLE_XCODE_DESTINATION_ID>' -derivedDataPath build/dd build
xcrun devicectl device install app --device <AVAILABLE_COREDEVICE_ID> build/dd/Build/Products/Debug-iphoneos/TodoNative.app
xcrun devicectl device process launch --device <AVAILABLE_COREDEVICE_ID> com.zhili.todo-native
```

Expected: choose an available paired device from the fresh command output; build, installation, and launch succeed. Keep both discovered identifiers out of tracked files and reports.

- [ ] **Step 6: Perform the real-device acceptance matrix**

On the iPhone:

1. Open AI Workbench → Breakdown.
2. Confirm direct free input still generates.
3. Open the picker, search a captured task by title and by context, and select it.
4. Edit the filled title and confirm the selected-task summary remains.
5. Change the source task acceptance criteria, return to the result, and confirm it is marked stale and cannot import.
6. Clear selection and confirm the edited text remains.
7. Switch to Today Plan and Review; confirm no picker appears.
8. Repeat in Dark Mode, accessibility text size, VoiceOver, and Reduce Motion.

Expected: every interaction matches the approved design and no task is modified merely by selecting it.

- [ ] **Step 7: Hand off verified commits for final branch review**

Inspect the logical implementation commits and record the exact verified HEAD. Preserve Worker guard, shared AI state/service, and iOS UI as no more than three implementation commits plus the existing design/plan documentation. Do not rebase or push from this task: the controller must first run the required broad whole-branch review, address its findings, rerun affected verification, and only then consolidate history and push.

```bash
git log --oneline origin/master..HEAD
git status --short
git diff --check origin/master..HEAD
```

Expected: the verified commit range is explicit, diff checking passes, and unrelated untracked files remain excluded. Final review and push remain pending.
