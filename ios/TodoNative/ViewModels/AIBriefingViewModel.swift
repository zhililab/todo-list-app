import Foundation

enum AIAssistantRecovery: String, Equatable, Sendable {
    case manageSubscription
    case configureProvider
}

struct AIAssistantFailure: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case quotaExceeded(kind: String)
        case other
    }

    let kind: Kind
    let message: String
    let recovery: [AIAssistantRecovery]

    init(error: Error) {
        if case .quotaExceeded(let kind) = error as? QuotaError {
            self.kind = .quotaExceeded(kind: kind)
            message = (error as? LocalizedError)?.errorDescription
                ?? Localization.t("ai.error.empty")
            recovery = [.manageSubscription, .configureProvider]
        } else {
            kind = .other
            message = (error as? LocalizedError)?.errorDescription
                ?? Localization.t("ai.error.empty")
            recovery = []
        }
    }
}

enum AIBriefState: Equatable, Sendable {
    case idle
    case loading(previous: AIDailyBrief?)
    case loaded(AIDailyBrief)
    case failed(previous: AIDailyBrief?, failure: AIAssistantFailure)
}

enum AIWorkbenchState: Equatable, Sendable {
    case idle
    case loading(previous: AIWorkbenchSession?)
    case result(AIWorkbenchSession)
    case failed(previous: AIWorkbenchSession?, failure: AIAssistantFailure)
}

struct AIWorkbenchProvenance: Equatable, Sendable {
    let mode: AIWorkbenchMode
    let goal: String
    let contextFingerprint: String
}

struct AIWorkbenchSession: Equatable, Sendable {
    let provenance: AIWorkbenchProvenance
    let result: AIWorkbenchResult
}

struct AIWorkbenchApplication: Equatable, Sendable {
    let existingTaskIDs: [UUID]
    let newTasks: [AISuggestedTask]

    var count: Int { existingTaskIDs.count + newTasks.count }
}

struct AIBriefRequest: Equatable, Sendable {
    let id: UUID
    let dayKey: String
    let contextFingerprint: String
}

struct AIWorkbenchRequest: Equatable, Sendable {
    let id: UUID
    let mode: AIWorkbenchMode
    let goal: String
    let contextFingerprint: String
}

@MainActor
final class AIBriefingViewModel: ObservableObject {
    @Published private(set) var briefState: AIBriefState = .idle
    @Published private(set) var isBriefStale = false
    @Published var mode: AIWorkbenchMode = .todayPlan {
        didSet {
            guard oldValue != mode else { return }
            invalidateWorkbench()
        }
    }
    @Published var goal = ""
    @Published private(set) var workbenchState: AIWorkbenchState = .idle
    @Published private(set) var selectedTaskIDs: Set<UUID> = []

    private let service: any AIAssistantServing
    private let cache: any AIBriefCaching
    private let attemptTracker: any AIBriefAutoAttemptTracking
    private var currentContext: AIAssistantContext?
    private var activeBriefRequest: AIBriefRequest?
    private var activeWorkbenchRequest: AIWorkbenchRequest?
    private var activeBriefTask: Task<(AIDailyBriefContent, AIAssistantSource), Error>?
    private var activeWorkbenchTask: Task<AIWorkbenchResult, Error>?

    init(
        service: any AIAssistantServing = LiveAIAssistantService(),
        cache: any AIBriefCaching = UserDefaultsAIBriefCache(),
        attemptTracker: any AIBriefAutoAttemptTracking = UserDefaultsAIBriefAttemptTracker()
    ) {
        self.service = service
        self.cache = cache
        self.attemptTracker = attemptTracker
    }

    func appear(
        items: [TodoItem],
        health: Int,
        now: Date = Date(),
        calendar: Calendar = .current
    ) async {
        let context = AIAssistantContext(items: items, health: health)
        currentContext = context
        let dayKey = AIBriefDayKey.value(for: now, calendar: calendar)

        if activeBriefRequest?.dayKey == dayKey {
            return
        }

        if let cached = cache.load(for: dayKey) {
            activeBriefRequest = nil
            briefState = .loaded(cached)
            updateStaleState(for: cached)
            return
        }

        if attemptTracker.hasAttemptedAutomaticGeneration(for: dayKey) {
            restoreMostRecentBriefWhenIdle()
            updateStaleState(for: currentBrief)
            return
        }

        attemptTracker.markAutomaticGenerationAttempted(for: dayKey)
        await generateBrief(
            context: context,
            now: now,
            dayKey: dayKey,
            previous: currentBrief ?? cache.loadMostRecent()
        )
    }

