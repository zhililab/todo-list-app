import Foundation

// 与 web app.js 的 AI 功能保持一致：有 Key 走 OpenAI，无 Key 或失败走本地降级，永远有结果
@MainActor
struct AIService {

    // 功能 1：智能拆解（与 web app.js handleBreakdown 保持一致）
    static func breakdown(goal: String, items: [TodoItem] = []) async -> String {
        let active = items.filter { !$0.isArchived && !$0.isCompleted }
        let context = active.isEmpty
            ? "当前没有未完成任务"
            : "当前未完成任务：\(active.map { $0.title }.joined(separator: "；"))"
        let prompt = "目标：\(goal)\n\(context)"
        return await smartText(
            prompt: prompt,
            instruction: "你是 AI-native todo 的任务规划助手。请给出 5-8 条可执行、可勾选的短任务清单，每行一条，不要额外解释。任务要包含明确动作，避免空泛。语言用中文。",
            fallback: localBreakdown(goal: goal)
        )
    }

    // 功能 2：复盘/下一步（与 web app.js handleSummary 保持一致）
    static func summary(items: [TodoItem], health: Int) async -> String {
        let active = items.filter { !$0.isArchived && !$0.isCompleted }
        let completed = items.filter { !$0.isArchived && $0.isCompleted }

        let completedLines = completed.isEmpty
            ? "- 暂无"
            : completed.map { "- \($0.title)" }.joined(separator: "\n")
        let activeLines = active.isEmpty
            ? "- 暂无"
            : active.map { "- \($0.title)（\($0.taskType.localizedName)，\(AIPlanService.priorityLabel($0.priority))，\(AIPlanService.effortLabel(minutes: $0.estimatedMinutes))）" }.joined(separator: "\n")

        let prompt = "已完成任务:\n\(completedLines)\n\n未完成任务:\n\(activeLines)\n\n健康分: \(health)"
        return await smartText(
            prompt: prompt,
            instruction: "你是项目助理。请输出：1）进展概览（2-3句）；2）下一步建议（3条）；3）最适合交给 AI 的下一条 prompt。语言简洁。",
            fallback: localSummary(items: items, health: health)
        )
    }

    // 功能 3：今日计划（与 web app.js handleTodayPlan 保持一致）
    static func todayPlan(items: [TodoItem]) async -> String {
        let active = items.filter { !$0.isArchived && !$0.isCompleted }
        let list = active.isEmpty
            ? "- 暂无"
            : active.map { "- \($0.title)（\($0.taskType.localizedName)，\(AIPlanService.priorityLabel($0.priority))，\(AIPlanService.effortLabel(minutes: $0.estimatedMinutes))）" }.joined(separator: "\n")
        let prompt = "请基于这些任务生成今天的执行计划：\n\(list)"
        return await smartText(
            prompt: prompt,
            instruction: "你是今日计划助手。请只保留最关键的 3-5 件事，按上午/下午/收尾组织，最后给出第一步。中文输出。",
            fallback: AIPlanService().generateTodayPlanText(from: items)
        )
    }

    // 与 web app.js getSmartText 保持一致：有 AI 结果用它，否则本地降级
    private static func smartText(prompt: String, instruction: String, fallback: String) async -> String {
        if let text = try? await OpenAIService.callOpenAI(promptText: prompt, instructionText: instruction),
           !text.isEmpty {
            return text
        }
        return fallback
    }

    // 与 web app.js extractTasksFromText 保持一致
    static func extractTasks(from text: String) -> [String] {
        let lines = text
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .map { line -> String in
                line.replacingOccurrences(of: "^[-*+•・\\d\\s.)、）(（]+", with: "", options: .regularExpression)
                    .trimmingCharacters(in: .whitespaces)
            }
            .map { line -> String in
                line.replacingOccurrences(of: "^\\[[ xX]\\]\\s*", with: "", options: .regularExpression)
                    .trimmingCharacters(in: .whitespaces)
            }
            .map { line -> String in
                line.replacingOccurrences(of: "^(任务|步骤|Task|Step)\\s*[:：]\\s*", with: "", options: .regularExpression)
                    .trimmingCharacters(in: .whitespaces)
            }
            .filter { $0.count >= 2 && !$0.contains("：") || $0.count >= 8 }
        return Array(lines.prefix(10))
    }

    // 与 web app.js localBreakdown 保持一致
    private static func localBreakdown(goal: String) -> String {
        let clean = goal.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        let subject = clean.count > 42 ? String(clean.prefix(42)) + "..." : clean
        return [
            "明确「\(subject)」的完成定义和不可做范围",
            "列出当前已有资料、相关文件、约束和风险",
            "拆出 1 个 30 分钟内能完成的最小版本",
            "完成核心实现，并记录关键决策到 Agent Notes",
            "补一条验收标准和一次手动验证记录",
            "复盘剩余问题，生成下一条交给 AI 的 prompt"
        ].joined(separator: "\n")
    }

    // 与 web app.js localSummary 保持一致
    private static func localSummary(items: [TodoItem], health: Int) -> String {
        let active = items.filter { !$0.isArchived && !$0.isCompleted }
        let completed = items.filter { !$0.isArchived && $0.isCompleted }
        let high = active.filter { $0.priority >= 4 }
        let missingContext = active.filter { $0.context.isEmpty && $0.acceptanceCriteria.isEmpty }

        let top3 = active.prefix(3).map { $0.title }.joined(separator: "；")
        let line1 = "进展概览：已完成 \(completed.count) 条，进行中 \(active.count) 条。当前健康分 \(health)，\(TodoViewModel.healthLabelStatic(health))。"
        let step1 = high.first.map { "1. 先推进高优先级任务：\($0.title)" } ?? "1. 选择一个最小任务推进，不要同时开太多分支。"
        let step2 = missingContext.first.map { "2. 给「\($0.title)」补上下文和验收标准。" } ?? "2. 已有任务上下文不错，可以直接进入执行。"
        let step3 = "3. 今日只保留 3 个主任务：\(top3.isEmpty ? "暂无" : top3)"
        return [line1, "", "下一步建议：", step1, step2, step3].joined(separator: "\n")
    }
}
