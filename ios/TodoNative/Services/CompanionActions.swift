import Foundation

@MainActor
enum CompanionActions {
    static let allowedKinds = ["add_task", "complete_task", "breakdown"]

    struct SuggestedAction: Identifiable, Equatable {
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

    static func parse(_ reply: String, maxActions: Int = 2) -> (text: String, actions: [SuggestedAction]) {
        let text = reply.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}"), start < end else {
            return (text, [])
        }
        let head = String(text[..<start]).trimmingCharacters(in: .whitespacesAndNewlines)
        let tail = String(text[text.index(after: end)...]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let jsonData = String(text[start...end]).data(using: .utf8),
              let json = (try? JSONSerialization.jsonObject(with: jsonData)) as? [String: Any],
              let rawActions = json["actions"] as? [[String: Any]] else {
            return (text, [])
        }
        var actions: [SuggestedAction] = []
        for raw in rawActions {
            guard actions.count < maxActions else { break }
            guard let kind = raw["action"] as? String, allowedKinds.contains(kind) else { continue }
            var payload = (raw["payload"] as? [String: Any])?.compactMapValues { $0 as? String } ?? [:]
            if kind == "add_task" || kind == "breakdown" {
                let text = payload["text"]
                if text == nil || text!.isEmpty {
                    if let fallback = payload["title"] ?? payload["name"] ?? payload["task"] ?? payload["goal"] {
                        payload["text"] = fallback
                    }
                }
            }
            let label = raw["label"] as? String ?? kind
            actions.append(SuggestedAction(label: label, kind: kind, payload: payload))
        }
        let clean = [head, tail].filter { !$0.isEmpty }.joined(separator: "\n")
        return (clean.isEmpty ? text : clean, actions)
    }

    static func extractTaskIntent(_ userText: String) -> String? {
        let zhPatterns = [
            #"(帮我|请|麻烦)?\s*(创建|新建|添加|加上|加个|记下|加入|收下)\s*(一个)?\s*(任务|待办|事项)?\s*[:：]?\s*(.+)"#,
            #"(帮我|请)\s*(创建|添加|记下|收下)\s*(.+)"#
        ]
        let enPattern = #"(?:create|add|remember|note)\s+(?:a\s+)?(?:task|todo)?\s*(?:[:：]\s*)?(.+)"#
        var captured: String?
        for pattern in zhPatterns {
            if let m = matchFirst(pattern, in: userText, caseInsensitive: false) { captured = m; break }
        }
        if captured == nil, let m = matchFirst(enPattern, in: userText, caseInsensitive: true) {
            captured = m
        }
        guard var task = captured?.trimmingCharacters(in: .whitespacesAndNewlines) else { return nil }
        task = task.trimmingCharacters(in: CharacterSet(charactersIn: "：:-"))
        task = task.trimmingCharacters(in: .whitespacesAndNewlines)
        if task.first == "\"" && task.last == "\"" && task.count >= 2 {
            task = String(task.dropFirst().dropLast())
        }
        guard task.count >= 2, task.count <= 40 else { return nil }
        if task.contains("什么") || task.contains("吗") || task.contains("?") || task.contains("？") { return nil }
        return task
    }

    private static func matchFirst(_ pattern: String, in text: String, caseInsensitive: Bool) -> String? {
        var options: NSRegularExpression.Options = []
        if caseInsensitive { options.insert(.caseInsensitive) }
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return nil }
        let fullRange = NSRange(text.startIndex..., in: text)
        guard let result = regex.firstMatch(in: text, options: [], range: fullRange) else { return nil }
        let group = result.range(at: result.numberOfRanges - 1)
        guard group.location != NSNotFound, let range = Range(group, in: text) else { return nil }
        return String(text[range])
    }
}