    func contextDidChange(items: [TodoItem], health: Int) {
        currentContext = AIAssistantContext(items: items, health: health)
        updateStaleState(for: currentBrief)
    }

    func refresh(
        items: [TodoItem],
        health: Int,
        now: Date = Date(),
        calendar: Calendar = .current
    ) async {
        let context = AIAssistantContext(items: items, health: health)
        currentContext = context
        let dayKey = AIBriefDayKey.value(for: now, calendar: calendar)
        attemptTracker.markAutomaticGenerationAttempted(for: dayKey)
        let previous = cache.load(for: dayKey) ?? currentBrief ?? cache.loadMostRecent()
        await generateBrief(
            context: context,
            now: now,
            dayKey: dayKey,
            previous: previous
        )
    }

    func open(mode: AIWorkbenchMode, prefill: String? = nil) {
        self.mode = mode
        guard let prefill else { return }
        if goal != prefill {
            invalidateWorkbench()
        }
        goal = prefill
    }

    func runWorkbench(
        items: [TodoItem],
        health: Int,
        now: Date = Date()
    ) async {
        let context = AIAssistantContext(items: items, health: health)
        let request = AIWorkbenchRequest(
            id: UUID(),
            mode: mode,
            goal: goal,
            contextFingerprint: context.fingerprint
        )
        let previous = currentWorkbenchSession
        activeWorkbenchTask?.cancel()
        activeWorkbenchRequest = request
        if previous == nil {
            selectedTaskIDs = []
        }
        workbenchState = .loading(previous: previous)
        let serviceTask = Task {
            try await service.workbench(
                mode: request.mode,
                goal: request.goal,
                context: context,
                now: now
            )
        }
        activeWorkbenchTask = serviceTask

        do {
            let result = try await withTaskCancellationHandler {
                try await serviceTask.value
            } onCancel: {
                serviceTask.cancel()
            }
            guard activeWorkbenchRequest == request else { return }
            activeWorkbenchRequest = nil
            activeWorkbenchTask = nil
            selectedTaskIDs = Set(result.suggestedTasks.map(\.id))
            workbenchState = .result(
                AIWorkbenchSession(
                    provenance: AIWorkbenchProvenance(
                        mode: request.mode,
                        goal: request.goal,
                        contextFingerprint: request.contextFingerprint
                    ),
                    result: result
                )
            )
        } catch {
            guard activeWorkbenchRequest == request else { return }
            activeWorkbenchRequest = nil
            activeWorkbenchTask = nil
            if error is CancellationError || Task.isCancelled {
                workbenchState = previous.map(AIWorkbenchState.result) ?? .idle
                return
            }
            workbenchState = .failed(
                previous: previous,
                failure: AIAssistantFailure(error: error)
            )
        }
    }

    func toggleTask(id: UUID) {
        if selectedTaskIDs.contains(id) {
            selectedTaskIDs.remove(id)
        } else {
            selectedTaskIDs.insert(id)
        }
    }

    func selectedTasksForImport(
        existingTitles: Set<String>,
        currentContext: AIAssistantContext
    ) -> [AISuggestedTask] {
        guard
            let session = currentWorkbenchSession,
            session.provenance == AIWorkbenchProvenance(
                mode: mode,
                goal: goal,
                contextFingerprint: currentContext.fingerprint
            )
        else { return [] }
        var seen = Set(existingTitles.compactMap(Self.normalizedTitleKey))
        var importable: [AISuggestedTask] = []

        for task in session.result.suggestedTasks where selectedTaskIDs.contains(task.id) {
            let displayTitle = Self.collapsedWhitespace(task.title)
            guard let key = Self.normalizedTitleKey(displayTitle), seen.insert(key).inserted else {
                continue
            }
            importable.append(
                AISuggestedTask(
                    id: task.id,
                    title: displayTitle,
                    rationale: task.rationale,
                    estimatedMinutes: task.estimatedMinutes,
                    priority: task.priority,
                    dueDate: task.dueDate
                )
            )
        }
        return importable
    }

