import CryptoKit
import Foundation

enum AISelectedGoalEligibility {
    static func eligibleTitle(for item: TodoItem) -> String? {
        let title = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            !item.isArchived,
            item.status == .todo || item.status == .doing,
            !title.isEmpty
        else { return nil }
        return title
    }
}

struct AISelectedGoalContext: Codable, Equatable, Sendable {
    let id: UUID
    let title: String
    let context: String
    let acceptanceCriteria: String
    let nextPrompt: String
    let taskType: String
    let priority: Int
    let estimatedMinutes: Int
    let dueDate: Date?

    init?(item: TodoItem) {
        guard let title = AISelectedGoalEligibility.eligibleTitle(for: item) else { return nil }

        id = item.id
        self.title = title
        context = item.context
        acceptanceCriteria = item.acceptanceCriteria
        nextPrompt = item.nextPrompt
        taskType = item.taskTypeRaw
        priority = item.priority
        estimatedMinutes = item.estimatedMinutes
        dueDate = item.dueDate
    }

    var fingerprint: String {
        let payload = AISelectedGoalFingerprintPayload(
            id: id,
            title: title,
            context: context,
            acceptanceCriteria: acceptanceCriteria,
            nextPrompt: nextPrompt,
            taskType: taskType,
            priority: priority,
            estimatedMinutes: estimatedMinutes,
            dueDate: dueDate
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(date.timeIntervalSince1970.bitPattern)
        }
        let data = try! encoder.encode(payload)

        return SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }

    var promptJSON: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return String(decoding: try! encoder.encode(self), as: UTF8.self)
    }
}

private struct AISelectedGoalFingerprintPayload: Codable, Sendable {
    let id: UUID
    let title: String
    let context: String
    let acceptanceCriteria: String
    let nextPrompt: String
    let taskType: String
    let priority: Int
    let estimatedMinutes: Int
    let dueDate: Date?
}
