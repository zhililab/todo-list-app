import XCTest
@testable import TodoNative

@MainActor
final class AIAssistantServiceTests: XCTestCase {
    private enum TestError: Error {
        case offline
    }

    private final class StubTransport: AIAssistantTransporting {
        var result: Result<String?, Error>
        private(set) var calls: [(prompt: String, instruction: String)] = []
        private let routedSource: AIAssistantSource

        init(source: AIAssistantSource, result: Result<String?, Error>) {
            routedSource = source
            self.result = result
        }

        func call(
            promptText: String,
            instructionText: String
        ) async throws -> (text: String?, source: AIAssistantSource) {
            calls.append((promptText, instructionText))
            await Task.yield()
            return (try result.get(), routedSource)
        }
    }

    private let context = AIAssistantContext(
        tasks: [
            AIAssistantTaskSnapshot(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
                title: "发布版本",
                status: "todo",
                priority: 5,
                estimatedMinutes: 45,
                dueDate: Date(timeIntervalSince1970: 1_786_233_600),
                isArchived: false
            )
        ],
        health: 58
    )

    private let validBriefJSON = #"{"summary":"先发布","detail":"保护截止任务","evidence":["1 个临近截止"]}"#

    private var validTasksJSON: String {
        #"{"overview":"按顺序推进","suggestedTasks":[{"id":"00000000-0000-0000-0000-000000000011","title":"定义完成标准","rationale":"先对齐范围","estimatedMinutes":20,"priority":5,"dueDate":"2026-08-10T08:30:00Z"},{"id":"00000000-0000-0000-0000-000000000012","title":"实现最小版本","rationale":"尽快获得反馈","estimatedMinutes":45,"priority":4,"dueDate":null},{"id":"00000000-0000-0000-0000-000000000013","title":"验证结果","rationale":"关闭交付风险","estimatedMinutes":15,"priority":3,"dueDate":null}],"sections":[]}"#
    }

    private let validReviewJSON = #"{"overview":"本周推进稳定","suggestedTasks":[],"sections":[{"id":"progress","title":"进展","body":"完成核心实现"},{"id":"next","title":"下一步","body":"完成验证"},{"id":"prompt","title":"推荐提示","body":"请检查发布风险"}]}"#

    func testDailyBriefDecoderAcceptsControlledJSON() throws {
        let brief = try AIAssistantDecoder.dailyBrief(from: validBriefJSON)

        XCTAssertEqual(brief.summary, "先发布")
        XCTAssertEqual(brief.evidence, ["1 个临近截止"])
    }

    func testDailyBriefDecoderRejectsEmptyEvidence() {
        let json = #"{"summary":"先发布","detail":"保护截止任务","evidence":[]}"#

        XCTAssertThrowsError(try AIAssistantDecoder.dailyBrief(from: json))
    }

    func testWorkbenchDecoderAcceptsBreakdownWithISO8601Date() throws {
        let result = try AIAssistantDecoder.workbench(
            from: validTasksJSON,
            mode: .breakdown,
            source: .custom
        )

        XCTAssertEqual(result.source, .custom)
        XCTAssertEqual(result.suggestedTasks.count, 3)
        XCTAssertEqual(
            result.suggestedTasks.first?.dueDate,
            ISO8601DateFormatter().date(from: "2026-08-10T08:30:00Z")
        )
    }

