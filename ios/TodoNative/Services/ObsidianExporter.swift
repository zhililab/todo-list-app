import Foundation

enum ObsidianExporter {
    static func makeDailyMarkdown(for items: [TodoItem], date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let dateKey = formatter.string(from: date)
        formatter.dateFormat = "HH:mm"

        var lines: [String] = [
            "# TodoList 每日导出 \(dateKey)",
            "",
            "生成时间：\(formatter.string(from: date))",
            ""
        ]

        let completed = items.filter { $0.status == .done && !$0.isArchived }
        let pending = items.filter { $0.status != .done && !$0.isArchived }

        if !pending.isEmpty {
            lines.append("## 未完成任务")
            for item in pending {
                lines.append("- [ ] \(item.title) （\(item.taskType.localizedName)）")
                if !item.context.isEmpty { lines.append("  - 上下文：\(item.context)") }
                if !item.acceptanceCriteria.isEmpty {
                    lines.append("  - 验收标准：\(item.acceptanceCriteria)")
                }
                if !item.nextPrompt.isEmpty {
                    lines.append("  - 下一步提示：\(item.nextPrompt)")
                }
            }
            lines.append("")
        }

        if !completed.isEmpty {
            lines.append("## 已完成任务")
            for item in completed {
                lines.append("- [x] \(item.title) （\(item.taskType.localizedName)）")
            }
        }

        return lines.joined(separator: "\n")
    }

    static func fileName(date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return "todo-list-app-\(formatter.string(from: date)).md"
    }
}
