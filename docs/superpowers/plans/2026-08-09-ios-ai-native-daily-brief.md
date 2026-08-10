# iOS AI-Native Daily Brief Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make AI continuously visible and actionable on the iOS Today screen through a cached daily briefing and a structured three-mode AI workbench.

**Architecture:** Add pure assistant domain models and a deterministic task-context fingerprint, place remote/local generation behind `AIAssistantServing`, and keep daily cache/refresh/import behavior in a dedicated `AIBriefingViewModel`. The Today screen consumes a focused briefing card while the sheet consumes the same environment object, so both surfaces share one state machine and never modify tasks without explicit confirmation.

**Tech Stack:** Swift 5, SwiftUI, SwiftData, CryptoKit, UserDefaults, XCTest, XcodeGen, iOS 17+

## Global Constraints

- The Today screen order is AI Daily Brief, Execution Status, Today Plan.
- Generate automatically only once per calendar day; changed task context marks the current brief stale but never triggers a second automatic request.
- AI must never modify, delete, reorder, or import tasks without a user action.
- Managed quota and custom API keys use the same UI; provider and model configuration remain in Settings.
- Remote decode failures and ordinary provider/network errors fall back to local structured output; quota exhaustion remains an explicit recoverable error.
- All motion respects Reduce Motion, all controls have a minimum 44×44pt target, and layouts support Dynamic Type.
- Do not log API keys, full prompts, or full task bodies.
- Every new user-facing string must exist in Chinese and English.

---

## File Map

- Create `ios/TodoNative/Models/AIAssistantModels.swift`: assistant modes, context snapshots, daily brief, suggested tasks, results, and deterministic fingerprint.
- Create `ios/TodoNative/Services/AIBriefCache.swift`: cache protocol and UserDefaults implementation.
- Create `ios/TodoNative/Services/AIAssistantService.swift`: service protocol, live adapter, JSON decode, and local structured fallback.
- Create `ios/TodoNative/ViewModels/AIBriefingViewModel.swift`: daily refresh policy, state machines, selection, deduplication, and import preparation.
- Create `ios/TodoNative/Components/AIDailyBriefCard.swift`: Today-screen briefing card and accessible states.
- Modify `ios/TodoNative/Views/DashboardView.swift`: insert the card, replace the hidden AI entry, and route quick actions.
- Replace `ios/TodoNative/Views/AIWorkbenchView.swift`: three-mode continuous workbench and structured result UI.
- Modify `ios/TodoNative/TodoNativeApp.swift`: create and inject one shared `AIBriefingViewModel`.
- Modify `ios/TodoNative/Localization/Localization.swift`: Chinese/English briefing and workbench copy.
- Add focused tests under `ios/TodoNativeTests/` for models, cache, service fallback, view-model policy, presentation, and localization.

---

### Task 1: Assistant Domain Models and Context Fingerprint

**Files:**
- Create: `ios/TodoNative/Models/AIAssistantModels.swift`
- Create: `ios/TodoNativeTests/AIAssistantModelsTests.swift`

**Interfaces:**
- Consumes: `TodoItem`, `TodoStatus`, `TaskType`.
- Produces: `AIWorkbenchMode`, `AIAssistantSource`, `AIAssistantContext`, `AIDailyBriefContent`, `AIDailyBrief`, `AISuggestedTask`, `AIResultSection`, `AIWorkbenchResult`.

- [ ] **Step 1: Write failing model and fingerprint tests**

```swift
import XCTest
@testable import TodoNative

final class AIAssistantModelsTests: XCTestCase {
    func testFingerprintIsStableAcrossItemOrder() {
        let a = AIAssistantTaskSnapshot(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, title: "发布", status: "todo", priority: 4, estimatedMinutes: 30, dueDate: Date(timeIntervalSince1970: 100), isArchived: false)
        let b = AIAssistantTaskSnapshot(id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!, title: "复盘", status: "doing", priority: 2, estimatedMinutes: 20, dueDate: nil, isArchived: false)
        XCTAssertEqual(AIAssistantContext(tasks: [a, b], health: 58).fingerprint, AIAssistantContext(tasks: [b, a], health: 58).fingerprint)
    }

    func testFingerprintChangesForRelevantTaskState() {
        let id = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let todo = AIAssistantTaskSnapshot(id: id, title: "发布", status: "todo", priority: 4, estimatedMinutes: 30, dueDate: nil, isArchived: false)
        let done = AIAssistantTaskSnapshot(id: id, title: "发布", status: "done", priority: 4, estimatedMinutes: 30, dueDate: nil, isArchived: false)
        XCTAssertNotEqual(AIAssistantContext(tasks: [todo], health: 58).fingerprint, AIAssistantContext(tasks: [done], health: 58).fingerprint)
    }

    func testModesExposeStableIDs() {
        XCTAssertEqual(AIWorkbenchMode.allCases.map(\.id), ["todayPlan", "breakdown", "review"])
    }
}
```

- [ ] **Step 2: Run the test and verify RED**

Run:

```bash
cd ios && xcodegen generate && xcodebuild -project TodoNative.xcodeproj -scheme TodoNative -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=27.0' -only-testing:TodoNativeTests/AIAssistantModelsTests test
```

Expected: compilation fails because the assistant model types do not exist.

- [ ] **Step 3: Implement the pure assistant models**

```swift
import CryptoKit
import Foundation

enum AIWorkbenchMode: String, CaseIterable, Codable, Identifiable {
    case todayPlan
    case breakdown
    case review
    var id: String { rawValue }
}

enum AIAssistantSource: String, Codable, Equatable {
    case managed
    case custom
    case local
}

struct AIAssistantTaskSnapshot: Codable, Equatable {
    let id: UUID
    let title: String
    let status: String
    let priority: Int
    let estimatedMinutes: Int
    let dueDate: Date?
    let isArchived: Bool
}

struct AIAssistantContext: Equatable {
    let tasks: [AIAssistantTaskSnapshot]
    let health: Int

    init(tasks: [AIAssistantTaskSnapshot], health: Int) {
        self.tasks = tasks
        self.health = health
    }

    init(items: [TodoItem], health: Int) {
        tasks = items.map {
            AIAssistantTaskSnapshot(id: $0.id, title: $0.title, status: $0.statusRaw, priority: $0.priority, estimatedMinutes: $0.estimatedMinutes, dueDate: $0.dueDate, isArchived: $0.isArchived)
        }
        self.health = health
    }

    var fingerprint: String {
        let rows = tasks.sorted { $0.id.uuidString < $1.id.uuidString }.map {
            [$0.id.uuidString, $0.title, $0.status, String($0.priority), String($0.estimatedMinutes), $0.dueDate.map { String($0.timeIntervalSince1970) } ?? "-", String($0.isArchived)].joined(separator: "|")
        }
        let payload = (["health=\(health)"] + rows).joined(separator: "\n")
        return SHA256.hash(data: Data(payload.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

struct AIDailyBriefContent: Codable, Equatable {
    let summary: String
    let detail: String
    let evidence: [String]
}

struct AIDailyBrief: Codable, Equatable {
    let content: AIDailyBriefContent
    let generatedAt: Date
    let source: AIAssistantSource
    let contextFingerprint: String
}

struct AISuggestedTask: Codable, Equatable, Identifiable {
    let id: UUID
    let title: String
    let rationale: String
    let estimatedMinutes: Int?
    let priority: Int?
    let dueDate: Date?
}

struct AIResultSection: Codable, Equatable, Identifiable {
    let id: String
    let title: String
    let body: String
}

struct AIWorkbenchResult: Codable, Equatable {
    let overview: String
    let suggestedTasks: [AISuggestedTask]
    let sections: [AIResultSection]
    let source: AIAssistantSource
}
```

