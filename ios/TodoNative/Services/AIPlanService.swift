import Foundation

final class AIPlanService {
    // 目前先提供离线规则版，后续接真实 AI API
    func generateTodayPlan(from items: [TodoItem]) -> [TodoItem] {
        let incomplete = items.filter { !$0.isArchived && $0.status != .done }
        return incomplete
            .sorted {
                if $0.priority == $1.priority {
                    return ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture)
                }
                return $0.priority > $1.priority
            }
            .prefix(5)
            .map { $0 }
    }

    // 与 web app.js localTodayPlan 保持一致：生成带序号/时段的计划文本（本地降级用）
    func generateTodayPlanText(from items: [TodoItem]) -> String {
        let active = generateTodayPlan(from: items)
        guard !active.isEmpty else { return "队列为空。捕捉一个目标。" }

        var lines = ["今日计划："]
        for (index, item) in active.enumerated() {
            lines.append("\(index + 1). \(item.title)（\(item.taskType.localizedName)，\(Self.priorityLabel(item.priority))，\(Self.effortLabel(minutes: item.estimatedMinutes))）")
        }
        lines.append("")

        // 与 web app.js getNextAction 保持一致
        let firstStep: String
        if let top = active.first {
            if top.context.isEmpty && top.acceptanceCriteria.isEmpty {
                firstStep = "下一步：给「\(top.title)」补 1 条上下文或验收标准。"
            } else {
                firstStep = "下一步：推进「\(top.title)」，建议投入 \(Self.effortLabel(minutes: top.estimatedMinutes))。"
            }
        } else {
            firstStep = ""
        }
        lines.append("第一步：\(firstStep)")
        return lines.joined(separator: "\n")
    }

    static func priorityLabel(_ priority: Int) -> String {
        if priority >= 4 { return "高优先级" }
        if priority == 3 { return "中优先级" }
        return "低优先级"
    }

    static func effortLabel(minutes: Int) -> String {
        minutes >= 60 ? "\(minutes / 60)小时" : "\(minutes)分钟"
    }
}
