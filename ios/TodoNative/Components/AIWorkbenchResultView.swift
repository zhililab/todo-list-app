import SwiftUI
import UIKit

struct AIWorkbenchModePresentation: Equatable {
    let mode: AIWorkbenchMode
    let titleKey: String
    let questionKey: String
    let placeholderKey: String
    let chipKeys: [String]
    let primaryActionKey: String

    init(mode: AIWorkbenchMode) {
        self.mode = mode
        switch mode {
        case .todayPlan:
            titleKey = "ai.workbench.todayPlan"
            questionKey = "ai.workbench.todayPlanQuestion"
            placeholderKey = "ai.workbench.todayPlanPlaceholder"
            chipKeys = [
                "ai.workbench.todayPlanChip.focus",
                "ai.workbench.todayPlanChip.buffer",
                "ai.workbench.todayPlanChip.deadlines"
            ]
            primaryActionKey = "ai.workbench.generatePlan"
        case .breakdown:
            titleKey = "ai.workbench.breakdown"
            questionKey = "ai.workbench.breakdownQuestion"
            placeholderKey = "ai.workbench.breakdownPlaceholder"
            chipKeys = [
                "ai.workbench.breakdownChip.smallSteps",
                "ai.workbench.breakdownChip.risks",
                "ai.workbench.breakdownChip.verify"
            ]
            primaryActionKey = "ai.workbench.generateBreakdown"
        case .review:
            titleKey = "ai.workbench.review"
            questionKey = "ai.workbench.reviewQuestion"
            placeholderKey = "ai.workbench.reviewPlaceholder"
            chipKeys = [
                "ai.workbench.reviewChip.progress",
                "ai.workbench.reviewChip.blockers",
                "ai.workbench.reviewChip.next"
            ]
            primaryActionKey = "ai.workbench.generateReview"
        }
    }

    func canGenerate(
        goal: String,
        selectedGoalFingerprint: String? = nil
    ) -> Bool {
        guard mode == .breakdown else { return true }
        if !goal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return true
        }
        return !(selectedGoalFingerprint ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty
    }
}

enum AIWorkbenchServiceKind: Equatable {
    case custom
    case managed
    case local
}

enum AIWorkbenchServiceStatus: Equatable {
    case configured
    case managedQuota
    case remoteSuccess
    case localFallback
    case quotaExceeded
    case localOnly
}

enum AIWorkbenchServiceTone: Equatable {
    case neutral
    case success
    case warning
    case critical
}

struct AIWorkbenchTaskRowLayoutPresentation: Equatable {
    enum Axis: Equatable {
        case horizontal
        case vertical
    }

    let axis: Axis

    init(isAccessibilitySize: Bool) {
        axis = isAccessibilitySize ? .vertical : .horizontal
    }
}

struct AIWorkbenchTaskRowAppearancePresentation: Equatable {
    enum Background: Equatable {
        case selectedSoft
        case card

        var semanticUIColor: UIColor {
            switch self {
            case .selectedSoft:
                return AppTheme.Palette.blueSoft
            case .card:
                return AppTheme.Palette.appCardBg
            }
        }

        var color: Color {
            switch self {
            case .selectedSoft:
                return Color(uiColor: semanticUIColor).opacity(0.72)
            case .card:
                return Color(uiColor: semanticUIColor)
            }
        }
    }

    let background: Background

    init(isSelected: Bool) {
        background = isSelected ? .selectedSoft : .card
    }
}

struct AIWorkbenchServicePresentation: Equatable {
    let kind: AIWorkbenchServiceKind
    let status: AIWorkbenchServiceStatus
    let statusKey: String
    let tone: AIWorkbenchServiceTone
    let detail: String?
    let quotaRemaining: Int?
    let quotaLimit: Int?