- [ ] **Step 4: Run focused tests and verify GREEN**

Run the Step 2 command. Expected: `AIAssistantModelsTests` passes.

- [ ] **Step 5: Commit the task**

```bash
git add ios/TodoNative/Models/AIAssistantModels.swift ios/TodoNativeTests/AIAssistantModelsTests.swift ios/TodoNative.xcodeproj/project.pbxproj
git commit -m "feat(ai): add assistant domain models"
```

---

### Task 2: Daily Brief Cache and Refresh Policy Inputs

**Files:**
- Create: `ios/TodoNative/Services/AIBriefCache.swift`
- Create: `ios/TodoNativeTests/AIBriefCacheTests.swift`

**Interfaces:**
- Consumes: `AIDailyBrief` from Task 1.
- Produces: `AIBriefCaching`, `UserDefaultsAIBriefCache`, `AIBriefDayKey.value(for:calendar:)`.

- [ ] **Step 1: Write failing cache isolation tests**

```swift
import XCTest
@testable import TodoNative

final class AIBriefCacheTests: XCTestCase {
    func testRoundTripIsScopedByCalendarDay() throws {
        let suite = "AIBriefCacheTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let cache = UserDefaultsAIBriefCache(defaults: defaults)
        let brief = AIDailyBrief(content: .init(summary: "先发布", detail: "保护截止任务", evidence: ["1 个截止"]), generatedAt: Date(timeIntervalSince1970: 10), source: .local, contextFingerprint: "abc")
        cache.save(brief, for: "2026-08-09")
        XCTAssertEqual(cache.load(for: "2026-08-09"), brief)
        XCTAssertNil(cache.load(for: "2026-08-10"))
        defaults.removePersistentDomain(forName: suite)
    }

    func testDayKeyUsesProvidedCalendar() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        XCTAssertEqual(AIBriefDayKey.value(for: Date(timeIntervalSince1970: 1786233600), calendar: calendar), "2026-08-09")
    }
}
```

- [ ] **Step 2: Run the test and verify RED**

Run the iOS focused command with `-only-testing:TodoNativeTests/AIBriefCacheTests`. Expected: missing cache types.

- [ ] **Step 3: Implement cache protocol and UserDefaults storage**

```swift
import Foundation

protocol AIBriefCaching {
    func load(for dayKey: String) -> AIDailyBrief?
    func save(_ brief: AIDailyBrief, for dayKey: String)
}

enum AIBriefDayKey {
    static func value(for date: Date, calendar: Calendar = .current) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }
}

final class UserDefaultsAIBriefCache: AIBriefCaching {
    private let defaults: UserDefaults
    private let prefix = "ai_daily_brief."

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    func load(for dayKey: String) -> AIDailyBrief? {
        guard let data = defaults.data(forKey: prefix + dayKey) else { return nil }
        return try? JSONDecoder().decode(AIDailyBrief.self, from: data)
    }

    func save(_ brief: AIDailyBrief, for dayKey: String) {
        guard let data = try? JSONEncoder().encode(brief) else { return }
        defaults.set(data, forKey: prefix + dayKey)
    }
}
```

- [ ] **Step 4: Run focused tests and verify GREEN**

Expected: both cache tests pass.

- [ ] **Step 5: Commit the task**

```bash
git add ios/TodoNative/Services/AIBriefCache.swift ios/TodoNativeTests/AIBriefCacheTests.swift ios/TodoNative.xcodeproj/project.pbxproj
git commit -m "feat(ai): cache daily brief by day"
```

---

### Task 3: Structured Assistant Service and Local Fallback

**Files:**
- Create: `ios/TodoNative/Services/AIAssistantService.swift`
- Create: `ios/TodoNativeTests/AIAssistantServiceTests.swift`
- Modify: `ios/TodoNative/Services/AIService.swift`

**Interfaces:**
- Consumes: Task 1 models and existing `OpenAIService.callOpenAI(promptText:instructionText:)`.
- Produces: `AIAssistantServing`, `LiveAIAssistantService`, `AIAssistantDecoder`, `LocalAIAssistantPlanner`.

- [ ] **Step 1: Write failing decoder and fallback tests**

```swift
import XCTest
@testable import TodoNative

final class AIAssistantServiceTests: XCTestCase {
    func testDailyBriefDecoderAcceptsControlledJSON() throws {
        let json = #"{"summary":"先发布","detail":"保护截止任务","evidence":["1 个临近截止"]}"#
        XCTAssertEqual(try AIAssistantDecoder.dailyBrief(from: json).summary, "先发布")
    }

    func testInvalidJSONUsesLocalBriefWithVisibleEvidence() {
        let task = AIAssistantTaskSnapshot(id: UUID(), title: "交付发布说明", status: "todo", priority: 5, estimatedMinutes: 45, dueDate: Date().addingTimeInterval(3600), isArchived: false)
        let brief = LocalAIAssistantPlanner.dailyBrief(context: .init(tasks: [task], health: 58), now: Date())
        XCTAssertFalse(brief.summary.isEmpty)
        XCTAssertFalse(brief.evidence.isEmpty)
    }

    func testBreakdownFallbackReturnsSelectableTasks() {
        let result = LocalAIAssistantPlanner.workbench(mode: .breakdown, goal: "发布版本", context: .init(tasks: [], health: 50), now: Date())
        XCTAssertGreaterThanOrEqual(result.suggestedTasks.count, 3)
        XCTAssertTrue(result.sections.isEmpty)
    }

    func testReviewFallbackReturnsSectionsWithoutTasks() {
        let result = LocalAIAssistantPlanner.workbench(mode: .review, goal: "", context: .init(tasks: [], health: 50), now: Date())
        XCTAssertTrue(result.suggestedTasks.isEmpty)
        XCTAssertEqual(result.sections.map(\.id), ["progress", "next", "prompt"])
    }
}
```

