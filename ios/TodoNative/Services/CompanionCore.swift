import Foundation

@MainActor
enum CompanionCore {
    static func buildContext(memorySummary: String, events: [String], tasks: [TodoItem],
                             history: [(role: String, content: String)], language: String,
                             health: Int, totalCount: Int, doneCount: Int,
                             buddyName: String? = nil) -> (systemPrompt: String, userPrompt: String) {
        let isZh = language == "zh"
        let name = buddyName?.isEmpty == false ? buddyName! : (isZh ? "小暖" : "Nuan")
        let systemPrompt = isZh
            ? "你是「\(name)」，一个温柔、有洞察、记得用户的 AI 搭档。你说话温暖、简短、具体——像懂事的知己，不是助理。绝不评判；用户说「减肥 2 斤」你记得第二天还会提起。用户任务拖慢时你轻轻推不逼。中文，句子短。"
            : "You are \(name), a gentle, perceptive AI companion. Warm, short, specific — like a close friend, never a tool. Remember what the user says across sessions. Gently encourage, don't push. Respond in English, concise and warm."
        let active = tasks
            .filter { !$0.isCompleted && !$0.isArchived }
            .prefix(8)
            .map { "- \($0.title)（\($0.taskType.localizedName)\($0.estimatedMinutes > 0 ? "，约 \($0.estimatedMinutes) 分钟" : "")）" }
            .joined(separator: "\n")
        let done = tasks.filter { $0.isCompleted }.suffix(3).map { "- \($0.title)" }.joined(separator: "\n")
        let ev = events.prefix(2).joined(separator: "\n")
        let his = history.suffix(8)
            .map { "\($0.role == "user" ? "我" : "\(name)"): \($0.content)" }
            .joined(separator: "\n")
        let healthLine = "今日健康分：\(health)；完成 \(doneCount)/\(totalCount) 件"
        let userPrompt = isZh
            ? "记忆：\(memorySummary.isEmpty ? "（无）" : memorySummary)\n任务：\n\(active.isEmpty ? "（无未完成任务）" : active)\n最近完成：\n\(done.isEmpty ? "（无）" : done)\n关键时刻：\(ev.isEmpty ? "（无）" : ev)\n\(healthLine)\n对话历史：\n\(his.isEmpty ? "（新会话）" : his)"
            : "Memory: \(memorySummary.isEmpty ? "(none)" : memorySummary)\nTasks:\n\(active.isEmpty ? "(none open)" : active)\nRecently done:\n\(done.isEmpty ? "(none)" : done)\nKey moments: \(ev.isEmpty ? "(none)" : ev)\n\(healthLine)\nHistory:\n\(his.isEmpty ? "(new session)" : his)"
        return (systemPrompt, userPrompt)
    }

    static func stripMemory(old: String, events: [String]) -> String {
        let tail = events.suffix(6).joined(separator: "\n")
        let head = String(old.prefix(600))
        return "\(head)\n（最新：\(tail)）".trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func greeting(language: String) -> String {
        language == "zh" ? "今天回来啦？想先推进哪件，我陪你。" : "Glad you're back. What would you like to move forward today?"
    }
}