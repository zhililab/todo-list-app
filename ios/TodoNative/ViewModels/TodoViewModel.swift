import Foundation
import SwiftData

@MainActor
final class TodoViewModel: ObservableObject {
    private let modelContext: ModelContext
    private let planner = AIPlanService()

    @Published private(set) var items: [TodoItem] = []
    @Published var selectedType: TaskType? = nil
    @Published var selectedStatusFilter: TaskFilter = .all
    @Published var todayPlan: [TodoItem] = []

    var unarchivedItems: [TodoItem] {
        items.filter { !$0.isArchived }
    }

    var completedItems: [TodoItem] {
        unarchivedItems.filter { $0.status == .done }
    }

    var doingItems: [TodoItem] {
        unarchivedItems.filter { $0.status == .doing }
    }

    var todoItems: [TodoItem] {
        unarchivedItems.filter { $0.status == .todo }
    }

    var highPriorityItems: [TodoItem] {
        unarchivedItems.filter { !$0.isCompleted && $0.priority >= 4 }
    }

    var completionRate: Int {
        let total = unarchivedItems.count
        guard total > 0 else { return 0 }
        return Int(((Double(completedItems.count) / Double(total)) * 100).rounded(.toNearestOrAwayFromZero))
    }

    // 与 web app.js calculateHealthScore 一致：
    // 完成率 45 分 + 上下文完整度 35 分 + 负载 20 分 - 高优先级未完成惩罚
    var healthScore: Int {
        let total = unarchivedItems.count
        guard total > 0 else { return 0 }

        let completed = completedItems.count
        let active = total - completed
        let withContext = unarchivedItems.filter { !$0.context.isEmpty || !$0.acceptanceCriteria.isEmpty || !$0.nextPrompt.isEmpty }.count
        let highOpen = highPriorityItems.count

        let completionScore = Int((Double(completed) / Double(total) * 45).rounded())
        let contextScore = Int((Double(withContext) / Double(total) * 35).rounded())
        let loadScore = active <= 5 ? 20 : max(4, 20 - (active - 5) * 3)
        let penalty = min(15, max(0, highOpen - 2) * 5)

        return max(0, min(100, completionScore + contextScore + loadScore - penalty))
    }

    static func healthLabelStatic(_ score: Int) -> String {
        if score <= 0 { return Localization.t("health.wait") }
        if score >= 80 { return Localization.t("health.good") }
        if score >= 60 { return Localization.t("health.forward") }
        if score >= 40 { return Localization.t("health.context") }
        return Localization.t("health.breakdown")
    }

    func healthLabel(for score: Int? = nil) -> String {
        Self.healthLabelStatic(score ?? healthScore)
    }

    init(modelContainer: ModelContainer) {
        self.modelContext = modelContainer.mainContext
        fetchItems()
        generatePlan()
    }

    var filteredItems: [TodoItem] {
        let typeFiltered = selectedType == nil ? unarchivedItems : unarchivedItems.filter { $0.taskType == selectedType }
        let statusFiltered: [TodoItem]
        switch selectedStatusFilter {
        case .all: statusFiltered = typeFiltered
        case .active: statusFiltered = typeFiltered.filter { !$0.isCompleted }
        case .completed: statusFiltered = typeFiltered.filter { $0.isCompleted }
        case .high: statusFiltered = typeFiltered.filter { !$0.isCompleted && $0.priority >= 4 }
        }
        return statusFiltered.sorted {
            if $0.status == $1.status {
                return $0.priority > $1.priority
            }
            return $0.status.rawValue < $1.status.rawValue
        }
    }

    func fetchItems() {
        let descriptor = FetchDescriptor<TodoItem>(
            predicate: #Predicate { item in
                !item.isArchived
            },
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        do {
            items = try modelContext.fetch(descriptor)
        } catch {
            print("Fetch error: \(error)")
            items = []
        }
    }

    func addItem(title: String, type: TaskType, context: String, criteria: String, prompt: String, minutes: Int, priority: Int) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let item = TodoItem(
            title: trimmed,
            context: context,
            acceptanceCriteria: criteria,
            nextPrompt: prompt,
            taskType: type,
            estimatedMinutes: minutes,
            priority: priority,
            status: .todo
        )
        modelContext.insert(item)
        save()
    }

    // 对齐 web app.js inferMeta：从自然语言推断优先级与时长
    func captureNaturalLanguage(_ text: String, type: TaskType = .personal, sourceGoal: String = "") {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let lower = trimmed.lowercased()

        let highWords = ["上线", "发布", "修复", "紧急", "今天", "deadline", "bug", "安全", "阻塞"]
        let lowWords = ["阅读", "整理", "以后", "备忘", "想法"]
        let priority: Int
        if highWords.contains(where: lower.contains) {
            priority = 5
        } else if lowWords.contains(where: lower.contains) {
            priority = 1
        } else {
            priority = 3
        }

        var minutes = 15
        if let match = trimmed.range(of: #"(\d+)\s*(分钟|min|小时|h)"#, options: .regularExpression) {
            let token = String(trimmed[match]).lowercased()
            if token.contains("小时") || token.contains("h") {
                let raw = token.prefix { $0.isNumber } ?? "1"
                minutes = max(5, (Int(raw) ?? 1) * 60)
            } else {
                let raw = token.prefix { $0.isNumber } ?? "15"
                minutes = max(5, Int(raw) ?? 15)
            }
        }

        let item = TodoItem(
            title: trimmed,
            taskType: type,
            estimatedMinutes: minutes,
            priority: priority,
            status: .todo,
            sourceGoal: sourceGoal
        )
        modelContext.insert(item)
        save()
    }

    func updateStatus(_ item: TodoItem, status: TodoStatus) {
        item.status = status
        item.updatedAt = Date()
        if status == .done { item.completedAt = Date() }
        save()
    }

    func updateItem(_ item: TodoItem, title: String, context: String, criteria: String, prompt: String, minutes: Int, priority: Int) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            item.title = trimmed
        }
        item.context = context
        item.acceptanceCriteria = criteria
        item.nextPrompt = prompt
        item.estimatedMinutes = minutes
        item.priority = priority
        item.updatedAt = Date()
        save()
    }

    func clearCompleted() {
        for item in completedItems {
            modelContext.delete(item)
        }
        save()
    }

    func delete(_ item: TodoItem) {
        modelContext.delete(item)
        save()
    }

    func archive(_ item: TodoItem) {
        item.isArchived = true
        item.updatedAt = Date()
        save()
    }

    func generatePlan() {
        todayPlan = planner.generateTodayPlan(from: items)
    }

    func exportMarkdown(for targetDate: Date = Date()) -> String {
        return ObsidianExporter.makeDailyMarkdown(for: items, date: targetDate)
    }

    private func save() {
        do {
            try modelContext.save()
            fetchItems()
            generatePlan()
        } catch {
            print("Save error: \(error)")
        }
    }
}

enum TaskFilter: String, CaseIterable, Identifiable {
    case all = "全部"
    case active = "进行中"
    case completed = "已完成"
    case high = "高优先级"

    var id: String { rawValue }

    var localizedName: String {
        switch self {
        case .all: return Localization.t("filter.all")
        case .active: return Localization.t("filter.active")
        case .completed: return Localization.t("filter.completed")
        case .high: return Localization.t("filter.high")
        }
    }
}
