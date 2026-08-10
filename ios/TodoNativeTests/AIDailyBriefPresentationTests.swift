import XCTest
@testable import TodoNative

final class AIDailyBriefPresentationTests: XCTestCase {
    private let generatedAt = Date(timeIntervalSince1970: 1_786_233_600)

    func testIdlePresentationKeepsStableEmptyState() {
        let presentation = AIDailyBriefPresentation(
            state: .idle,
            isStale: false
        )

        XCTAssertEqual(presentation.phase, .idle)
        XCTAssertNil(presentation.brief)
        XCTAssertFalse(presentation.showsProgress)
        XCTAssertTrue(presentation.canRefresh)
    }

    func testInitialLoadingHasNoBriefAndShowsProgress() {
        let presentation = AIDailyBriefPresentation(
            state: .loading(previous: nil),
            isStale: false
        )

        XCTAssertEqual(presentation.phase, .initialLoading)
        XCTAssertNil(presentation.brief)
        XCTAssertTrue(presentation.showsProgress)
        XCTAssertEqual(presentation.announcement, .loading)
    }

    func testRefreshingKeepsPreviousBriefVisible() {
        let previous = makeBrief(source: .managed)
        let presentation = AIDailyBriefPresentation(
            state: .loading(previous: previous),
            isStale: true
        )

        XCTAssertEqual(presentation.phase, .refreshing)
        XCTAssertEqual(presentation.brief, previous)
        XCTAssertTrue(presentation.showsProgress)
        XCTAssertEqual(presentation.badges, [.updateAvailable])
        XCTAssertEqual(presentation.announcement, .refreshing)
    }

    func testLoadedRemoteBriefShowsUpdatedTimeWithoutSourceBadge() {
        let brief = makeBrief(source: .managed)
        let presentation = AIDailyBriefPresentation(
            state: .loaded(brief),
            isStale: false
        )

        XCTAssertEqual(presentation.phase, .content)
        XCTAssertEqual(presentation.generatedAt, generatedAt)
        XCTAssertTrue(presentation.badges.isEmpty)
    }

    func testLocalStaleBriefShowsBothLocalAndUpdateBadges() {
        let brief = makeBrief(source: .local)
        let presentation = AIDailyBriefPresentation(
            state: .loaded(brief),
            isStale: true
        )

        XCTAssertEqual(presentation.badges, [.localSuggestion, .updateAvailable])
    }

    func testQuotaFailureKeepsPreviousBriefAndTypedRecovery() {
        let previous = makeBrief(source: .custom)
        let failure = AIAssistantFailure(error: QuotaError.quotaExceeded(kind: "daily"))
        let presentation = AIDailyBriefPresentation(
            state: .failed(previous: previous, failure: failure),
            isStale: false
        )

        XCTAssertEqual(presentation.phase, .failure)
        XCTAssertEqual(presentation.brief, previous)
        XCTAssertEqual(presentation.failure?.kind, .quotaExceeded(kind: "daily"))
        XCTAssertEqual(presentation.recovery, [.manageSubscription, .configureProvider])
        XCTAssertEqual(presentation.badges, [.updateAvailable])
        XCTAssertEqual(presentation.announcement, .failure(failure.message))
    }

    func testGenericFailureWithoutPreviousBriefHasNoRecoveryActions() {
        let failure = AIAssistantFailure(error: TestFailure.offline)
        let presentation = AIDailyBriefPresentation(
            state: .failed(previous: nil, failure: failure),
            isStale: false
        )

        XCTAssertEqual(presentation.phase, .failure)
        XCTAssertNil(presentation.brief)
        XCTAssertEqual(presentation.failure?.kind, .other)
        XCTAssertTrue(presentation.recovery.isEmpty)
        XCTAssertEqual(presentation.announcement, .failure("网络不可用"))
    }

    func testManagedFreeLoadingStateRemainsVisibleAndActionable() {
        let presentation = AIDailyBriefPresentation(
            state: .loading(previous: makeBrief(source: .managed)),
            isStale: true
        )

        XCTAssertEqual(presentation.phase, .refreshing)
        XCTAssertNotNil(presentation.brief)
        XCTAssertTrue(presentation.showsProgress)
        XCTAssertFalse(presentation.canRefresh)
        XCTAssertTrue(presentation.showsQuickActions)
    }

    private func makeBrief(source: AIAssistantSource) -> AIDailyBrief {
        AIDailyBrief(
            content: .init(
                summary: "先发布",
                detail: "保护截止任务",
                evidence: ["2 项进行中"]
            ),
            generatedAt: generatedAt,
            source: source,
            contextFingerprint: "fingerprint"
        )
    }
}

private enum TestFailure: LocalizedError {
    case offline

    var errorDescription: String? { "网络不可用" }
}
