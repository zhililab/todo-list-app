import Foundation

@MainActor
protocol AIBriefCaching: AnyObject {
    func load(for dayKey: String) -> AIDailyBrief?
    func loadMostRecent() -> AIDailyBrief?
    func save(_ brief: AIDailyBrief, for dayKey: String)
}

@MainActor
protocol AIBriefAutoAttemptTracking: AnyObject {
    func hasAttemptedAutomaticGeneration(for dayKey: String) -> Bool
    func markAutomaticGenerationAttempted(for dayKey: String)
}

enum AIBriefDayKey {
    static func value(for date: Date, calendar: Calendar = .current) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
    }
}

@MainActor
final class UserDefaultsAIBriefCache: AIBriefCaching {
    private let defaults: UserDefaults
    private let prefix = "ai_daily_brief."

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load(for dayKey: String) -> AIDailyBrief? {
        guard let data = defaults.data(forKey: key(for: dayKey)) else { return nil }
        return try? JSONDecoder().decode(AIDailyBrief.self, from: data)
    }

    func loadMostRecent() -> AIDailyBrief? {
        let entries = defaults.dictionaryRepresentation()
            .compactMap { key, value -> (String, Data)? in
                guard key.hasPrefix(prefix), let data = value as? Data else { return nil }
                return (key, data)
            }
            .sorted { $0.0 > $1.0 }

        return entries.lazy.compactMap { _, data in
            try? JSONDecoder().decode(AIDailyBrief.self, from: data)
        }.first
    }

    func save(_ brief: AIDailyBrief, for dayKey: String) {
        guard let data = try? JSONEncoder().encode(brief) else { return }
        defaults.set(data, forKey: key(for: dayKey))
    }

    private func key(for dayKey: String) -> String {
        prefix + dayKey
    }
}

@MainActor
final class UserDefaultsAIBriefAttemptTracker: AIBriefAutoAttemptTracking {
    private let defaults: UserDefaults
    private let prefix = "ai_daily_brief_auto_attempt."

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func hasAttemptedAutomaticGeneration(for dayKey: String) -> Bool {
        defaults.bool(forKey: key(for: dayKey))
    }

    func markAutomaticGenerationAttempted(for dayKey: String) {
        defaults.set(true, forKey: key(for: dayKey))
    }

    private func key(for dayKey: String) -> String {
        prefix + dayKey
    }
}
