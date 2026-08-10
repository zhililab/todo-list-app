import Foundation
import SwiftData

@MainActor
final class TodoViewModel: ObservableObject {
    private static let todayFocusStorageKey = "today_focus_ids"
    private static let todayFocusDayStorageKey = "today_focus_day_key"

    private let modelContext: ModelContext
    private let planner = AIPlanService()
    private let reminderScheduler: ReminderScheduling
    private let defaults: UserDefaults
    private let calendar: Calendar
    private let now: () -> Date

    @Published private(set) var items: [TodoItem] = []
    @Published var selectedType: TaskType? = nil
    @Published var selectedStatusFilter: TaskFilter = .all
    @Published var todayPlan: [TodoItem] = []
    @Published private(set) var todayFocusIDs: [UUID] = []

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

    init(
        modelContainer: ModelContainer,
        reminderScheduler: ReminderScheduling? = nil,
        defaults: UserDefaults = .standard,
        calendar: Calendar = .current,
        now: @escaping () -> Date = Date.init
    ) {
        self.modelContext = modelContainer.mainContext
        self.reminderScheduler = reminderScheduler ?? NotificationService()
        self.defaults = defaults
        self.calendar = calendar
        self.now = now
        let currentDayKey = AIBriefDayKey.value(for: now(), calendar: calendar)
        if defaults.string(forKey: Self.todayFocusDayStorageKey) == currentDayKey {
            todayFocusIDs = defaults.stringArray(forKey: Self.todayFocusStorageKey)?
                .compactMap(UUID.init(uuidString:)) ?? []
        } else {
            todayFocusIDs = []
            defaults.set(currentDayKey, forKey: Self.todayFocusDayStorageKey)
            defaults.set([], forKey: Self.todayFocusStorageKey)
        }
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

    func addItem(title: String, type: TaskType, context: String, criteria: String, prompt: String, minutes: Int, priority: Int, dueDate: Date? = nil) {
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
            status: .todo,
            dueDate: dueDate
        )
        modelContext.insert(item)
        if let dueDate {
            reminderScheduler.scheduleDueReminder(taskID: item.id, title: item.title, dueDate: dueDate)
        }
        save()
    }

    // 对齐 web app.js inferMeta：从自然语言推断优先级与时长
    @discardableResult
    func captureNaturalLanguage(
        _ text: String,
        type: TaskType = .personal,
        sourceGoal: String = "",
        dueDate: Date? = nil,
        estimatedMinutes: Int? = nil,
        priority: Int? = nil,
        inferDueDateWhenMissing: Bool = true
    ) -> UUID? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let lower = trimmed.lowercased()

        let highWords = ["上线", "发布", "修复", "紧急", "今天", "deadline", "bug", "安全", "阻塞"]
        let lowWords = ["阅读", "整理", "以后", "备忘", "想法"]
        let resolvedPriority = priority ?? {
            if highWords.contains(where: lower.contains) { return 5 }
            if lowWords.contains(where: lower.contains) { return 1 }
            return 3
        }()

        let resolvedMinutes = estimatedMinutes ?? {
            var inferred = 15
            if let match = trimmed.range(of: #"(\d+)\s*(分钟|min|小时|h)"#, options: .regularExpression) {
                let token = String(trimmed[match]).lowercased()
                if token.contains("小时") || token.contains("h") {
                    let raw = token.prefix { $0.isNumber }
                    inferred = max(5, (Int(raw) ?? 1) * 60)
                } else {
                    let raw = token.prefix { $0.isNumber }
                    inferred = max(5, Int(raw) ?? 15)
                }
            }
            return inferred
        }()

