import Foundation

@MainActor
protocol AIAssistantServing {
    func dailyBrief(
        context: AIAssistantContext,
        now: Date
    ) async throws -> (AIDailyBriefContent, AIAssistantSource)

    func workbench(
        mode: AIWorkbenchMode,
        goal: String,
        context: AIAssistantContext,
        now: Date
    ) async throws -> AIWorkbenchResult
}

@MainActor
protocol AIAssistantTransporting {
    func call(
        promptText: String,
        instructionText: String
    ) async throws -> (text: String?, source: AIAssistantSource)
}

@MainActor
struct OpenAIAssistantTransport: AIAssistantTransporting {
    func call(
        promptText: String,
        instructionText: String
    ) async throws -> (text: String?, source: AIAssistantSource) {
        try await OpenAIService.callOpenAIWithSource(
            promptText: promptText,
            instructionText: instructionText
        )
    }
}

enum AIAssistantDecodingError: Error, Equatable {
    case invalidShape
}

enum AIAssistantDecoder {
    private struct WorkbenchPayload: Decodable {
        let overview: String
        let suggestedTasks: [AISuggestedTask]
        let sections: [AIResultSection]
    }

    static func dailyBrief(from text: String) throws -> AIDailyBriefContent {
        let content = try JSONDecoder().decode(
            AIDailyBriefContent.self,
            from: Data(text.utf8)
        )
        guard isPresent(content.summary),
              isPresent(content.detail),
              !content.evidence.isEmpty,
              content.evidence.allSatisfy(isPresent) else {
            throw AIAssistantDecodingError.invalidShape
        }
        return content
    }

    static func workbench(
        from text: String,
        mode: AIWorkbenchMode,
        source: AIAssistantSource
    ) throws -> AIWorkbenchResult {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let payload = try decoder.decode(WorkbenchPayload.self, from: Data(text.utf8))

        guard isPresent(payload.overview) else {
            throw AIAssistantDecodingError.invalidShape
        }

        switch mode {
        case .todayPlan, .breakdown:
            guard (3...8).contains(payload.suggestedTasks.count),
                  payload.sections.isEmpty,
                  validSuggestedTasks(payload.suggestedTasks) else {
                throw AIAssistantDecodingError.invalidShape
            }
        case .review:
            guard payload.suggestedTasks.isEmpty,
                  payload.sections.map(\.id) == ["progress", "next", "prompt"],
                  payload.sections.allSatisfy({ isPresent($0.title) && isPresent($0.body) }) else {
                throw AIAssistantDecodingError.invalidShape
            }
        }

        return AIWorkbenchResult(
            overview: payload.overview,
            suggestedTasks: payload.suggestedTasks,
            sections: payload.sections,
            source: source
        )
    }

    private static func validSuggestedTasks(_ tasks: [AISuggestedTask]) -> Bool {
        let ids = Set(tasks.map(\.id))
        guard ids.count == tasks.count else { return false }

        return tasks.allSatisfy { task in
            isPresent(task.title)
                && isPresent(task.rationale)
                && task.estimatedMinutes.map { $0 > 0 } != false
                && task.priority.map { (1...5).contains($0) } != false
        }
    }

    private static func isPresent(_ text: String) -> Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

enum LocalAIAssistantPlanner {
    static func dailyBrief(
        context: AIAssistantContext,
        now: Date
    ) -> AIDailyBriefContent {
        let active = context.tasks.filter { !$0.isArchived && $0.status != TodoStatus.done.rawValue }
        let urgent = active.filter {
            guard let dueDate = $0.dueDate else { return false }
            return dueDate < now.addingTimeInterval(86_400)
        }
        let top = active.sorted(by: isHigherPriority).first

        return AIDailyBriefContent(
            summary: top.map {
                Localization.t("ai.brief.localPriority", $0.title)
            } ?? Localization.t("ai.brief.emptySummary"),
            detail: urgent.isEmpty
                ? Localization.t("ai.brief.steadyDetail")
                : Localization.t("ai.brief.deadlineDetail", urgent.count),
            evidence: [
                Localization.t("ai.brief.activeEvidence", active.count),
                Localization.t("ai.brief.deadlineEvidence", urgent.count),
                Localization.t("ai.brief.healthEvidence", context.health)
            ]
        )
    }