- [ ] **Step 2: Run the test and verify RED**

Run the iOS focused command with `-only-testing:TodoNativeTests/AIAssistantServiceTests`. Expected: missing service, decoder, and local planner types.

- [ ] **Step 3: Implement protocol, controlled decode, and local planner**

```swift
import Foundation

@MainActor
protocol AIAssistantServing {
    func dailyBrief(context: AIAssistantContext, now: Date) async throws -> (AIDailyBriefContent, AIAssistantSource)
    func workbench(mode: AIWorkbenchMode, goal: String, context: AIAssistantContext, now: Date) async throws -> AIWorkbenchResult
}

enum AIAssistantDecoder {
    static func dailyBrief(from text: String) throws -> AIDailyBriefContent {
        try JSONDecoder().decode(AIDailyBriefContent.self, from: Data(text.utf8))
    }

    static func workbench(from text: String, source: AIAssistantSource) throws -> AIWorkbenchResult {
        struct Payload: Decodable { let overview: String; let suggestedTasks: [AISuggestedTask]; let sections: [AIResultSection] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let payload = try decoder.decode(Payload.self, from: Data(text.utf8))
        return AIWorkbenchResult(overview: payload.overview, suggestedTasks: payload.suggestedTasks, sections: payload.sections, source: source)
    }
}

enum LocalAIAssistantPlanner {
    static func dailyBrief(context: AIAssistantContext, now: Date) -> AIDailyBriefContent {
        let active = context.tasks.filter { !$0.isArchived && $0.status != "done" }
        let urgent = active.filter { ($0.dueDate ?? .distantFuture) < now.addingTimeInterval(86_400) }
        let top = active.sorted { ($0.priority, -$0.estimatedMinutes) > ($1.priority, -$1.estimatedMinutes) }.first
        return AIDailyBriefContent(
            summary: top.map { "先完成「\($0.title)」，再安排低耗能任务。" } ?? Localization.t("ai.brief.emptySummary"),
            detail: urgent.isEmpty ? Localization.t("ai.brief.steadyDetail") : Localization.t("ai.brief.deadlineDetail", urgent.count),
            evidence: [Localization.t("ai.brief.activeEvidence", active.count), Localization.t("ai.brief.deadlineEvidence", urgent.count), Localization.t("ai.brief.healthEvidence", context.health)]
        )
    }

    static func workbench(mode: AIWorkbenchMode, goal: String, context: AIAssistantContext, now: Date) -> AIWorkbenchResult {
        switch mode {
        case .todayPlan:
            let tasks = context.tasks.filter { !$0.isArchived && $0.status != "done" }.sorted { $0.priority > $1.priority }.prefix(5).map {
                AISuggestedTask(id: UUID(), title: $0.title, rationale: Localization.t("ai.workbench.existingTaskReason"), estimatedMinutes: $0.estimatedMinutes, priority: $0.priority, dueDate: $0.dueDate)
            }
            return AIWorkbenchResult(overview: Localization.t("ai.workbench.localPlanOverview"), suggestedTasks: Array(tasks), sections: [], source: .local)
        case .breakdown:
            let clean = goal.trimmingCharacters(in: .whitespacesAndNewlines)
            let titles = [Localization.t("ai.workbench.defineDone", clean), Localization.t("ai.workbench.collectContext"), Localization.t("ai.workbench.buildMinimum"), Localization.t("ai.workbench.verifyResult")]
            return AIWorkbenchResult(overview: Localization.t("ai.workbench.localBreakdownOverview"), suggestedTasks: titles.map { AISuggestedTask(id: UUID(), title: $0, rationale: Localization.t("ai.workbench.localReason"), estimatedMinutes: 30, priority: 3, dueDate: nil) }, sections: [], source: .local)
        case .review:
            return AIWorkbenchResult(overview: Localization.t("ai.workbench.localReviewOverview"), suggestedTasks: [], sections: [
                .init(id: "progress", title: Localization.t("ai.workbench.progress"), body: Localization.t("ai.workbench.progressBody", context.tasks.filter { $0.status == "done" }.count)),
                .init(id: "next", title: Localization.t("ai.workbench.next"), body: Localization.t("ai.workbench.nextBody")),
                .init(id: "prompt", title: Localization.t("ai.workbench.nextPrompt"), body: Localization.t("ai.workbench.nextPromptBody"))
            ], source: .local)
        }
    }
}
```

Add the live adapter with the following error boundary. `dailyBriefInstruction` and `workbenchInstruction(mode:)` must request only the JSON fields represented by the Codable models, with no Markdown fences.

```swift
struct LiveAIAssistantService: AIAssistantServing {
    func dailyBrief(context: AIAssistantContext, now: Date) async throws -> (AIDailyBriefContent, AIAssistantSource) {
        let fallback = LocalAIAssistantPlanner.dailyBrief(context: context, now: now)
        do {
            guard let text = try await OpenAIService.callOpenAI(
                promptText: Self.contextPrompt(context),
                instructionText: Self.dailyBriefInstruction
            ), !text.isEmpty else { return (fallback, .local) }
            let source: AIAssistantSource = OpenAIService.apiKey().trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .managed : .custom
            return (try AIAssistantDecoder.dailyBrief(from: text), source)
        } catch let error as QuotaError {
            throw error
        } catch {
            return (fallback, .local)
        }
    }

    func workbench(mode: AIWorkbenchMode, goal: String, context: AIAssistantContext, now: Date) async throws -> AIWorkbenchResult {
        let fallback = LocalAIAssistantPlanner.workbench(mode: mode, goal: goal, context: context, now: now)
        do {
            guard let text = try await OpenAIService.callOpenAI(
                promptText: "goal=\(goal)\n\(Self.contextPrompt(context))",
                instructionText: Self.workbenchInstruction(mode: mode)
            ), !text.isEmpty else { return fallback }
            let source: AIAssistantSource = OpenAIService.apiKey().trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .managed : .custom
            return try AIAssistantDecoder.workbench(from: text, source: source)
        } catch let error as QuotaError {
            throw error
        } catch {
            return fallback
        }
    }

    private static func contextPrompt(_ context: AIAssistantContext) -> String {
        let rows = context.tasks.filter { !$0.isArchived }.map {
            "- \($0.title) | \($0.status) | priority=\($0.priority) | minutes=\($0.estimatedMinutes) | due=\($0.dueDate?.ISO8601Format() ?? "none")"
        }
        return (["health=\(context.health)"] + rows).joined(separator: "\n")
    }

    private static let dailyBriefInstruction = "Return one JSON object with summary:String, detail:String, evidence:[String]. Give a concise actionable recommendation. Do not include Markdown."

    private static func workbenchInstruction(mode: AIWorkbenchMode) -> String {
        "Return one JSON object with overview:String, suggestedTasks:[{id UUID string,title:String,rationale:String,estimatedMinutes:Int|null,priority:Int|null,dueDate ISO8601|null}], sections:[{id:String,title:String,body:String}]. Mode=\(mode.rawValue). Review mode uses sections and an empty suggestedTasks array. Do not include Markdown."
    }
}
```

