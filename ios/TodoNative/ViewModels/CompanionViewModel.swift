import Foundation
import SwiftUI

@MainActor
final class CompanionViewModel: ObservableObject {
    typealias ChatOperation = ([[String: String]]) async throws -> String?
    typealias BreakdownOperation = @MainActor (String, [TodoItem]) async throws -> String

    private struct PendingRemoteSend {
        let routeIdentifier: String
        let originalText: String
        let payload: [[String: String]]
        let context: AIAssistantContext
    }

    private struct PendingBreakdown {
        let routeIdentifier: String
        let goal: String
        let todoViewModel: TodoViewModel
    }

    @Published var messages: [BuddyMessage] = []
    @Published var input = ""
    @Published var isBusy = false
    @Published var isTyping = false

    struct BuddyMessage: Identifiable, Codable {
        let id: UUID
        let role: String
        let text: String
        var actions: [BuddyAction]

        init(role: String, text: String, actions: [BuddyAction] = []) {
            self.id = UUID()
            self.role = role
            self.text = text
            self.actions = actions
        }
    }

    struct BuddyAction: Identifiable, Codable {
        let id: UUID
        let label: String
        let kind: String
        let payload: [String: String]

        init(label: String, kind: String, payload: [String: String]) {
            self.id = UUID()
            self.label = label
            self.kind = kind
            self.payload = payload
        }
    }

    static let memoryKey = "companion_memory"
    static let historyKey = "companion_history"
    static let greetingKey = "companion_greeting"
    static let nameKey = "companion_name"
    static let greetingEnabledKey = "companion_greeting_enabled"
    static let celebratedKey = "companion_celebrated"

    private static let maxHistory = 40
    private let consentManager: AIConsentManager
    private let chat: ChatOperation
    private let breakdown: BreakdownOperation
    private var pendingRemoteSend: PendingRemoteSend?
    private var pendingBreakdown: PendingBreakdown?

    init(
        consentManager: AIConsentManager = OpenAIService.consentManager,
        chat: @escaping ChatOperation = { messages in
            try await OpenAIService.callChat(messages: messages)
        },
        breakdown: @escaping BreakdownOperation = { goal, items in
            try await AIService.breakdown(goal: goal, items: items)
        }
    ) {
        self.consentManager = consentManager
        self.chat = chat
        self.breakdown = breakdown
        loadHistory()
    }

    var memory: String {
        get { UserDefaults.standard.string(forKey: Self.memoryKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: Self.memoryKey) }
    }

    var buddyName: String {
        UserDefaults.standard.string(forKey: Self.nameKey)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    func send(items: [TodoItem], health: Int, language: String, events: [String] = []) async -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isBusy else { return nil }
        isBusy = true
        isTyping = true
        appendAnimated(BuddyMessage(role: "user", text: trimmed))
        input = ""
        saveHistory()

        let name = buddyName.isEmpty ? nil : buddyName
        let history = messages.map { (role: $0.role, content: $0.text) }
        let (system, user) = CompanionCore.buildContext(
            memorySummary: memory, events: events, tasks: items,
            history: history, language: language, health: health,
            totalCount: items.count,
            doneCount: items.filter(\.isCompleted).count,
            buddyName: name)

        let request = PendingRemoteSend(
            routeIdentifier: "",
            originalText: trimmed,
            payload: [
                ["role": "system", "content": system],
                ["role": "user", "content": user]
            ],
            context: AIAssistantContext(items: items, health: health)
        )
        return await performRemoteSend(request)
    }

    func resolvePendingConsent(_ resolution: AIConsentResolution?) async -> String? {
        guard let resolution, !isBusy else { return nil }
        if let pendingRemoteSend,
           pendingRemoteSend.routeIdentifier == resolution.route.identifier {
            self.pendingRemoteSend = nil
            isBusy = true
            isTyping = true
            return await performRemoteSend(pendingRemoteSend)
        }
        if let pendingBreakdown,
           pendingBreakdown.routeIdentifier == resolution.route.identifier {
            self.pendingBreakdown = nil
            await performBreakdown(
                goal: pendingBreakdown.goal,
                in: pendingBreakdown.todoViewModel
            )
        }
        return nil
    }

    private func performRemoteSend(_ request: PendingRemoteSend) async -> String? {
        do {
            let text = try await chat(request.payload)
            if let text, !text.isEmpty {
                let parsed = CompanionActions.parse(text)
                var actions = parsed.actions.map { BuddyAction(label: $0.label, kind: $0.kind, payload: $0.payload) }
                if actions.isEmpty, let taskText = CompanionActions.extractTaskIntent(request.originalText) {
                    actions = [BuddyAction(label: Localization.t("buddy.addTodo"), kind: "add_task", payload: ["text": taskText])]
                }
                appendAnimated(BuddyMessage(role: "assistant", text: parsed.text, actions: actions))
                return finishSend(reply: parsed.text, originalText: request.originalText)
            } else {
                return finishWithLocalPlanner(request)
            }
        } catch RemoteAIConsentError.needsConsent(let route) {
            pendingRemoteSend = PendingRemoteSend(
                routeIdentifier: route.identifier,
                originalText: request.originalText,
                payload: request.payload,
                context: request.context
            )
            consentManager.requestConsent(for: route)
            isTyping = false
            isBusy = false
            saveHistory()
            return nil
        } catch RemoteAIConsentError.declined {
            return finishWithLocalPlanner(request)
        } catch let error as QuotaError {
            let reply = quotaMessage(for: error)
            appendAnimated(BuddyMessage(role: "assistant", text: reply))
            return finishSend(reply: reply, originalText: request.originalText)
        } catch {
            let reply = Localization.t("buddy.silent")
            appendAnimated(BuddyMessage(role: "assistant", text: reply))
            return finishSend(reply: reply, originalText: request.originalText)
        }
    }