    func testWorkbenchDecoderRejectsInvalidTaskShapes() {
        let invalidPayloads = [
            // Fewer than three tasks.
            #"{"overview":"x","suggestedTasks":[],"sections":[]}"#,
            // Duplicate UUID and invalid title, rationale, minutes, and priority.
            #"{"overview":"x","suggestedTasks":[{"id":"00000000-0000-0000-0000-000000000011","title":" ","rationale":"why","estimatedMinutes":20,"priority":5,"dueDate":null},{"id":"00000000-0000-0000-0000-000000000011","title":"b","rationale":" ","estimatedMinutes":0,"priority":0,"dueDate":null},{"id":"00000000-0000-0000-0000-000000000013","title":"c","rationale":"why","estimatedMinutes":20,"priority":6,"dueDate":null}],"sections":[]}"#,
            // Plan modes must not smuggle review sections into the result.
            #"{"overview":"x","suggestedTasks":[{"id":"00000000-0000-0000-0000-000000000011","title":"a","rationale":"why","estimatedMinutes":20,"priority":5,"dueDate":null},{"id":"00000000-0000-0000-0000-000000000012","title":"b","rationale":"why","estimatedMinutes":20,"priority":4,"dueDate":null},{"id":"00000000-0000-0000-0000-000000000013","title":"c","rationale":"why","estimatedMinutes":20,"priority":3,"dueDate":null}],"sections":[{"id":"progress","title":"p","body":"b"}]}"#
        ]

        for json in invalidPayloads {
            XCTAssertThrowsError(
                try AIAssistantDecoder.workbench(from: json, mode: .todayPlan, source: .managed)
            )
        }
    }

    func testWorkbenchDecoderAcceptsReviewShape() throws {
        let result = try AIAssistantDecoder.workbench(
            from: validReviewJSON,
            mode: .review,
            source: .managed
        )

        XCTAssertTrue(result.suggestedTasks.isEmpty)
        XCTAssertEqual(result.sections.map(\.id), ["progress", "next", "prompt"])
    }

    func testWorkbenchDecoderRejectsReviewTasksOrMissingSections() {
        XCTAssertThrowsError(
            try AIAssistantDecoder.workbench(from: validTasksJSON, mode: .review, source: .managed)
        )

        let missingPrompt = #"{"overview":"x","suggestedTasks":[],"sections":[{"id":"progress","title":"p","body":"b"},{"id":"next","title":"n","body":"b"}]}"#
        XCTAssertThrowsError(
            try AIAssistantDecoder.workbench(from: missingPrompt, mode: .review, source: .managed)
        )
    }

    func testSuccessfulResponseUsesSourceReturnedBySameTransportCall() async throws {
        let quotaKey = QuotaClient.baseURLKey
        let apiKey = OpenAIService.keyStorageKey
        let oldQuota = UserDefaults.standard.object(forKey: quotaKey)
        let oldAPIKey = UserDefaults.standard.object(forKey: apiKey)
        defer {
            restore(oldQuota, forKey: quotaKey)
            restore(oldAPIKey, forKey: apiKey)
        }
        UserDefaults.standard.set("https://quota.test", forKey: quotaKey)
        UserDefaults.standard.set("", forKey: apiKey)
        let transport = StubTransport(source: .custom, result: .success(validBriefJSON))
        let service = LiveAIAssistantService(transport: transport)

        let (brief, source) = try await service.dailyBrief(context: context, now: Date())

        XCTAssertEqual(brief.summary, "先发布")
        XCTAssertEqual(source, .custom)
        XCTAssertEqual(transport.calls.count, 1)
    }

    func testMalformedOrInvalidRemoteShapeFallsBackToLocal() async throws {
        for response in ["not json", #"{"summary":"x","detail":"y","evidence":[]}"#] {
            let transport = StubTransport(source: .managed, result: .success(response))
            let service = LiveAIAssistantService(transport: transport)

            let (_, source) = try await service.dailyBrief(context: context, now: Date())

            XCTAssertEqual(source, .local)
        }
    }

    func testNetworkServerAndMissingBaseURLErrorsFallBackToLocal() async throws {
        let errors: [Error] = [
            TestError.offline,
            QuotaError.server(status: 503, code: "upstream_failure"),
            QuotaError.missingBaseURL
        ]

        for error in errors {
            let transport = StubTransport(source: .managed, result: .failure(error))
            let service = LiveAIAssistantService(transport: transport)

            let result = try await service.workbench(
                mode: .breakdown,
                goal: "发布版本",
                context: context,
                now: Date()
            )

            XCTAssertEqual(result.source, .local)
            XCTAssertGreaterThanOrEqual(result.suggestedTasks.count, 3)
        }
    }