    init(
        apiKey: String,
        managedBaseURL: String?,
        providerName: String,
        model: String,
        latestResultSource: AIAssistantSource?,
        quotaSnapshot: QuotaSnapshot? = nil,
        failure: AIAssistantFailure? = nil
    ) {
        let hasAPIKey = !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasManagedQuota = !(managedBaseURL ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty

        if hasAPIKey {
            kind = .custom
            detail = [providerName, model]
                .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                .joined(separator: " · ")
        } else if hasManagedQuota {
            kind = .managed
            detail = "DeepSeek · \(OpenAIService.managedModelID)"
        } else {
            kind = .local
            detail = nil
        }

        if case .quotaExceeded = failure?.kind {
            status = .quotaExceeded
            statusKey = "ai.workbench.status.quotaExceeded"
            tone = .critical
            quotaRemaining = 0
            quotaLimit = nil
        } else if failure != nil {
            tone = .neutral
            if kind == .managed, let quotaSnapshot {
                status = .managedQuota
                statusKey = "ai.workbench.status.managedQuota"
                if quotaSnapshot.isPro {
                    quotaRemaining = max(0, quotaSnapshot.proLimit - quotaSnapshot.proUsed)
                    quotaLimit = quotaSnapshot.proLimit
                } else {
                    quotaRemaining = max(0, quotaSnapshot.freeLimit - quotaSnapshot.freeUsed)
                    quotaLimit = quotaSnapshot.freeLimit
                }
            } else if kind == .local {
                status = .localOnly
                statusKey = "ai.workbench.service.local"
                quotaRemaining = nil
                quotaLimit = nil
            } else {
                status = .configured
                statusKey = kind == .managed
                    ? "ai.workbench.service.managed"
                    : "ai.workbench.status.configured"
                quotaRemaining = nil
                quotaLimit = nil
            }
        } else if latestResultSource == .custom || latestResultSource == .managed {
            status = .remoteSuccess
            statusKey = "ai.workbench.status.remoteSuccess"
            tone = .success
            quotaRemaining = nil
            quotaLimit = nil
        } else if latestResultSource == .local {
            status = .localFallback
            statusKey = "ai.workbench.status.localFallback"
            tone = .warning
            quotaRemaining = nil
            quotaLimit = nil
        } else if kind == .managed, let quotaSnapshot {
            status = .managedQuota
            statusKey = "ai.workbench.status.managedQuota"
            tone = .neutral
            if quotaSnapshot.isPro {
                quotaRemaining = max(0, quotaSnapshot.proLimit - quotaSnapshot.proUsed)
                quotaLimit = quotaSnapshot.proLimit
            } else {
                quotaRemaining = max(0, quotaSnapshot.freeLimit - quotaSnapshot.freeUsed)
                quotaLimit = quotaSnapshot.freeLimit
            }
        } else if kind == .local {
            status = .localOnly
            statusKey = "ai.workbench.service.local"
            tone = .neutral
            quotaRemaining = nil
            quotaLimit = nil
        } else {
            status = .configured
            statusKey = kind == .managed
                ? "ai.workbench.service.managed"
                : "ai.workbench.status.configured"
            tone = .neutral
            quotaRemaining = nil
            quotaLimit = nil
        }
    }
}

struct AIWorkbenchConfirmationPresentation: Equatable {
    let messageKey: String?
    let count: Int

    var isVisible: Bool {
        messageKey != nil
    }

    init(mode: AIWorkbenchMode, appliedCount: Int) {
        count = max(0, appliedCount)
        guard count > 0 else {
            messageKey = nil
            return
        }

        switch mode {
        case .todayPlan:
            messageKey = "ai.workbench.confirmation.today"
        case .breakdown:
            messageKey = "ai.workbench.confirmation.tasks"
        case .review:
            messageKey = nil
        }
    }
}

struct AIWorkbenchSessionPresentation: Equatable {
    enum Phase: Equatable {
        case idle
        case loading
        case result
        case failed
    }

    let phase: Phase
    let session: AIWorkbenchSession?
    let failure: AIAssistantFailure?
    let isFresh: Bool
    let showsRetainedResult: Bool
    let showsStaleResult: Bool