        // 无显式到期时，尝试从文本推断（今天/明天/后天/X小时后/X点），供本地提醒调度
        let resolvedDue = dueDate ?? (inferDueDateWhenMissing ? DueDateParser.parse(from: text) : nil)
        let item = TodoItem(
            title: trimmed,
            taskType: type,
            estimatedMinutes: resolvedMinutes,
            priority: resolvedPriority,
            status: .todo,
            dueDate: resolvedDue,
            sourceGoal: sourceGoal
        )
        modelContext.insert(item)
        if let resolvedDue {
            reminderScheduler.scheduleDueReminder(taskID: item.id, title: item.title, dueDate: resolvedDue)
        }
        save()
        return item.id
    }

    @discardableResult
    func importSuggestedTasks(
        _ tasks: [AISuggestedTask],
        type: TaskType = .personal,
        sourceGoal: String
    ) -> [UUID] {
        tasks.compactMap { task in
            captureNaturalLanguage(
                task.title,
                type: type,
                sourceGoal: sourceGoal,
                dueDate: task.dueDate,
                estimatedMinutes: task.estimatedMinutes,
                priority: task.priority,
                inferDueDateWhenMissing: false
            )
        }
    }

    @discardableResult
    func applyTodayPlan(
        _ application: AIWorkbenchApplication,
        type: TaskType = .personal,
        sourceGoal: String
    ) -> Int {
        let importedIDs = importSuggestedTasks(
            application.newTasks,
            type: type,
            sourceGoal: sourceGoal
        )
        applyTodayFocus(application.existingTaskIDs + importedIDs)
        return todayFocusIDs.count
    }

    func applyTodayFocus(_ ids: [UUID]) {
        resetTodayFocusIfNeeded()
        let eligibleIDs = Set(
            items.lazy
                .filter { !$0.isArchived && !$0.isCompleted }
                .map(\.id)
        )
        var seen = Set<UUID>()
        todayFocusIDs = ids.filter {
            eligibleIDs.contains($0) && seen.insert($0).inserted
        }
        persistTodayFocus()
        generatePlan()
    }

    func updateStatus(_ item: TodoItem, status: TodoStatus) {
        item.status = status
        item.updatedAt = Date()
        if status == .done {
            item.completedAt = Date()
        } else if status == .todo || status == .doing {
            item.completedAt = nil
        }
        syncReminder(for: item)
        save()
    }

    func updateItem(_ item: TodoItem, title: String, context: String, criteria: String, prompt: String, minutes: Int, priority: Int, dueDate: Date?) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            item.title = trimmed
        }
        item.context = context
        item.acceptanceCriteria = criteria
        item.nextPrompt = prompt
        item.estimatedMinutes = minutes
        item.priority = priority
        item.dueDate = dueDate
        item.updatedAt = Date()
        syncReminder(for: item)
        save()
    }

    func clearCompleted() {
        for item in completedItems {
            reminderScheduler.cancelReminder(taskID: item.id)
            modelContext.delete(item)
        }
        save()
    }

    func delete(_ item: TodoItem) {
        reminderScheduler.cancelReminder(taskID: item.id)
        modelContext.delete(item)
        save()
    }

    func archive(_ item: TodoItem) {
        reminderScheduler.cancelReminder(taskID: item.id)
        item.isArchived = true
        item.updatedAt = Date()
        save()
    }

    func generatePlan() {
        resetTodayFocusIfNeeded()
        let eligibleItems = items.filter { !$0.isArchived && !$0.isCompleted }
        let itemsByID = Dictionary(uniqueKeysWithValues: eligibleItems.map { ($0.id, $0) })
        var seen = Set<UUID>()
        let cleanedFocusIDs = todayFocusIDs.filter {
            itemsByID[$0] != nil && seen.insert($0).inserted
        }
        if cleanedFocusIDs != todayFocusIDs {
            todayFocusIDs = cleanedFocusIDs
            persistTodayFocus()
        }

        let focused = cleanedFocusIDs.compactMap { itemsByID[$0] }
        let fallback = planner.generateTodayPlan(from: items).filter {
            !seen.contains($0.id)
        }
        todayPlan = Array((focused + fallback).prefix(5))
    }

    func refreshTodayPlan() {
        generatePlan()
    }

    func restoreDueReminders(now: Date = Date()) {
        for item in items where isReminderEligible(item) {
            guard let dueDate = item.dueDate, dueDate > now else { continue }
            reminderScheduler.scheduleDueReminder(taskID: item.id, title: item.title, dueDate: dueDate)
        }
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

    private func persistTodayFocus() {
        defaults.set(currentDayKey, forKey: Self.todayFocusDayStorageKey)
        defaults.set(todayFocusIDs.map(\.uuidString), forKey: Self.todayFocusStorageKey)
    }

    private var currentDayKey: String {
        AIBriefDayKey.value(for: now(), calendar: calendar)
    }

    private func resetTodayFocusIfNeeded() {
        guard defaults.string(forKey: Self.todayFocusDayStorageKey) != currentDayKey else { return }
        todayFocusIDs = []
        persistTodayFocus()
    }

    private func syncReminder(for item: TodoItem) {
        guard isReminderEligible(item), let dueDate = item.dueDate else {
            reminderScheduler.cancelReminder(taskID: item.id)
            return
        }
        reminderScheduler.scheduleDueReminder(taskID: item.id, title: item.title, dueDate: dueDate)
    }

    private func isReminderEligible(_ item: TodoItem) -> Bool {
        !item.isArchived && (item.status == .todo || item.status == .doing)
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
