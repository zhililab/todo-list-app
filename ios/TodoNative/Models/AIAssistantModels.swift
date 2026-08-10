import CryptoKit
import Foundation

enum AIWorkbenchMode: String, CaseIterable, Codable, Identifiable, Sendable {
    case todayPlan
    case breakdown
    case review

    var id: String { rawValue }
}

enum AIAssistantSource: String, Codable, Equatable, Sendable {
    case managed
    case custom
    case local
}

struct AIAssistantTaskSnapshot: Codable, Equatable, Sendable {
    let id: UUID
    let title: String
    let status: String
    let priority: Int
    let estimatedMinutes: Int
    let dueDate: Date?
    let isArchived: Bool
}

struct AIAssistantContext: Equatable, Sendable {
    let tasks: [AIAssistantTaskSnapshot]
    let health: Int

    init(tasks: [AIAssistantTaskSnapshot], health: Int) {
        self.tasks = tasks
        self.health = health
    }

    init(items: [TodoItem], health: Int) {
        tasks = items.map {
            AIAssistantTaskSnapshot(
                id: $0.id,
                title: $0.title,
                status: $0.statusRaw,
                priority: $0.priority,
                estimatedMinutes: $0.estimatedMinutes,
                dueDate: $0.dueDate,
                isArchived: $0.isArchived
            )
        }
        self.health = health
    }

    var fingerprint: String {
        let payload = AIAssistantFingerprintPayload(
            health: health,
            tasks: tasks.sorted { $0.id.uuidString < $1.id.uuidString }
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
}

private struct AIAssistantFingerprintPayload: Codable, Sendable {
    let health: Int
    let tasks: [AIAssistantTaskSnapshot]
}

struct AIDailyBriefContent: Codable, Equatable, Sendable {
    let summary: String
    let detail: String
    let evidence: [String]
}

struct AIDailyBrief: Codable, Equatable, Sendable {
    let content: AIDailyBriefContent
    let generatedAt: Date
    let source: AIAssistantSource
    let contextFingerprint: String
}

struct AISuggestedTask: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let title: String
    let rationale: String
    let estimatedMinutes: Int?
    let priority: Int?
    let dueDate: Date?
}

struct AIResultSection: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let title: String
    let body: String
}

struct AIWorkbenchResult: Codable, Equatable, Sendable {
    let overview: String
    let suggestedTasks: [AISuggestedTask]
    let sections: [AIResultSection]
    let source: AIAssistantSource
}