    var currentResultSource: AIAssistantSource? {
        phase == .result ? session?.result.source : nil
    }

    init(
        state: AIWorkbenchState,
        currentMode: AIWorkbenchMode,
        currentGoal: String,
        currentContextFingerprint: String,
        currentSelectedGoalFingerprint: String? = nil
    ) {
        switch state {
        case .idle:
            phase = .idle
            session = nil
            failure = nil
        case .loading(let previous):
            phase = .loading
            session = previous
            failure = nil
        case .result(let resultSession):
            phase = .result
            session = resultSession
            failure = nil
        case .failed(let previous, let assistantFailure):
            phase = .failed
            session = previous
            failure = assistantFailure
        }

        let currentProvenance = AIWorkbenchProvenance(
            mode: currentMode,
            goal: currentGoal,
            contextFingerprint: currentContextFingerprint,
            selectedGoalFingerprint: currentSelectedGoalFingerprint
        )
        isFresh = session?.provenance == currentProvenance
        showsRetainedResult = session != nil && (phase == .loading || phase == .failed)
        showsStaleResult = session != nil && !isFresh
    }
}

struct AIWorkbenchContextPresentation: Equatable {
    let taskCount: Int
    let deadlineCount: Int
    let todoCount: Int
    let doingCount: Int
    let doneCount: Int
    let health: Int

    init(context: AIAssistantContext) {
        let visible = context.tasks.filter { !$0.isArchived }
        taskCount = visible.count
        deadlineCount = visible.filter { $0.dueDate != nil }.count
        todoCount = visible.filter { $0.status == TodoStatus.todo.rawValue }.count
        doingCount = visible.filter { $0.status == TodoStatus.doing.rawValue }.count
        doneCount = visible.filter { $0.status == TodoStatus.done.rawValue }.count
        health = context.health
    }
}

struct AIWorkbenchResultPresentation: Equatable {
    let importKey: String?
    let importCount: Int
    let showsImport: Bool
    let canImport: Bool
    let importAnnouncementKey: String?