    static func workbench(
        mode: AIWorkbenchMode,
        goal: String,
        context: AIAssistantContext,
        now: Date
    ) -> AIWorkbenchResult {
        switch mode {
        case .todayPlan:
            let tasks = context.tasks
                .filter { !$0.isArchived && $0.status != TodoStatus.done.rawValue }
                .sorted(by: isHigherPriority)
                .prefix(5)
                .map {
                    AISuggestedTask(
                        id: $0.id,
                        title: $0.title,
                        rationale: Localization.t("ai.workbench.existingTaskReason"),
                        estimatedMinutes: max(1, $0.estimatedMinutes),
                        priority: min(5, max(1, $0.priority)),
                        dueDate: $0.dueDate
                    )
                }
            return AIWorkbenchResult(
                overview: Localization.t("ai.workbench.localPlanOverview"),
                suggestedTasks: Array(tasks),
                sections: [],
                source: .local
            )

        case .breakdown:
            let cleanGoal = goal.trimmingCharacters(in: .whitespacesAndNewlines)
            let subject = cleanGoal.isEmpty
                ? Localization.t("ai.workbench.defaultGoal")
                : cleanGoal
            let titles = [
                Localization.t("ai.workbench.defineDone", subject),
                Localization.t("ai.workbench.collectContext"),
                Localization.t("ai.workbench.buildMinimum"),
                Localization.t("ai.workbench.verifyResult")
            ]
            let tasks = titles.map {
                AISuggestedTask(
                    id: UUID(),
                    title: $0,
                    rationale: Localization.t("ai.workbench.localReason"),
                    estimatedMinutes: 30,
                    priority: 3,
                    dueDate: nil
                )
            }
            return AIWorkbenchResult(
                overview: Localization.t("ai.workbench.localBreakdownOverview"),
                suggestedTasks: tasks,
                sections: [],
                source: .local
            )

        case .review:
            let completedCount = context.tasks.filter {
                !$0.isArchived && $0.status == TodoStatus.done.rawValue
            }.count
            return AIWorkbenchResult(
                overview: Localization.t("ai.workbench.localReviewOverview"),
                suggestedTasks: [],
                sections: [
                    AIResultSection(
                        id: "progress",
                        title: Localization.t("ai.workbench.progress"),
                        body: Localization.t("ai.workbench.progressBody", completedCount)
                    ),
                    AIResultSection(
                        id: "next",
                        title: Localization.t("ai.workbench.next"),
                        body: Localization.t("ai.workbench.nextBody")
                    ),
                    AIResultSection(
                        id: "prompt",
                        title: Localization.t("ai.workbench.nextPrompt"),
                        body: Localization.t("ai.workbench.nextPromptBody")
                    )
                ],
                source: .local
            )
        }
    }

    private static func isHigherPriority(
        _ lhs: AIAssistantTaskSnapshot,
        _ rhs: AIAssistantTaskSnapshot
    ) -> Bool {
        if lhs.priority != rhs.priority {
            return lhs.priority > rhs.priority
        }
        let lhsDue = lhs.dueDate ?? .distantFuture
        let rhsDue = rhs.dueDate ?? .distantFuture
        if lhsDue != rhsDue {
            return lhsDue < rhsDue
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}

@MainActor
struct LiveAIAssistantService: AIAssistantServing {
    private let transport: any AIAssistantTransporting

    init(transport: any AIAssistantTransporting = OpenAIAssistantTransport()) {
        self.transport = transport
    }

    func dailyBrief(
        context: AIAssistantContext,
        now: Date
    ) async throws -> (AIDailyBriefContent, AIAssistantSource) {
        let fallback = LocalAIAssistantPlanner.dailyBrief(context: context, now: now)
        do {
            let response = try await transport.call(
                promptText: Self.contextPrompt(context),
                instructionText: Self.dailyBriefInstruction
            )
            guard let text = response.text,
                  !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return (fallback, .local)
            }
            return (try AIAssistantDecoder.dailyBrief(from: text), response.source)
        } catch let error as QuotaError {
            if case .quotaExceeded = error {
                throw error
            }
            return (fallback, .local)
        } catch {
            return (fallback, .local)
        }
    }

    func workbench(
        mode: AIWorkbenchMode,
        goal: String,
        context: AIAssistantContext,
        now: Date
    ) async throws -> AIWorkbenchResult {
        let fallback = LocalAIAssistantPlanner.workbench(
            mode: mode,
            goal: goal,
            context: context,
            now: now
        )
        do {
            let response = try await transport.call(
                promptText: "goal=\(goal)\n\(Self.contextPrompt(context))",
                instructionText: Self.workbenchInstruction(mode: mode)
            )
            guard let text = response.text,
                  !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return fallback
            }
            return try AIAssistantDecoder.workbench(
                from: text,
                mode: mode,
                source: response.source
            )
        } catch let error as QuotaError {
            if case .quotaExceeded = error {
                throw error
            }
            return fallback
        } catch {
            return fallback
        }
    }

    private static func contextPrompt(_ context: AIAssistantContext) -> String {
        let rows = context.tasks
            .filter { !$0.isArchived }
            .sorted { $0.id.uuidString < $1.id.uuidString }
            .map {
                "- \($0.title) | \($0.status) | priority=\($0.priority) | minutes=\($0.estimatedMinutes) | due=\($0.dueDate?.ISO8601Format() ?? "none")"
            }
        return (["health=\(context.health)"] + rows).joined(separator: "\n")
    }

    private static let dailyBriefInstruction = "Return only one JSON object with summary:String, detail:String, and a non-empty evidence:[String]. Do not include Markdown fences."

    private static func workbenchInstruction(mode: AIWorkbenchMode) -> String {
        switch mode {
        case .todayPlan, .breakdown:
            return "Return only one JSON object with overview:String, suggestedTasks containing 3 to 8 items with unique UUID id, non-empty title and rationale, estimatedMinutes as a positive integer or null, priority from 1 to 5 or null, dueDate as ISO8601 or null, and sections:[]. Mode=\(mode.rawValue). Do not include Markdown fences."
        case .review:
            return "Return only one JSON object with overview:String, suggestedTasks:[], and exactly three non-empty sections in this order with ids progress, next, prompt. Do not include Markdown fences."
        }
    }
}