Add `AIService.dailyBrief(items:health:now:)` and `AIService.workbench(mode:goal:items:health:now:)` convenience methods that create `AIAssistantContext` and delegate to `LiveAIAssistantService`, leaving the three existing string APIs source-compatible.

- [ ] **Step 4: Run focused tests and verify GREEN**

Expected: decoder and local planner tests pass without a network call.

- [ ] **Step 5: Commit the task**

```bash
git add ios/TodoNative/Services/AIAssistantService.swift ios/TodoNative/Services/AIService.swift ios/TodoNativeTests/AIAssistantServiceTests.swift ios/TodoNative.xcodeproj/project.pbxproj
git commit -m "feat(ai): add structured assistant service"
```

---

### Task 4: Briefing ViewModel State Machines

**Files:**
- Create: `ios/TodoNative/ViewModels/AIBriefingViewModel.swift`
- Create: `ios/TodoNativeTests/AIBriefingViewModelTests.swift`

**Interfaces:**
- Consumes: `AIAssistantServing`, `AIBriefCaching`, and all Task 1 models.
- Produces: `AIBriefState`, `AIWorkbenchState`, `AIBriefingViewModel.appear`, `.contextDidChange`, `.refresh`, `.open`, `.runWorkbench`, `.toggleTask`, and `.selectedTasksForImport`.

- [ ] **Step 1: Write deterministic failing policy tests with fakes**

```swift
import XCTest
@testable import TodoNative

@MainActor
final class AIBriefingViewModelTests: XCTestCase {
    func testFirstAppearanceGeneratesAndSecondAppearanceSameDayUsesCache() async {
        let service = FakeAssistantService()
        let cache = MemoryBriefCache()
        let vm = AIBriefingViewModel(service: service, cache: cache)
        let now = Date(timeIntervalSince1970: 1_786_233_600)
        await vm.appear(items: [], health: 50, now: now)
        await vm.appear(items: [], health: 50, now: now.addingTimeInterval(60))
        XCTAssertEqual(service.dailyBriefCalls, 1)
    }

    func testChangedContextMarksBriefStaleWithoutGenerating() async {
        let service = FakeAssistantService()
        let vm = AIBriefingViewModel(service: service, cache: MemoryBriefCache())
        let now = Date(timeIntervalSince1970: 1_786_233_600)
        await vm.appear(items: [], health: 50, now: now)
        vm.contextDidChange(items: [TodoItem(title: "新任务")], health: 50)
        XCTAssertTrue(vm.isBriefStale)
        XCTAssertEqual(service.dailyBriefCalls, 1)
    }

    func testManualRefreshGeneratesAgain() async {
        let service = FakeAssistantService()
        let vm = AIBriefingViewModel(service: service, cache: MemoryBriefCache())
        let now = Date(timeIntervalSince1970: 1_786_233_600)
        await vm.appear(items: [], health: 50, now: now)
        await vm.refresh(items: [], health: 50, now: now.addingTimeInterval(60))
        XCTAssertEqual(service.dailyBriefCalls, 2)
    }

    func testSelectedTasksExcludeExistingTitles() async {
        let service = FakeAssistantService()
        service.workbenchResult = .init(overview: "", suggestedTasks: [.init(id: UUID(), title: "重复", rationale: "", estimatedMinutes: nil, priority: nil, dueDate: nil), .init(id: UUID(), title: "新增", rationale: "", estimatedMinutes: nil, priority: nil, dueDate: nil)], sections: [], source: .local)
        let vm = AIBriefingViewModel(service: service, cache: MemoryBriefCache())
        await vm.runWorkbench(items: [], health: 50)
        XCTAssertEqual(vm.selectedTasksForImport(existingTitles: ["重复"]).map(\.title), ["新增"])
    }
}
```

Include these deterministic test doubles in the test file so no test calls the network:

```swift
@MainActor
private final class FakeAssistantService: AIAssistantServing {
    var dailyBriefCalls = 0
    var workbenchCalls = 0
    var workbenchResult = AIWorkbenchResult(overview: "建议", suggestedTasks: [], sections: [], source: .managed)

    func dailyBrief(context: AIAssistantContext, now: Date) async throws -> (AIDailyBriefContent, AIAssistantSource) {
        dailyBriefCalls += 1
        return (.init(summary: "先发布", detail: "保护截止任务", evidence: ["1 个截止"]), .managed)
    }

    func workbench(mode: AIWorkbenchMode, goal: String, context: AIAssistantContext, now: Date) async throws -> AIWorkbenchResult {
        workbenchCalls += 1
        return workbenchResult
    }
}

private final class MemoryBriefCache: AIBriefCaching {
    var values: [String: AIDailyBrief] = [:]
    func load(for dayKey: String) -> AIDailyBrief? { values[dayKey] }
    func save(_ brief: AIDailyBrief, for dayKey: String) { values[dayKey] = brief }
}
```

- [ ] **Step 2: Run the test and verify RED**

Run the iOS focused command with `-only-testing:TodoNativeTests/AIBriefingViewModelTests`. Expected: missing view-model states and methods.

- [ ] **Step 3: Implement explicit state and generation guards**