    private func finishWithLocalPlanner(_ request: PendingRemoteSend) -> String {
        let result = LocalAIAssistantPlanner.workbench(
            mode: .breakdown,
            goal: request.originalText,
            context: request.context,
            now: Date()
        )
        let actions = result.suggestedTasks.map {
            BuddyAction(
                label: Localization.t("buddy.addTodo"),
                kind: "add_task",
                payload: ["text": $0.title]
            )
        }
        appendAnimated(BuddyMessage(role: "assistant", text: result.overview, actions: actions))
        return finishSend(reply: result.overview, originalText: request.originalText)
    }

    private func finishSend(reply: String, originalText: String) -> String {
        isTyping = false
        isBusy = false
        saveHistory()
        memory = CompanionCore.stripMemory(old: memory, events: [originalText, reply])
        return reply
    }

    private func quotaMessage(for error: QuotaError) -> String {
        if case .quotaExceeded(let kind) = error {
            return kind == "daily"
                ? Localization.t("quota.exceeded.daily")
                : Localization.t("quota.exceeded.free")
        }
        return error.localizedDescription
    }

    // Visual transitions belong to the view so they can follow environment accessibility settings.
    private func appendAnimated(_ message: BuddyMessage) {
        messages.append(message)
    }

    func greetingIfNeeded(language: String) {
        guard UserDefaults.standard.object(forKey: Self.greetingEnabledKey) as? Bool ?? true else { return }
        let today = Self.todayString()
        guard UserDefaults.standard.string(forKey: Self.greetingKey) != today else { return }
        UserDefaults.standard.set(today, forKey: Self.greetingKey)
        appendAnimated(BuddyMessage(role: "assistant", text: CompanionCore.greeting(language: language)))
        saveHistory()
    }

    func runMoments(items: [TodoItem], storage: UserDefaults = .standard) {
        let count = CompanionEvents.completedCountToday(in: items)
        let events = CompanionEvents.moments(tasks: items, completedToday: count)
        let today = Self.todayString()
        let skipCelebrate = !Self.shouldCelebrate(today: today, storage: storage)
        var appended = false
        for event in events {
            if event.type == "celebrate" && skipCelebrate { continue }
            appendAnimated(BuddyMessage(role: "assistant", text: event.text))
            appended = true
            if event.type == "nudge", let title = event.taskTitle,
               let task = items.first(where: { $0.title == title }) {
                CompanionEvents.markNudged(task)
            }
        }
        if appended {
            if events.contains(where: { $0.type == "celebrate" }) && !skipCelebrate {
                Self.markCelebrated(today: today, storage: storage)
            }
            saveHistory()
        }
    }

    static func shouldCelebrate(today: String, storage: UserDefaults = .standard) -> Bool {
        storage.string(forKey: celebratedKey) != today
    }

    static func markCelebrated(today: String, storage: UserDefaults = .standard) {
        storage.set(today, forKey: celebratedKey)
    }

    func apply(action: BuddyAction, in vm: TodoViewModel) {
        let title = action.payload["text"] ?? action.payload["title"] ?? action.payload["name"] ?? action.payload["task"] ?? action.payload["goal"] ?? ""
        switch action.kind {
        case "add_task":
            if !title.isEmpty {
                vm.captureNaturalLanguage(title, sourceGoal: "companion")
                appendAnimated(BuddyMessage(role: "assistant", text: Localization.t("buddy.addedTodo")))
            }
        case "complete_task":
            if let item = vm.unarchivedItems.first(where: { $0.title.localizedCaseInsensitiveContains(title) }), !item.isCompleted {
                vm.updateStatus(item, status: .done)
                appendAnimated(BuddyMessage(role: "assistant", text: Localization.t("buddy.completed")))
            }
        case "breakdown":
            if !title.isEmpty {
                Task {
                    await performBreakdown(goal: title, in: vm)
                }
            }
        default:
            break
        }
        saveHistory()
    }

    private func performBreakdown(goal: String, in vm: TodoViewModel) async {
        do {
            let text = try await breakdown(goal, vm.unarchivedItems)
            for task in AIService.extractTasks(from: text) {
                vm.captureNaturalLanguage(task, sourceGoal: "companion")
            }
            appendAnimated(
                BuddyMessage(role: "assistant", text: Localization.t("buddy.splitTask"))
            )
            saveHistory()
        } catch RemoteAIConsentError.needsConsent(let route) {
            pendingBreakdown = PendingBreakdown(
                routeIdentifier: route.identifier,
                goal: goal,
                todoViewModel: vm
            )
            consentManager.requestConsent(for: route)
        } catch let error as QuotaError {
            appendAnimated(BuddyMessage(role: "assistant", text: quotaMessage(for: error)))
            saveHistory()
        } catch {
            appendAnimated(
                BuddyMessage(role: "assistant", text: Localization.t("buddy.silent"))
            )
            saveHistory()
        }
    }

    private func loadHistory() {
        guard let data = UserDefaults.standard.data(forKey: Self.historyKey),
              let decoded = try? JSONDecoder().decode([BuddyMessage].self, from: data) else { return }
        messages = decoded
    }

    private func saveHistory() {
        let kept = Array(messages.suffix(Self.maxHistory))
        if let data = try? JSONEncoder().encode(kept) {
            UserDefaults.standard.set(data, forKey: Self.historyKey)
        }
    }

    static func todayString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }
}