    func testQuotaExceededIsTheOnlyQuotaErrorPassedThrough() async {
        let transport = StubTransport(
            source: .managed,
            result: .failure(QuotaError.quotaExceeded(kind: "daily"))
        )
        let service = LiveAIAssistantService(transport: transport)

        do {
            _ = try await service.dailyBrief(context: context, now: Date())
            XCTFail("Expected quotaExceeded")
        } catch QuotaError.quotaExceeded(let kind) {
            XCTAssertEqual(kind, "daily")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testInvalidRemoteWorkbenchShapeFallsBackToModeSpecificLocalResult() async throws {
        let transport = StubTransport(
            source: .managed,
            result: .success(#"{"overview":"x","suggestedTasks":[],"sections":[]}"#)
        )
        let service = LiveAIAssistantService(transport: transport)

        let result = try await service.workbench(
            mode: .review,
            goal: "",
            context: context,
            now: Date()
        )

        XCTAssertEqual(result.source, .local)
        XCTAssertTrue(result.suggestedTasks.isEmpty)
        XCTAssertEqual(result.sections.map(\.id), ["progress", "next", "prompt"])
    }

    func testLocalPlannerProducesSelectableBreakdownAndReviewSections() {
        let breakdown = LocalAIAssistantPlanner.workbench(
            mode: .breakdown,
            goal: "发布版本",
            context: context,
            now: Date()
        )
        XCTAssertGreaterThanOrEqual(breakdown.suggestedTasks.count, 3)
        XCTAssertEqual(Set(breakdown.suggestedTasks.map(\.id)).count, breakdown.suggestedTasks.count)
        XCTAssertTrue(breakdown.sections.isEmpty)

        let review = LocalAIAssistantPlanner.workbench(
            mode: .review,
            goal: "",
            context: context,
            now: Date()
        )
        XCTAssertTrue(review.suggestedTasks.isEmpty)
        XCTAssertEqual(review.sections.map(\.id), ["progress", "next", "prompt"])
    }

    func testLocalTodayPlanRecommendationsKeepExistingTaskIDs() {
        let result = LocalAIAssistantPlanner.workbench(
            mode: .todayPlan,
            goal: "",
            context: context,
            now: Date()
        )

        XCTAssertEqual(result.suggestedTasks.map(\.id), context.tasks.map(\.id))
        XCTAssertEqual(result.suggestedTasks.map(\.title), context.tasks.map(\.title))
    }

    func testLocalPlannerNeverLeaksLocalizationKeysInChineseOrEnglish() {
        let oldLanguage = UserDefaults.standard.object(forKey: Localization.languageKey)
        defer { restore(oldLanguage, forKey: Localization.languageKey) }

        for language in ["zh", "en"] {
            Localization.setLanguage(language)
            let now = Date(timeIntervalSince1970: 1_786_200_000)
            let emptyContext = AIAssistantContext(tasks: [], health: 50)
            let brief = LocalAIAssistantPlanner.dailyBrief(context: context, now: now)
            let emptyBrief = LocalAIAssistantPlanner.dailyBrief(context: emptyContext, now: now)
            let todayPlan = LocalAIAssistantPlanner.workbench(
                mode: .todayPlan,
                goal: "",
                context: context,
                now: now
            )
            let breakdown = LocalAIAssistantPlanner.workbench(
                mode: .breakdown,
                goal: "",
                context: context,
                now: now
            )
            let review = LocalAIAssistantPlanner.workbench(
                mode: .review,
                goal: "",
                context: context,
                now: now
            )
            let renderedStrings = [
                brief.summary,
                brief.detail,
                emptyBrief.summary,
                emptyBrief.detail,
                todayPlan.overview,
                breakdown.overview,
                review.overview
            ]
                + brief.evidence
                + emptyBrief.evidence
                + todayPlan.suggestedTasks.flatMap { [$0.title, $0.rationale] }
                + breakdown.suggestedTasks.flatMap { [$0.title, $0.rationale] }
                + review.sections.flatMap { [$0.title, $0.body] }

            for rendered in renderedStrings {
                XCTAssertFalse(
                    rendered.contains("ai.brief.") || rendered.contains("ai.workbench."),
                    "Leaked localization key for \(language): \(rendered)"
                )
            }
        }
    }

    private func restore(_ value: Any?, forKey key: String) {
        if let value {
            UserDefaults.standard.set(value, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }
}