```swift
enum AIBriefState: Equatable {
    case idle
    case loading(previous: AIDailyBrief?)
    case loaded(AIDailyBrief)
    case failed(previous: AIDailyBrief?, message: String)
}

enum AIWorkbenchState: Equatable {
    case idle
    case loading
    case result(AIWorkbenchResult)
    case failed(String)
}

@MainActor
final class AIBriefingViewModel: ObservableObject {
    @Published private(set) var briefState: AIBriefState = .idle
    @Published private(set) var isBriefStale = false
    @Published var mode: AIWorkbenchMode = .todayPlan
    @Published var goal = ""
    @Published private(set) var workbenchState: AIWorkbenchState = .idle
    @Published private(set) var selectedTaskIDs: Set<UUID> = []

    private let service: AIAssistantServing
    private let cache: AIBriefCaching
    private var currentContext: AIAssistantContext?
    private var requestGeneration = 0

    init(service: AIAssistantServing = LiveAIAssistantService(), cache: AIBriefCaching = UserDefaultsAIBriefCache()) {
        self.service = service
        self.cache = cache
    }
}
```

Add these methods inside the ViewModel; `currentBrief` returns the brief carried by loaded/loading/failed states.

```swift
func appear(items: [TodoItem], health: Int, now: Date = Date(), calendar: Calendar = .current) async {
    let context = AIAssistantContext(items: items, health: health)
    currentContext = context
    let key = AIBriefDayKey.value(for: now, calendar: calendar)
    if let cached = cache.load(for: key) {
        briefState = .loaded(cached)
        isBriefStale = cached.contextFingerprint != context.fingerprint
        return
    }
    await generateBrief(context: context, now: now, dayKey: key)
}

func contextDidChange(items: [TodoItem], health: Int) {
    let context = AIAssistantContext(items: items, health: health)
    currentContext = context
    isBriefStale = currentBrief.map { $0.contextFingerprint != context.fingerprint } ?? false
}

func refresh(items: [TodoItem], health: Int, now: Date = Date(), calendar: Calendar = .current) async {
    let context = AIAssistantContext(items: items, health: health)
    currentContext = context
    await generateBrief(context: context, now: now, dayKey: AIBriefDayKey.value(for: now, calendar: calendar))
}

private func generateBrief(context: AIAssistantContext, now: Date, dayKey: String) async {
    requestGeneration += 1
    let generation = requestGeneration
    let previous = currentBrief
    briefState = .loading(previous: previous)
    do {
        let (content, source) = try await service.dailyBrief(context: context, now: now)
        guard generation == requestGeneration else { return }
        let brief = AIDailyBrief(content: content, generatedAt: now, source: source, contextFingerprint: context.fingerprint)
        cache.save(brief, for: dayKey)
        briefState = .loaded(brief)
        isBriefStale = false
    } catch {
        guard generation == requestGeneration else { return }
        briefState = .failed(previous: previous, message: (error as? LocalizedError)?.errorDescription ?? Localization.t("ai.error.empty"))
    }
}

func open(mode: AIWorkbenchMode, prefill: String = "") {
    self.mode = mode
    if goal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { goal = prefill }
}

func runWorkbench(items: [TodoItem], health: Int, now: Date = Date()) async {
    requestGeneration += 1
    let generation = requestGeneration
    let context = AIAssistantContext(items: items, health: health)
    workbenchState = .loading
    do {
        let result = try await service.workbench(mode: mode, goal: goal, context: context, now: now)
        guard generation == requestGeneration else { return }
        selectedTaskIDs = Set(result.suggestedTasks.map(\.id))
        workbenchState = .result(result)
    } catch {
        guard generation == requestGeneration else { return }
        workbenchState = .failed((error as? LocalizedError)?.errorDescription ?? Localization.t("ai.error.empty"))
    }
}

func toggleTask(id: UUID) {
    if selectedTaskIDs.contains(id) { selectedTaskIDs.remove(id) } else { selectedTaskIDs.insert(id) }
}

func selectedTasksForImport(existingTitles: Set<String>) -> [AISuggestedTask] {
    guard case .result(let result) = workbenchState else { return [] }
    let existing = Set(existingTitles.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() })
    return result.suggestedTasks.filter {
        selectedTaskIDs.contains($0.id) && !existing.contains($0.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
    }
}
```

- [ ] **Step 4: Run focused tests and verify GREEN**

Expected: policy, stale state, refresh, and deduplication tests pass.

- [ ] **Step 5: Commit the task**

```bash
git add ios/TodoNative/ViewModels/AIBriefingViewModel.swift ios/TodoNativeTests/AIBriefingViewModelTests.swift ios/TodoNative.xcodeproj/project.pbxproj
git commit -m "feat(ai): manage daily brief lifecycle"
```

---

### Task 5: Today-Screen AI Daily Brief Card

**Files:**
- Create: `ios/TodoNative/Components/AIDailyBriefCard.swift`
- Modify: `ios/TodoNative/Views/DashboardView.swift`
- Create: `ios/TodoNativeTests/AIDailyBriefPresentationTests.swift`

**Interfaces:**
- Consumes: `AIBriefingViewModel.briefState`, `isBriefStale`, `AIWorkbenchMode`.
- Produces: `AIDailyBriefCard` with `onOpen`, `onRefresh`, and `onQuickAction` closures; Dashboard sheet routing with a mode.

- [ ] **Step 1: Write failing pure presentation tests**

```swift
import XCTest
@testable import TodoNative

final class AIDailyBriefPresentationTests: XCTestCase {
    func testLoadedStaleBriefShowsUpdateStatus() {
        let brief = AIDailyBrief(content: .init(summary: "先发布", detail: "保护截止任务", evidence: []), generatedAt: Date(), source: .managed, contextFingerprint: "old")
        XCTAssertEqual(AIDailyBriefPresentation(state: .loaded(brief), isStale: true).statusKey, "ai.brief.updateAvailable")
    }

    func testFailedStateKeepsPreviousBriefVisible() {
        let brief = AIDailyBrief(content: .init(summary: "保留", detail: "旧简报", evidence: []), generatedAt: Date(), source: .managed, contextFingerprint: "old")
        XCTAssertEqual(AIDailyBriefPresentation(state: .failed(previous: brief, message: "额度不足"), isStale: false).brief, brief)
    }
}
```

- [ ] **Step 2: Run the test and verify RED**

Run the iOS focused command with `-only-testing:TodoNativeTests/AIDailyBriefPresentationTests`. Expected: missing presentation adapter.

- [ ] **Step 3: Implement presentation adapter and card**

Create the pure adapter, then build the card:

```swift
struct AIDailyBriefPresentation: Equatable {
    let brief: AIDailyBrief?
    let statusKey: String?
    let showsProgress: Bool
    let errorMessage: String?

    init(state: AIBriefState, isStale: Bool) {
        switch state {
        case .idle:
            brief = nil; statusKey = nil; showsProgress = false; errorMessage = nil
        case .loading(let previous):
            brief = previous; statusKey = nil; showsProgress = true; errorMessage = nil
        case .loaded(let value):
            brief = value; statusKey = isStale ? "ai.brief.updateAvailable" : "ai.brief.updatedAt"; showsProgress = false; errorMessage = nil
        case .failed(let previous, let message):
            brief = previous; statusKey = previous == nil ? nil : "ai.brief.updateAvailable"; showsProgress = false; errorMessage = message
        }
    }
}
```

Build the card with:

```swift
struct AIDailyBriefCard: View {
    let presentation: AIDailyBriefPresentation
    let onOpen: () -> Void
    let onRefresh: () -> Void
    let onQuickAction: (AIWorkbenchMode) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            header
            if let brief = presentation.brief { loadedContent(brief) }
            else if presentation.showsProgress { loadingContent }
            else { emptyContent }
            if let error = presentation.errorMessage { Text(error).foregroundStyle(.red).font(AppTheme.Typography.caption2) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .appCard()
        .accessibilityElement(children: .contain)
    }
}
```

Use `sparkles` and `arrow.clockwise` SF Symbols in production. The three quick actions map to `.todayPlan`, `.review`, and `.breakdown`. Apply the existing `AppTheme.Motion.resolvedFade` helper and maintain 44pt targets.

Modify Dashboard order to `AIDailyBriefCard`, `executionSummary`, `todayPlan`. Replace the toolbar title `AI` with localized `AI Brief`. Call `briefing.appear` from `.task` and `briefing.contextDidChange` from `.onChange` of a stable Dashboard context fingerprint. Route the toolbar, card, and quick actions to the existing AI sheet with the selected mode.

- [ ] **Step 4: Run focused tests and a Debug build**

Expected: presentation tests pass and Dashboard compiles at regular and accessibility Dynamic Type sizes.

- [ ] **Step 5: Commit the task**

```bash
git add ios/TodoNative/Components/AIDailyBriefCard.swift ios/TodoNative/Views/DashboardView.swift ios/TodoNativeTests/AIDailyBriefPresentationTests.swift ios/TodoNative.xcodeproj/project.pbxproj
git commit -m "feat(ios): surface AI daily brief on Today"
```

---

### Task 6: Structured Three-Mode AI Workbench

**Files:**
- Replace: `ios/TodoNative/Views/AIWorkbenchView.swift`
- Create: `ios/TodoNative/Components/AIWorkbenchResultView.swift`
- Create: `ios/TodoNativeTests/AIWorkbenchPresentationTests.swift`

**Interfaces:**
- Consumes: shared `AIBriefingViewModel`, `TodoViewModel`, `AIWorkbenchMode`, `AIWorkbenchState`.
- Produces: segmented workbench, contextual prompt, structured selectable results, explicit task import.

- [ ] **Step 1: Write failing mode-copy and import-label tests**

```swift
import XCTest
@testable import TodoNative

final class AIWorkbenchPresentationTests: XCTestCase {
    func testModePresentationUsesDistinctPrimaryActions() {
        XCTAssertEqual(AIWorkbenchModePresentation(mode: .todayPlan).primaryActionKey, "ai.workbench.generatePlan")
        XCTAssertEqual(AIWorkbenchModePresentation(mode: .breakdown).primaryActionKey, "ai.workbench.generateBreakdown")
        XCTAssertEqual(AIWorkbenchModePresentation(mode: .review).primaryActionKey, "ai.workbench.generateReview")
    }

    func testTaskResultUsesTodayPlanImportLabel() {
        XCTAssertEqual(AIWorkbenchResultPresentation(mode: .todayPlan, selectedCount: 3).importKey, "ai.workbench.addToToday")
    }

    func testReviewResultDoesNotShowImport() {
        XCTAssertNil(AIWorkbenchResultPresentation(mode: .review, selectedCount: 0).importKey)
    }
}
```

- [ ] **Step 2: Run the test and verify RED**

Run the iOS focused command with `-only-testing:TodoNativeTests/AIWorkbenchPresentationTests`. Expected: missing presentation types.

- [ ] **Step 3: Replace form UI with the continuous workbench**

The view hierarchy must be:

```swift
NavigationStack {
    ScrollView {
        VStack(spacing: AppTheme.Spacing.md) {
            serviceStatus
            Picker("", selection: $briefing.mode) { /* all modes */ }
                .pickerStyle(.segmented)
            contextDisclosure
            promptCard
            AIWorkbenchResultView(state: briefing.workbenchState, mode: briefing.mode, selectedTaskIDs: briefing.selectedTaskIDs, onToggle: briefing.toggleTask)
        }
        .padding(AppTheme.Spacing.md)
    }
    .safeAreaInset(edge: .bottom) { bottomActions }
    .navigationTitle(Localization.t("ai.workbench.title"))
    .navigationBarTitleDisplayMode(.inline)
}
```

`promptCard` contains the mode-specific question, a multiline `TextField(axis: .vertical)`, prompt chips, and one primary generate button. Remove the three stacked action buttons, monospaced output, and empty output box.

`AIWorkbenchResultView` renders selectable task rows for plan/breakdown and titled text sections for review. The bottom inset shows `Regenerate` and the localized import action only when suggested tasks exist. Import calls `selectedTasksForImport`, then creates each item through `TodoViewModel.captureNaturalLanguage`; `.todayPlan` uses `sourceGoal: "ai-today-plan"`, `.breakdown` uses the user goal. Announce import success through `UIAccessibility.post`.

Add `.presentationDragIndicator(.visible)` and `.presentationDetents([.large])` at the Dashboard sheet call site. Preserve input when changing modes; do not auto-run.

- [ ] **Step 4: Run focused tests and a Debug build**

Expected: presentation tests pass, the old `AI output` container is absent, and the workbench compiles with the shared environment object.

- [ ] **Step 5: Commit the task**

```bash
git add ios/TodoNative/Views/AIWorkbenchView.swift ios/TodoNative/Components/AIWorkbenchResultView.swift ios/TodoNative/Views/DashboardView.swift ios/TodoNativeTests/AIWorkbenchPresentationTests.swift ios/TodoNative.xcodeproj/project.pbxproj
git commit -m "feat(ai): redesign the mobile workbench"
```

---

### Task 7: App Injection, Localization, Accessibility, and Integration