    func selectedTasksForApplication(
        existingItems: [TodoItem],
        currentContext: AIAssistantContext
    ) -> AIWorkbenchApplication {
        guard
            let session = currentWorkbenchSession,
            session.provenance == AIWorkbenchProvenance(
                mode: mode,
                goal: goal,
                contextFingerprint: currentContext.fingerprint
            )
        else {
            return AIWorkbenchApplication(existingTaskIDs: [], newTasks: [])
        }

        let activeItems = existingItems.filter { !$0.isArchived && !$0.isCompleted }
        let activeIDs = Set(activeItems.map(\.id))
        var seenExistingIDs = Set<UUID>()
        var seenTitles = Set(activeItems.compactMap { Self.normalizedTitleKey($0.title) })
        var existingTaskIDs: [UUID] = []
        var newTasks: [AISuggestedTask] = []

        for task in session.result.suggestedTasks where selectedTaskIDs.contains(task.id) {
            if mode == .todayPlan,
               activeIDs.contains(task.id),
               seenExistingIDs.insert(task.id).inserted {
                existingTaskIDs.append(task.id)
                continue
            }

            let displayTitle = Self.collapsedWhitespace(task.title)
            guard let key = Self.normalizedTitleKey(displayTitle), seenTitles.insert(key).inserted else {
                continue
            }
            newTasks.append(
                AISuggestedTask(
                    id: task.id,
                    title: displayTitle,
                    rationale: task.rationale,
                    estimatedMinutes: task.estimatedMinutes,
                    priority: task.priority,
                    dueDate: task.dueDate
                )
            )
        }

        return AIWorkbenchApplication(
            existingTaskIDs: existingTaskIDs,
            newTasks: newTasks
        )
    }

    func selectedImportCount(
        existingTitles: Set<String>,
        currentContext: AIAssistantContext
    ) -> Int {
        selectedTasksForImport(
            existingTitles: existingTitles,
            currentContext: currentContext
        ).count
    }

    private var currentWorkbenchSession: AIWorkbenchSession? {
        switch workbenchState {
        case .idle:
            return nil
        case .loading(let previous), .failed(let previous, _):
            return previous
        case .result(let session):
            return session
        }
    }

    private var currentBrief: AIDailyBrief? {
        switch briefState {
        case .idle:
            return nil
        case .loading(let previous), .failed(let previous, _):
            return previous
        case .loaded(let brief):
            return brief
        }
    }

    private func generateBrief(
        context: AIAssistantContext,
        now: Date,
        dayKey: String,
        previous: AIDailyBrief?
    ) async {
        let request = AIBriefRequest(
            id: UUID(),
            dayKey: dayKey,
            contextFingerprint: context.fingerprint
        )
        activeBriefTask?.cancel()
        activeBriefRequest = request
        briefState = .loading(previous: previous)
        updateStaleState(for: previous)
        let serviceTask = Task {
            try await service.dailyBrief(context: context, now: now)
        }
        activeBriefTask = serviceTask

        do {
            let (content, source) = try await withTaskCancellationHandler {
                try await serviceTask.value
            } onCancel: {
                serviceTask.cancel()
            }
            guard activeBriefRequest == request else { return }
            activeBriefRequest = nil
            activeBriefTask = nil
            let brief = AIDailyBrief(
                content: content,
                generatedAt: now,
                source: source,
                contextFingerprint: request.contextFingerprint
            )
            cache.save(brief, for: dayKey)
            briefState = .loaded(brief)
            updateStaleState(for: brief)
        } catch {
            guard activeBriefRequest == request else { return }
            activeBriefRequest = nil
            activeBriefTask = nil
            if error is CancellationError || Task.isCancelled {
                briefState = previous.map(AIBriefState.loaded) ?? .idle
                updateStaleState(for: previous)
                return
            }
            briefState = .failed(
                previous: previous,
                failure: AIAssistantFailure(error: error)
            )
            updateStaleState(for: previous)
        }
    }

    private func restoreMostRecentBriefWhenIdle() {
        guard case .idle = briefState, let recent = cache.loadMostRecent() else { return }
        briefState = .loaded(recent)
    }

    private func updateStaleState(for brief: AIDailyBrief?) {
        guard let brief, let currentContext else {
            isBriefStale = false
            return
        }
        isBriefStale = brief.contextFingerprint != currentContext.fingerprint
    }

    private func invalidateWorkbench() {
        activeWorkbenchTask?.cancel()
        activeWorkbenchTask = nil
        activeWorkbenchRequest = nil
        selectedTaskIDs = []
        workbenchState = .idle
    }

    private static func collapsedWhitespace(_ title: String) -> String {
        title.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    private static func normalizedTitleKey(_ title: String) -> String? {
        let collapsed = collapsedWhitespace(title)
        guard !collapsed.isEmpty else { return nil }
        return collapsed.lowercased(with: Locale(identifier: "en_US_POSIX"))
    }
}
