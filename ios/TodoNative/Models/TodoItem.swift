import Foundation
import SwiftData

@Model
final class TodoItem {
    @Attribute(.unique) var id: UUID
    var title: String
    var context: String
    var acceptanceCriteria: String
    var nextPrompt: String
    var taskTypeRaw: String
    var estimatedMinutes: Int
    var priority: Int
    var statusRaw: String
    var dueDate: Date?
    var isArchived: Bool
    var createdAt: Date
    var updatedAt: Date
    var completedAt: Date?
    var sourceGoal: String = ""

    init(
        title: String,
        context: String = "",
        acceptanceCriteria: String = "",
        nextPrompt: String = "",
        taskType: TaskType = .personal,
        estimatedMinutes: Int = 15,
        priority: Int = 3,
        status: TodoStatus = .todo,
        dueDate: Date? = nil,
        isArchived: Bool = false,
        sourceGoal: String = ""
    ) {
        self.id = UUID()
        self.title = title
        self.context = context
        self.acceptanceCriteria = acceptanceCriteria
        self.nextPrompt = nextPrompt
        self.taskTypeRaw = taskType.rawValue
        self.estimatedMinutes = estimatedMinutes
        self.priority = priority
        self.statusRaw = status.rawValue
        self.dueDate = dueDate
        self.isArchived = isArchived
        self.sourceGoal = sourceGoal
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    var taskType: TaskType {
        get { TaskType(rawValue: taskTypeRaw) ?? .personal }
        set { taskTypeRaw = newValue.rawValue }
    }

    var status: TodoStatus {
        get { TodoStatus(rawValue: statusRaw) ?? .todo }
        set { statusRaw = newValue.rawValue }
    }

    var isCompleted: Bool {
        status == .done
    }
}

enum TaskType: String, Codable, CaseIterable, Identifiable {
    case personal = "Personal"
    case code = "Code"
    case product = "Product"
    case learning = "Learning"
    case life = "Life"

    var id: String { rawValue }

    var localizedName: String {
        switch self {
        case .personal: return Localization.t("taskType.personal")
        case .code: return Localization.t("taskType.code")
        case .product: return Localization.t("taskType.product")
        case .learning: return Localization.t("taskType.learning")
        case .life: return Localization.t("taskType.life")
        }
    }
}

enum TodoStatus: String, Codable, CaseIterable, Identifiable {
    case todo = "todo"
    case doing = "doing"
    case done = "done"
    case archived = "archived"

    var id: String { rawValue }
}
