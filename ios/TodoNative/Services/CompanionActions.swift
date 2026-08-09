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
            let payload = (raw["payload"] as? [String: Any])?.compactMapValues { $0 as? String } ?? [:]
            let label = raw["label"] as? String ?? kind
            actions.append(SuggestedAction(label: label, kind: kind, payload: payload))
        }
        let clean = [head, tail].filter { !$0.isEmpty }.joined(separator: "\n")
        return (clean.isEmpty ? text : clean, actions)
    }
}