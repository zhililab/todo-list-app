import Foundation
import SwiftUI

@MainActor
final class CompanionViewModel: ObservableObject {
    @Published var messages: [BuddyMessage] = []
    @Published var input = ""
    @Published var isBusy = false

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

    private static let maxHistory = 40

    init() {
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
        messages.append(BuddyMessage(role: "user", text: trimmed))
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

        let reply: String
        if let text = try? await OpenAIService.callOpenAI(promptText: user, instructionText: system) {
            let parsed = CompanionActions.parse(text)
            let actions = parsed.actions.map { BuddyAction(label: $0.label, kind: $0.kind, payload: $0.payload) }
            reply = parsed.text
            messages.append(BuddyMessage(role: "assistant", text: parsed.text, actions: actions))
        } else {
            reply = Localization.t("buddy.silent")
            messages.append(BuddyMessage(role: "assistant", text: reply))
        }
        isBusy = false
        saveHistory()
        memory = CompanionCore.stripMemory(old: memory, events: [trimmed, reply])
        return reply
    }

    func greetingIfNeeded(language: String) {
        guard UserDefaults.standard.object(forKey: Self.greetingEnabledKey) as? Bool ?? true else { return }
        let today = Self.todayString()
        guard UserDefaults.standard.string(forKey: Self.greetingKey) != today else { return }
        UserDefaults.standard.set(today, forKey: Self.greetingKey)
        messages.append(BuddyMessage(role: "assistant", text: CompanionCore.greeting(language: language)))
        saveHistory()
    }

    func runMoments(items: [TodoItem]) {
        let count = CompanionEvents.completedCountToday(in: items)
        let events = CompanionEvents.moments(tasks: items, completedToday: count)
        for event in events {
            messages.append(BuddyMessage(role: "assistant", text: event.text))
            if event.type == "nudge", let title = event.taskTitle,
               let task = items.first(where: { $0.title == title }) {
                CompanionEvents.markNudged(task)
            }
        }
        if !events.isEmpty { saveHistory() }
    }

    func apply(action: BuddyAction, in vm: TodoViewModel) {
        let title = action.payload["title"] ?? action.payload["text"] ?? ""
        switch action.kind {
        case "add_task":
            if !title.isEmpty {
                vm.captureNaturalLanguage(title, sourceGoal: "companion")
                messages.append(BuddyMessage(role: "assistant", text: Localization.t("buddy.addedTodo")))
            }
        case "complete_task":
            if let item = vm.unarchivedItems.first(where: { $0.title.localizedCaseInsensitiveContains(title) }), !item.isCompleted {
                vm.updateStatus(item, status: .done)
                messages.append(BuddyMessage(role: "assistant", text: Localization.t("buddy.completed")))
            }
        case "breakdown":
            if !title.isEmpty {
                Task {
                    let text = await AIService.breakdown(goal: title, items: vm.unarchivedItems)
                    for task in AIService.extractTasks(from: text) {
                        vm.captureNaturalLanguage(task, sourceGoal: "companion")
                    }
                    messages.append(BuddyMessage(role: "assistant", text: Localization.t("buddy.splitTask")))
                    saveHistory()
                }
            }
        default:
            break
        }
        saveHistory()
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