    init(
        mode: AIWorkbenchMode,
        importableCount: Int,
        hasSuggestedTasks: Bool,
        isSessionImportable: Bool = true
    ) {
        importCount = max(0, importableCount)
        switch mode {
        case .todayPlan:
            importKey = "ai.workbench.addToToday"
        case .breakdown:
            importKey = "ai.workbench.addToTodo"
        case .review:
            importKey = nil
        }
        showsImport = importKey != nil && hasSuggestedTasks
        canImport = showsImport && importCount > 0 && isSessionImportable
        switch mode {
        case .todayPlan where canImport:
            importAnnouncementKey = "ai.workbench.appliedToToday"
        case .breakdown where canImport:
            importAnnouncementKey = "ai.workbench.imported"
        default:
            importAnnouncementKey = nil
        }
    }
}

struct AIWorkbenchResultView: View {
    let presentation: AIWorkbenchSessionPresentation
    let mode: AIWorkbenchMode
    let selectedTaskIDs: Set<UUID>
    let onToggle: (UUID) -> Void
    let onRetry: () -> Void
    let onRecovery: (AIAssistantRecovery) -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            switch presentation.phase {
            case .idle:
                EmptyView()
            case .loading:
                VStack(spacing: AppTheme.Spacing.sm) {
                    loadingView
                    retainedResultView
                }
            case .result:
                retainedResultView
            case .failed:
                VStack(spacing: AppTheme.Spacing.sm) {
                    if let failure = presentation.failure {
                        failureView(failure)
                    }
                    retainedResultView
                }
            }
        }
        .transition(
            reduceMotion
                ? .opacity
                : .opacity.combined(with: .offset(y: AppTheme.Spacing.xs))
        )
    }

    @ViewBuilder
    private var retainedResultView: some View {
        if let session = presentation.session {
            resultView(session.result)
        }
    }

    private var loadingView: some View {
        HStack(alignment: .top, spacing: AppTheme.Spacing.sm) {
            ProgressView()
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                Text(Localization.t("ai.workbench.loading"))
                    .font(AppTheme.Typography.body.weight(.semibold))
                    .foregroundStyle(Color.appText)
                Text(Localization.t("ai.workbench.loadingDetail"))
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(Color.appMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 88, alignment: .leading)
        .appCard()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Localization.t("ai.workbench.loading"))
        .accessibilityValue(Localization.t("ai.workbench.loadingDetail"))
    }

    @ViewBuilder
    private func resultView(_ result: AIWorkbenchResult) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            HStack(spacing: AppTheme.Spacing.xs) {
                Text(Localization.t("ai.workbench.result"))
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(Color.accentBlue)
                if let statusKey = resultStatusKey {
                    Text(Localization.t(statusKey))
                        .font(AppTheme.Typography.caption2)
                        .foregroundStyle(Color.appMuted)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.appBg, in: Capsule())
                }
            }

            Text(result.overview)
                .font(AppTheme.Typography.headline)
                .foregroundStyle(Color.appText)
                .fixedSize(horizontal: false, vertical: true)

            if mode == .review {
                reviewSections(result.sections)
            } else if result.suggestedTasks.isEmpty {
                Text(Localization.t("ai.workbench.emptyResult"))
                    .font(AppTheme.Typography.body)
                    .foregroundStyle(Color.appMuted)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(spacing: 0) {
                    ForEach(result.suggestedTasks) { task in
                        taskRow(task)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.Spacing.radiusMd))
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.Spacing.radiusMd)
                        .stroke(Color.appLine, lineWidth: 1)
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .appCard()
        .accessibilityElement(children: .contain)
    }

    private var resultStatusKey: String? {
        if presentation.showsStaleResult {
            return "ai.workbench.result.stale"
        }
        if presentation.showsRetainedResult {
            return "ai.workbench.result.retained"
        }
        return nil
    }

    @ViewBuilder
    private func reviewSections(_ sections: [AIResultSection]) -> some View {
        if sections.isEmpty {
            Text(Localization.t("ai.workbench.emptyResult"))
                .font(AppTheme.Typography.body)
                .foregroundStyle(Color.appMuted)
        } else {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                ForEach(sections) { section in
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                        Text(section.title)
                            .font(AppTheme.Typography.body.weight(.semibold))
                            .foregroundStyle(Color.appText)
                        Text(section.body)
                            .font(AppTheme.Typography.body)
                            .foregroundStyle(Color.appMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(AppTheme.Spacing.sm)
                    .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
                    .background(Color.appBg, in: RoundedRectangle(cornerRadius: AppTheme.Spacing.radiusSm))
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    private func taskRow(_ task: AISuggestedTask) -> some View {
        let isSelected = selectedTaskIDs.contains(task.id)
        let layout = AIWorkbenchTaskRowLayoutPresentation(
            isAccessibilitySize: dynamicTypeSize.isAccessibilitySize
        )
        let appearance = AIWorkbenchTaskRowAppearancePresentation(isSelected: isSelected)
        return Button {
            onToggle(task.id)
        } label: {
            Group {
                if layout.axis == .vertical {
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                        selectionIcon(isSelected: isSelected)
                        taskDetails(task)
                    }
                } else {
                    HStack(alignment: .top, spacing: AppTheme.Spacing.sm) {
                        selectionIcon(isSelected: isSelected)
                        taskDetails(task)
                    }
                }
            }
            .padding(AppTheme.Spacing.sm)
            .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
            .background(appearance.background.color)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!presentation.isFresh || presentation.phase == .loading)
        .accessibilityLabel(task.title)
        .accessibilityValue(accessibilityValue(for: task, isSelected: isSelected))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func selectionIcon(isSelected: Bool) -> some View {
        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
            .font(.title3)
            .foregroundStyle(isSelected ? Color.accentBlue : Color.appMuted)
            .frame(width: 28, height: 28)
    }

    private func taskDetails(_ task: AISuggestedTask) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
            Text(task.title)
                .font(AppTheme.Typography.body.weight(.semibold))
                .foregroundStyle(Color.appText)
                .fixedSize(horizontal: false, vertical: true)
            metadata(for: task)
            Text(task.rationale)
                .font(AppTheme.Typography.caption)
                .foregroundStyle(Color.appMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func metadata(for task: AISuggestedTask) -> some View {
        let labels = metadataLabels(for: task)
        if !labels.isEmpty {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(labels, id: \.self) { label in
                        metadataLabel(label)
                    }
                }
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: AppTheme.Spacing.sm) {
                        ForEach(labels, id: \.self) { label in
                            metadataLabel(label)
                        }
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(labels, id: \.self) { label in
                            metadataLabel(label)
                        }
                    }
                }
            }
        }
    }

    private func metadataLabel(_ text: String) -> some View {
        Text(text)
            .font(AppTheme.Typography.caption2)
            .foregroundStyle(Color.ghostText)
    }

    private func metadataLabels(for task: AISuggestedTask) -> [String] {
        var labels: [String] = []
        if let minutes = task.estimatedMinutes {
            labels.append(Localization.t("ai.workbench.minutes", minutes))
        }
        if let priority = task.priority {
            labels.append(Localization.t("ai.workbench.priority", priority))
        }
        if let dueDate = task.dueDate {
            labels.append(
                Localization.t(
                    "ai.workbench.dueDate",
                    dueDate.formatted(date: .abbreviated, time: .shortened)
                )
            )
        }
        return labels
    }

    private func accessibilityValue(for task: AISuggestedTask, isSelected: Bool) -> String {
        let selection = Localization.t(
            isSelected ? "ai.workbench.selected" : "ai.workbench.notSelected"
        )
        return ([selection] + metadataLabels(for: task) + [task.rationale])
            .joined(separator: "，")
    }

    private func failureView(_ failure: AIAssistantFailure) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            Label(Localization.t("ai.workbench.error"), systemImage: failureIcon(failure))
                .font(AppTheme.Typography.headline)
                .foregroundStyle(Color.red)
            Text(failure.message)
                .font(AppTheme.Typography.body)
                .foregroundStyle(Color.appText)
                .fixedSize(horizontal: false, vertical: true)

            recoveryActions(for: failure)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .appCard()
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Localization.t("ai.workbench.error"))
        .accessibilityValue(failure.message)
    }

    @ViewBuilder
    private func recoveryActions(for failure: AIAssistantFailure) -> some View {
        let actions = VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
            retryButton
            ForEach(failure.recovery, id: \.rawValue) { recovery in
                recoveryButton(recovery)
            }
        }

        if dynamicTypeSize.isAccessibilitySize || !failure.recovery.isEmpty {
            actions
        } else {
            retryButton
        }
    }

    private var retryButton: some View {
        Button(Localization.t("ai.workbench.retry"), action: onRetry)
            .ghostButton()
            .frame(minHeight: 44)
            .accessibilityLabel(Localization.t("ai.workbench.retry"))
    }

    private func recoveryButton(_ recovery: AIAssistantRecovery) -> some View {
        Button {
            onRecovery(recovery)
        } label: {
            Text(recoveryTitle(recovery))
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(Color.accentBlue)
        .accessibilityLabel(recoveryTitle(recovery))
    }

    private func recoveryTitle(_ recovery: AIAssistantRecovery) -> String {
        switch recovery {
        case .manageSubscription:
            return Localization.t("ai.brief.manageSubscription")
        case .configureProvider:
            return Localization.t("ai.brief.configureProvider")
        }
    }

    private func failureIcon(_ failure: AIAssistantFailure) -> String {
        switch failure.kind {
        case .quotaExceeded:
            return "gauge.with.dots.needle.0percent"
        case .other:
            return "exclamationmark.triangle"
        }
    }
}
