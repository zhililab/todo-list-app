import Foundation
import XCTest
@testable import TodoNative

@MainActor
final class AIBriefCacheTests: XCTestCase {
    func testRoundTripIsScopedByCalendarDay() {
        let suite = "AIBriefCacheTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let cache: any AIBriefCaching = UserDefaultsAIBriefCache(defaults: defaults)
        let brief = makeBrief(summary: "先发布")

        cache.save(brief, for: "2026-08-09")

        XCTAssertEqual(cache.load(for: "2026-08-09"), brief)
        XCTAssertNil(cache.load(for: "2026-08-10"))
    }

    func testLoadMostRecentReturnsLatestValidBrief() {
        let suite = "AIBriefCacheTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let cache = UserDefaultsAIBriefCache(defaults: defaults)
        let yesterday = makeBrief(summary: "保留昨日简报")
        let today = makeBrief(summary: "今天的新简报")
        cache.save(yesterday, for: "2026-08-08")
        cache.save(today, for: "2026-08-09")
        defaults.set(Data("not a brief".utf8), forKey: "ai_daily_brief.2026-08-10")

        XCTAssertEqual(cache.loadMostRecent(), today)
    }

    func testDayKeyUsesInjectedTimeZones() {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0)!
        var utcPlusEight = Calendar(identifier: .gregorian)
        utcPlusEight.timeZone = TimeZone(secondsFromGMT: 8 * 60 * 60)!
        let instant = utc.date(from: DateComponents(year: 2026, month: 8, day: 8, hour: 16, minute: 30))!

        XCTAssertEqual(AIBriefDayKey.value(for: instant, calendar: utc), "2026-08-08")
        XCTAssertEqual(AIBriefDayKey.value(for: instant, calendar: utcPlusEight), "2026-08-09")
    }

    func testCacheHasASendableMainActorContract() {
        requireSendable(UserDefaultsAIBriefCache.self)
    }

    func testAutomaticAttemptTrackerPersistsAcrossInstancesByDay() {
        let suite = "AIBriefAttemptTrackerTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let first = UserDefaultsAIBriefAttemptTracker(defaults: defaults)
        first.markAutomaticGenerationAttempted(for: "2026-08-09")
        let reconstructed = UserDefaultsAIBriefAttemptTracker(defaults: defaults)

        XCTAssertTrue(reconstructed.hasAttemptedAutomaticGeneration(for: "2026-08-09"))
        XCTAssertFalse(reconstructed.hasAttemptedAutomaticGeneration(for: "2026-08-10"))
    }

    private func makeBrief(summary: String) -> AIDailyBrief {
        AIDailyBrief(
            content: .init(summary: summary, detail: "保护截止任务", evidence: ["1 个截止"]),
            generatedAt: Date(timeIntervalSince1970: 10),
            source: .local,
            contextFingerprint: "abc"
        )
    }

    private func requireSendable<T: Sendable>(_: T.Type) {}
}