**Files:**
- Modify: `ios/TodoNative/TodoNativeApp.swift`
- Modify: `ios/TodoNative/Localization/Localization.swift`
- Modify: `ios/TodoNativeTests/LocalizationTests.swift`
- Modify: `ios/TodoNative/Views/DashboardView.swift`
- Modify: `ios/TodoNative/Views/AIWorkbenchView.swift`

**Interfaces:**
- Consumes: `AIBriefingViewModel` and all UI components from Tasks 4–6.
- Produces: one shared environment object and complete bilingual accessible product flow.

- [ ] **Step 1: Extend the localization completeness test before adding strings**

Add the exact keys below to the bilingual key list:

```swift
"ai.brief.title", "ai.brief.toolbar", "ai.brief.updatedAt", "ai.brief.updateAvailable", "ai.brief.local", "ai.brief.refresh", "ai.brief.generatePlan", "ai.brief.helpPrioritize", "ai.brief.breakdown", "ai.brief.emptySummary", "ai.brief.steadyDetail", "ai.brief.deadlineDetail", "ai.brief.activeEvidence", "ai.brief.deadlineEvidence", "ai.brief.healthEvidence", "ai.workbench.title", "ai.workbench.subtitle", "ai.workbench.context", "ai.workbench.todayPlan", "ai.workbench.breakdown", "ai.workbench.review", "ai.workbench.generatePlan", "ai.workbench.generateBreakdown", "ai.workbench.generateReview", "ai.workbench.regenerate", "ai.workbench.addToToday", "ai.workbench.addToTodo", "ai.workbench.imported", "ai.workbench.existingTaskReason", "ai.workbench.localPlanOverview", "ai.workbench.defineDone", "ai.workbench.collectContext", "ai.workbench.buildMinimum", "ai.workbench.verifyResult", "ai.workbench.localBreakdownOverview", "ai.workbench.localReason", "ai.workbench.localReviewOverview", "ai.workbench.progress", "ai.workbench.progressBody", "ai.workbench.next", "ai.workbench.nextBody", "ai.workbench.nextPrompt", "ai.workbench.nextPromptBody"
```

- [ ] **Step 2: Run LocalizationTests and verify RED**

Expected: every new key falls back to its key in Chinese and English.

- [ ] **Step 3: Add Chinese/English copy and inject the shared ViewModel**

In `TodoNativeApp`, create exactly one shared object:

```swift
@StateObject private var aiBriefingViewModel: AIBriefingViewModel

// init
_aiBriefingViewModel = StateObject(wrappedValue: AIBriefingViewModel())

// MainTabView environment
.environmentObject(aiBriefingViewModel)
```

Add these exact values to the Chinese and English dictionaries. Do not translate service or model names.

```swift
// zh
"ai.brief.title": "今日 AI 简报",
"ai.brief.toolbar": "AI 简报",
"ai.brief.updatedAt": "今天 %@ 更新",
"ai.brief.updateAvailable": "建议可更新",
"ai.brief.local": "本地建议",
"ai.brief.refresh": "更新简报",
"ai.brief.generatePlan": "生成计划",
"ai.brief.helpPrioritize": "帮我取舍",
"ai.brief.breakdown": "拆解目标",
"ai.brief.emptySummary": "先添加一项任务，我会帮你安排今天。",
"ai.brief.steadyDetail": "当前没有临近截止，可以按优先级稳定推进。",
"ai.brief.deadlineDetail": "有 %d 项任务即将到期，先保护截止任务。",
"ai.brief.activeEvidence": "%d 项进行中",
"ai.brief.deadlineEvidence": "%d 个临近截止",
"ai.brief.healthEvidence": "健康分 %d",
"ai.workbench.title": "AI 计划助手",
"ai.workbench.subtitle": "把想法变成下一步",
"ai.workbench.context": "已读取 %d 项任务、%d 个截止时间与当前健康分；不会自动修改任务。",
"ai.workbench.todayPlan": "今日计划",
"ai.workbench.breakdown": "拆解目标",
"ai.workbench.review": "复盘",
"ai.workbench.generatePlan": "生成今日建议",
"ai.workbench.generateBreakdown": "智能拆解",
"ai.workbench.generateReview": "生成复盘",
"ai.workbench.regenerate": "重新生成",
"ai.workbench.addToToday": "加入今日计划（%d）",
"ai.workbench.addToTodo": "加入待办（%d）",
"ai.workbench.imported": "AI 建议已加入任务列表。",
"ai.workbench.existingTaskReason": "来自现有任务",
"ai.workbench.localPlanOverview": "先保护高优先级和临近截止任务。",
"ai.workbench.defineDone": "明确「%@」的完成定义",
"ai.workbench.collectContext": "整理已有资料、约束和风险",
"ai.workbench.buildMinimum": "完成一个 30 分钟内可验证的最小版本",
"ai.workbench.verifyResult": "按验收标准验证并记录结果",
"ai.workbench.localBreakdownOverview": "先定义结果，再拆成可验证的小步骤。",
"ai.workbench.localReason": "本地规划建议",
"ai.workbench.localReviewOverview": "根据当前任务生成的本地复盘。",
"ai.workbench.progress": "进展概览",
"ai.workbench.progressBody": "已完成 %d 项任务。",
"ai.workbench.next": "下一步建议",
"ai.workbench.nextBody": "选择一个最小任务推进，避免同时开启过多分支。",
"ai.workbench.nextPrompt": "下一条 AI 提示",
"ai.workbench.nextPromptBody": "请基于当前任务，给出一个 30 分钟内可验证的下一步。",

// en
"ai.brief.title": "Today's AI Brief",
"ai.brief.toolbar": "AI Brief",
"ai.brief.updatedAt": "Updated today at %@",
"ai.brief.updateAvailable": "Update available",
"ai.brief.local": "On-device suggestion",
"ai.brief.refresh": "Refresh brief",
"ai.brief.generatePlan": "Build a plan",
"ai.brief.helpPrioritize": "Help me prioritize",
"ai.brief.breakdown": "Break down a goal",
"ai.brief.emptySummary": "Add a task and I will help shape your day.",
"ai.brief.steadyDetail": "Nothing is due soon, so you can progress by priority.",
"ai.brief.deadlineDetail": "%d tasks are due soon. Protect the deadline work first.",
"ai.brief.activeEvidence": "%d active tasks",
"ai.brief.deadlineEvidence": "%d near deadlines",
"ai.brief.healthEvidence": "Health %d",
"ai.workbench.title": "AI Planning Assistant",
"ai.workbench.subtitle": "Turn an idea into the next step",
"ai.workbench.context": "Using %d tasks, %d deadlines, and your current health score. Tasks are never changed automatically.",
"ai.workbench.todayPlan": "Today Plan",
"ai.workbench.breakdown": "Break Down",
"ai.workbench.review": "Review",
"ai.workbench.generatePlan": "Generate today's advice",
"ai.workbench.generateBreakdown": "Break it down",
"ai.workbench.generateReview": "Generate review",
"ai.workbench.regenerate": "Regenerate",
"ai.workbench.addToToday": "Add to Today (%d)",
"ai.workbench.addToTodo": "Add to Tasks (%d)",
"ai.workbench.imported": "AI suggestions were added to your tasks.",
"ai.workbench.existingTaskReason": "From an existing task",
"ai.workbench.localPlanOverview": "Protect high-priority and near-deadline work first.",
"ai.workbench.defineDone": "Define done for “%@”",
"ai.workbench.collectContext": "Gather existing material, constraints, and risks",
"ai.workbench.buildMinimum": "Build a minimum result that can be verified in 30 minutes",
"ai.workbench.verifyResult": "Verify the result against acceptance criteria",
"ai.workbench.localBreakdownOverview": "Define the outcome, then create verifiable steps.",
"ai.workbench.localReason": "On-device planning suggestion",
"ai.workbench.localReviewOverview": "An on-device review based on current tasks.",
"ai.workbench.progress": "Progress",
"ai.workbench.progressBody": "%d tasks completed.",
"ai.workbench.next": "Next step",
"ai.workbench.nextBody": "Move one small task forward instead of opening too many branches.",
"ai.workbench.nextPrompt": "Next AI prompt",
"ai.workbench.nextPromptBody": "Based on my current tasks, suggest one verifiable next step I can finish in 30 minutes."
```

