import Foundation

@MainActor
enum CompanionEvents {
    struct Moment: Equatable {
        let type: String
        let text: String
        let taskTitle: String?
    }

    static let nudgedKey = "companion_nudged"

    static func completedCountToday(in tasks: [TodoItem], now: Date = Date()) -> Int {
        let calendar = Calendar.current
        return tasks.filter {
            $0.isCompleted && calendar.isDate($0.completedAt ?? .distantPast, inSameDayAs: now)
        }.count
    }

    static func moments(tasks: [TodoItem], completedToday: Int, now: Date = Date(), language: String = Localization.currentLanguage) -> [Moment] {
        let isZh = language == "zh"
        let recentDone = tasks
            .filter { $0.isCompleted }
            .sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }

        var result: [Moment] = []
        if completedToday >= 3 {
            result.append(Moment(
                type: "celebrate",
                text: isZh ? "今天已经完成 \(completedToday) 件了，这节奏很扎实。" : "You've completed \(completedToday) things today — solid momentum.",
                taskTitle: recentDone.first?.title))
        } else if completedToday >= 1, let last = recentDone.first {
            result.append(Moment(
                type: "celebrate",
                text: isZh ? "完成了「\(last.title)」！这一步很扎实，我陪你记下它。" : "You finished \"\(last.title)\"! A solid step — I'm noting it down with you.",
                taskTitle: last.title))
        } else if completedToday >= 1 {
            result.append(Moment(
                type: "celebrate",
                text: isZh ? "今天完成了一件任务，我替你记下。" : "You completed a task today — I'm noting it down.",
                taskTitle: nil))
        }

        let threshold = now.addingTimeInterval(-3 * 86400)
        let stale = tasks
            .filter { !$0.isCompleted && !$0.isArchived && $0.createdAt < threshold && !nudgedIDs.contains($0.id) }
            .sorted { $0.createdAt < $1.createdAt }
            .prefix(2)
        for task in stale {
            result.append(Moment(
                type: "nudge",
                text: isZh ? "那个「\(task.title)」已经放了几天了，要不要给它挪个位子？" : "That \"\(task.title)\" has been sitting for days — want to give it a new spot?",
                taskTitle: task.title))
        }
        return Array(result.prefix(3))
    }

    static var nudgedIDs: Set<UUID> {
        Set((UserDefaults.standard.stringArray(forKey: nudgedKey) ?? []).compactMap { UUID(uuidString: $0) })
    }

    static func markNudged(_ task: TodoItem) {
        var ids = nudgedIDs
        ids.insert(task.id)
        UserDefaults.standard.set(ids.map(\.uuidString), forKey: nudgedKey)
    }

    static func clearNudged() {
        UserDefaults.standard.removeObject(forKey: nudgedKey)
    }
}