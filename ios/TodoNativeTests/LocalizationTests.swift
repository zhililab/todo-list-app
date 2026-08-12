import XCTest
@testable import TodoNative

@MainActor
final class LocalizationTests: XCTestCase {
    private let languageKey = "app_language"
    private let requiredDirectKeys = [
        "ai.brief.title",
        "ai.brief.toolbar",
        "ai.brief.updatedAt",
        "ai.brief.updateAvailable",
        "ai.brief.local",
        "ai.brief.refresh",
        "ai.brief.refreshing",
        "ai.brief.loading",
        "ai.brief.loadingDetail",
        "ai.brief.emptyTitle",
        "ai.brief.emptyDetail",
        "ai.brief.open",
        "ai.brief.openHint",
        "ai.brief.error",
        "ai.brief.manageSubscription",
        "ai.brief.configureProvider",
        "ai.brief.generatePlan",
        "ai.brief.helpPrioritize",
        "ai.brief.breakdown",
        "ai.brief.planPrefill",
        "ai.brief.prioritizePrefill",
        "ai.brief.breakdownPrefill",
        "ai.brief.localPriority",
        "ai.brief.emptySummary",
        "ai.brief.steadyDetail",
        "ai.brief.deadlineDetail",
        "ai.brief.activeEvidence",
        "ai.brief.deadlineEvidence",
        "ai.brief.healthEvidence",
        "ai.workbench.title",
        "ai.workbench.subtitle",
        "ai.workbench.service",
        "ai.workbench.service.custom",
        "ai.workbench.service.managed",
        "ai.workbench.service.local",
        "ai.workbench.result.local",
        "ai.workbench.status.configured",
        "ai.workbench.status.managedQuota",
        "ai.workbench.status.remoteSuccess",
        "ai.workbench.status.localFallback",
        "ai.workbench.status.quotaExceeded",
        "ai.workbench.status.remaining",
        "ai.workbench.mode",
        "ai.workbench.todayPlan",
        "ai.workbench.breakdown",
        "ai.workbench.review",
        "ai.workbench.context",
        "ai.workbench.contextSummary",
        "ai.workbench.contextDetail",
        "ai.workbench.noAutomaticChanges",
        "ai.workbench.todayPlanQuestion",
        "ai.workbench.breakdownQuestion",
        "ai.workbench.reviewQuestion",
        "ai.workbench.todayPlanPlaceholder",
        "ai.workbench.breakdownPlaceholder",
        "ai.workbench.reviewPlaceholder",
        "ai.workbench.todayPlanChip.focus",
        "ai.workbench.todayPlanChip.buffer",
        "ai.workbench.todayPlanChip.deadlines",
        "ai.workbench.breakdownChip.smallSteps",
        "ai.workbench.breakdownChip.risks",
        "ai.workbench.breakdownChip.verify",
        "ai.workbench.reviewChip.progress",
        "ai.workbench.reviewChip.blockers",
        "ai.workbench.reviewChip.next",
        "ai.workbench.goalA11y",
        "ai.workbench.generatePlan",
        "ai.workbench.generateBreakdown",
        "ai.workbench.generateReview",
        "ai.workbench.loading",
        "ai.workbench.loadingDetail",
        "ai.workbench.result",
        "ai.workbench.result.retained",
        "ai.workbench.result.stale",
        "ai.workbench.resultReady",
        "ai.workbench.emptyResult",
        "ai.workbench.error",
        "ai.workbench.retry",
        "ai.workbench.regenerate",
        "ai.workbench.addToToday",
        "ai.workbench.addToTodo",
        "ai.workbench.appliedToToday",
        "ai.workbench.imported",
        "ai.workbench.confirmation.today",
        "ai.workbench.confirmation.tasks",
        "ai.workbench.selected",
        "ai.workbench.notSelected",
        "ai.workbench.minutes",
        "ai.workbench.priority",
        "ai.workbench.dueDate",
        "ai.workbench.existingTaskReason",
        "ai.workbench.localPlanOverview",
        "ai.workbench.defaultGoal",
        "ai.workbench.defineDone",
        "ai.workbench.collectContext",
        "ai.workbench.buildMinimum",
        "ai.workbench.verifyResult",
        "ai.workbench.localReason",
        "ai.workbench.localBreakdownOverview",
        "ai.workbench.localReviewOverview",
        "ai.workbench.progress",
        "ai.workbench.progressBody",
        "ai.workbench.next",
        "ai.workbench.nextBody",
        "ai.workbench.nextPrompt",
        "ai.workbench.nextPromptBody",
        "ai.goalPicker.title",
        "ai.goalPicker.searchPlaceholder",
        "ai.goalPicker.chooseExisting",
        "ai.goalPicker.directInput",
        "ai.goalPicker.selectedTask",
        "ai.goalPicker.change",
        "ai.goalPicker.clear",
        "ai.goalPicker.doing",
        "ai.goalPicker.todo",
        "ai.goalPicker.empty",
        "ai.goalPicker.priority",
        "ai.goalPicker.dueDate",
        "ai.goalPicker.selectionStatus"
    ]

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: languageKey)
        LanguageEnvironment.setDefaultLanguage()
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: languageKey)
        LanguageEnvironment.setDefaultLanguage()
        super.tearDown()
    }

    func testDefaultsToChinese() {
        XCTAssertEqual(Localization.currentLanguage, "zh")
        XCTAssertEqual(Localization.t("tab.today"), "今日计划")
        XCTAssertEqual(Localization.t("taskType.personal"), "个人")
    }

    func testSwitchToEnglish() {
        Localization.setLanguage("en")
        XCTAssertEqual(Localization.currentLanguage, "en")
        XCTAssertEqual(Localization.t("tab.today"), "Today Plan")
        XCTAssertEqual(Localization.t("taskType.personal"), "Personal")
    }

    func testPaywallPromisesOnlyImplementedPremiumBenefits() {
        let expected = [
            "zh": "高级权限：AI 今日计划、分析看板、高级导出，一次订阅全部解锁。",
            "en": "Premium benefits: AI Today Plan, Analytics Dashboard, and Advanced Export."
        ]

        for (language, copy) in expected {
            Localization.setLanguage(language)
            let actual = Localization.t("paywall.perks")
            XCTAssertEqual(actual, copy)
            XCTAssertFalse(actual.localizedCaseInsensitiveContains("template"))
            XCTAssertFalse(actual.localizedCaseInsensitiveContains("theme pack"))
            XCTAssertFalse(actual.contains("模板"))
            XCTAssertFalse(actual.contains("主题包"))
        }
    }

    func testMissingKeyFallsBackToKey() {
        XCTAssertEqual(Localization.t("no.such.key"), "no.such.key")
    }

    func testLanguageEnvironmentPublishes() {
        let env = LanguageEnvironment()
        XCTAssertEqual(env.language, "zh")
        env.setLanguage("en")
        XCTAssertEqual(env.language, "en")
        XCTAssertEqual(Localization.t("tab.settings"), "Settings")
    }

    func testRefinedSettingsAndCompanionCopyExistsInBothLanguages() {
        let keys = [
            "common.ok",
            "notice.systemAllowed",
            "notice.systemDenied",
            "notice.systemNotDetermined",
            "notice.openSettings",
            "notice.permissionExplanation",
            "notice.debugPendingCount",
            "ai.model.custom",
            "ai.managedFixedModel",
            "ai.modelSelectorHint",
            "ai.customModelPlaceholder",
            "ai.customBaseURLHint",
            "ai.keySaveFailed",
            "ai.consent.title",
            "ai.consent.summary",
            "ai.consent.transmittedTitle",
            "ai.consent.transmittedContent",
            "ai.consent.recipientTitle",
            "ai.consent.recipient",
            "ai.consent.managedRecipient",
            "ai.consent.managedRouteDetail",
            "ai.consent.byokRouteDetail",
            "ai.consent.declineDetail",
            "ai.consent.revokeDetail",
            "ai.consent.privacy",
            "ai.consent.decline",
            "ai.consent.continue",
            "settings.privacy",
            "settings.terms",
            "settings.support",
            "settings.supportID",
            "settings.supportIDDetail",
            "settings.copySupportID",
            "settings.supportIDCopied",
            "settings.copySupportIDA11yHint",
            "settings.aiConsentRevoke",
            "settings.aiConsentRevokeTitle",
            "settings.aiConsentRevokeDetail",
            "settings.deleteAIConfiguration",
            "settings.deleteAIConfigurationTitle",
            "settings.deleteAIConfigurationDetail",
            "settings.deleteAIConfigurationConfirm",
            "settings.deleteAIConfigurationErrorTitle",
            "settings.deleteAIConfigurationErrorDetail",
            "voice.errorTitle",
            "voice.switchToVoice",
            "voice.switchToKeyboard",
            "voice.cancelAndSwitchToKeyboard",
            "voice.startRecording",
            "voice.requestingPermission",
            "voice.recording",
            "voice.finalizing",
            "voice.openSettings",
            "voice.speechPermissionDenied",
            "voice.microphonePermissionDenied",
            "voice.recognitionFailed",
            "voice.noSpeechDetected",
            "voice.transcriptReady"
        ]

        for language in ["zh", "en"] {
            Localization.setLanguage(language)
            for key in keys {
                XCTAssertNotEqual(Localization.t(key), key, "Missing \(key) for \(language)")
            }
        }
    }

    func testAssistantFallbackCopyExistsDirectlyInEachLanguage() {
        for language in ["zh", "en"] {
            for key in requiredDirectKeys {
                XCTAssertTrue(
                    Localization.hasTranslation(key, language: language),
                    "Missing direct \(language) translation for \(key)"
                )
            }
        }
    }

    func testAssistantFormatPlaceholdersRenderInChineseAndEnglish() {
        let expectations: [String: [String]] = [
            "zh": [
                "今天 09:30 更新",
                "有 2 项任务将在 24 小时内到期，优先保护交付。",
                "已读取 4 项任务、2 个截止时间与当前健康分 80。",
                "已将 3 项安排到今日计划。",
                "已导入 3 条 AI 建议。",
                "托管额度剩余 7/10 次。",
                "已更新今日计划（3 项）。",
                "已加入待办（3 项）。"
            ],
            "en": [
                "Updated today at 09:30",
                "2 tasks are due within 24 hours; protect those deliveries first.",
                "Using 4 tasks, 2 deadlines, and your current health score of 80.",
                "Added 3 items to Today.",
                "Imported 3 AI suggestions.",
                "7 of 10 managed requests remaining.",
                "Today Plan updated (3 items).",
                "Added 3 items to Tasks."
            ]
        ]

        for language in ["zh", "en"] {
            Localization.setLanguage(language)
            XCTAssertEqual(Localization.t("ai.brief.updatedAt", "09:30"), expectations[language]?[0])
            XCTAssertEqual(Localization.t("ai.brief.deadlineDetail", 2), expectations[language]?[1])
            XCTAssertEqual(Localization.t("ai.workbench.contextSummary", 4, 2, 80), expectations[language]?[2])
            XCTAssertEqual(Localization.t("ai.workbench.appliedToToday", 3), expectations[language]?[3])
            XCTAssertEqual(Localization.t("ai.workbench.imported", 3), expectations[language]?[4])
            XCTAssertEqual(Localization.t("ai.workbench.status.remaining", 7, 10), expectations[language]?[5])
            XCTAssertEqual(Localization.t("ai.workbench.confirmation.today", 3), expectations[language]?[6])
            XCTAssertEqual(Localization.t("ai.workbench.confirmation.tasks", 3), expectations[language]?[7])
        }
    }

    func testQuotaServerErrorFormatsNumericStatusWithoutCrashing() {
        let expectations = [
            "zh": "AI 服务错误（503 upstream）",
            "en": "AI service error (503 upstream)"
        ]

        for language in ["zh", "en"] {
            Localization.setLanguage(language)
            XCTAssertEqual(
                QuotaError.server(status: 503, code: "upstream").errorDescription,
                expectations[language]
            )
        }
    }
}