Audit both screens for:

- 44pt button targets.
- VoiceOver labels and values for brief state, stale state, model/quota state, selection count, loading, failure, and import success.
- Reduce Motion via existing theme helpers.
- Vertical reflow at accessibility Dynamic Type sizes.
- No color-only status communication.

- [ ] **Step 4: Generate the project and run all focused AI tests**

Run:

```bash
cd ios && xcodegen generate && xcodebuild -project TodoNative.xcodeproj -scheme TodoNative -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=27.0' -only-testing:TodoNativeTests/AIAssistantModelsTests -only-testing:TodoNativeTests/AIBriefCacheTests -only-testing:TodoNativeTests/AIAssistantServiceTests -only-testing:TodoNativeTests/AIBriefingViewModelTests -only-testing:TodoNativeTests/AIDailyBriefPresentationTests -only-testing:TodoNativeTests/AIWorkbenchPresentationTests -only-testing:TodoNativeTests/LocalizationTests test
```

Expected: all selected tests pass with zero failures.

- [ ] **Step 5: Commit the task**

```bash
git add ios/TodoNative/TodoNativeApp.swift ios/TodoNative/Localization/Localization.swift ios/TodoNative/Views/DashboardView.swift ios/TodoNative/Views/AIWorkbenchView.swift ios/TodoNativeTests/LocalizationTests.swift ios/TodoNative.xcodeproj/project.pbxproj
git commit -m "feat(ios): integrate AI-native daily briefing"
```

---

### Task 8: Full Regression, Release Isolation, and Device Deployment

**Files:**
- Verify only; modify product files only for failures attributable to Tasks 1–7.

**Interfaces:**
- Consumes: the complete feature.
- Produces: test, Release, device-install, and launch evidence.

- [ ] **Step 1: Run the complete iOS suite**

```bash
xcodebuild -project ios/TodoNative.xcodeproj -scheme TodoNative -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=27.0' test
```

Expected: all tests pass with zero failures.

- [ ] **Step 2: Run unchanged web and worker suites**

```bash
node --test
cd workers/quota-proxy && npm test
```

Expected: both suites pass with zero failures.

- [ ] **Step 3: Build Release**

```bash
xcodebuild -project ios/TodoNative.xcodeproj -scheme TodoNative -configuration Release -destination 'generic/platform=iOS Simulator' build
```

Expected: `BUILD SUCCEEDED`; Debug-only notification tools remain absent from Release.

- [ ] **Step 4: Perform simulator visual QA**

Verify Today loaded, stale, local fallback, quota failure, loading, and empty states; verify all three workbench modes, task selection, import confirmation, maximum Dynamic Type, VoiceOver labels, and Reduce Motion. Compare the implementation at iPhone 17 Pro size with the approved A-option visual hierarchy.

- [ ] **Step 5: Build, install, and launch the WiFi device target**

```bash
cd ios
xcodebuild -project TodoNative.xcodeproj -scheme TodoNative -destination 'id=00008150-001934920240401C' -derivedDataPath build/dd build
xcrun devicectl device install app --device C3AC8A00-2E4A-5147-BBD4-2C843EF20846 /Users/lizhi/code/todo-list-app/ios/build/dd/Build/Products/Debug-iphoneos/TodoNative.app
xcrun devicectl device process launch --device C3AC8A00-2E4A-5147-BBD4-2C843EF20846 com.zhili.todo-native
```

Expected: device build succeeds, installation reports bundle ID `com.zhili.todo-native`, and launch succeeds.

- [ ] **Step 6: Final review and integration commit**

Review the complete diff for stale requests, duplicate imports, accidental automatic task mutation, inaccessible state changes, and Release-only regressions. If integration fixes were required, commit them as:

```bash
git add ios/TodoNative/Models/AIAssistantModels.swift ios/TodoNative/Services/AIBriefCache.swift ios/TodoNative/Services/AIAssistantService.swift ios/TodoNative/Services/AIService.swift ios/TodoNative/ViewModels/AIBriefingViewModel.swift ios/TodoNative/Components/AIDailyBriefCard.swift ios/TodoNative/Components/AIWorkbenchResultView.swift ios/TodoNative/Views/DashboardView.swift ios/TodoNative/Views/AIWorkbenchView.swift ios/TodoNative/TodoNativeApp.swift ios/TodoNative/Localization/Localization.swift ios/TodoNativeTests/AIAssistantModelsTests.swift ios/TodoNativeTests/AIBriefCacheTests.swift ios/TodoNativeTests/AIAssistantServiceTests.swift ios/TodoNativeTests/AIBriefingViewModelTests.swift ios/TodoNativeTests/AIDailyBriefPresentationTests.swift ios/TodoNativeTests/AIWorkbenchPresentationTests.swift ios/TodoNativeTests/LocalizationTests.swift ios/TodoNative.xcodeproj/project.pbxproj
git commit -m "fix(ios): harden AI briefing integration"
```
