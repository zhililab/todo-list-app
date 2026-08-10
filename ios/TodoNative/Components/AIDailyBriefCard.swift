import SwiftUI
import UIKit

enum AIDailyBriefPhase: Equatable {
    case idle
    case initialLoading
    case refreshing
    case content
    case failure
}

enum AIDailyBriefBadge: Equatable {
    case localSuggestion
    case updateAvailable
}

enum AIDailyBriefAnnouncement: Equatable {
    case loading
    case refreshing
    case failure(String)

    var spokenText: String {
        switch self {
        case .loading:
            return Localization.t("ai.brief.loading")
        case .refreshing:
            return Localization.t("ai.brief.refreshing")
        case .failure(let message):
            return message
        }
    }
}

enum AIDailyBriefQuickAction: CaseIterable, Equatable, Identifiable {
    case generatePlan
    case prioritize
    case breakdown

    var id: Self { self }

    private var metadata: (mode: AIWorkbenchMode, titleKey: String, prefillKey: String, systemImage: String) {
        switch self {
        case .generatePlan:
            return (
                mode: .todayPlan,
                titleKey: "ai.brief.generatePlan",
                prefillKey: "ai.brief.planPrefill",
                systemImage: "calendar.badge.plus"
            )
        case .prioritize:
            return (
                mode: .review,
                titleKey: "ai.brief.helpPrioritize",
                prefillKey: "ai.brief.prioritizePrefill",
                systemImage: "arrow.triangle.branch"
            )
        case .breakdown:
            return (
                mode: .breakdown,
                titleKey: "ai.brief.breakdown",
                prefillKey: "ai.brief.breakdownPrefill",
                systemImage: "square.split.2x2"
            )
        }
    }

    var mode: AIWorkbenchMode { metadata.mode }

    var titleKey: String { metadata.titleKey }

    var prefillKey: String { metadata.prefillKey }

    var systemImage: String { metadata.systemImage }
}

struct AIDailyBriefPresentation: Equatable {
    let brief: AIDailyBrief?
    let phase: AIDailyBriefPhase
    let badges: [AIDailyBriefBadge]
    let showsProgress: Bool
    let failure: AIAssistantFailure?
    let announcement: AIDailyBriefAnnouncement?
    let recovery: [AIAssistantRecovery]
    let canRefresh: Bool
    let showsQuickActions: Bool

    var generatedAt: Date? { brief?.generatedAt }

    init(
        state: AIBriefState,
        isStale: Bool
    ) {
        let resolvedBrief: AIDailyBrief?
        let resolvedPhase: AIDailyBriefPhase
        let resolvedProgress: Bool
        let resolvedFailure: AIAssistantFailure?
        let resolvedAnnouncement: AIDailyBriefAnnouncement?
        let failedWithPreviousBrief: Bool

        switch state {
        case .idle:
            resolvedBrief = nil
            resolvedPhase = .idle
            resolvedProgress = false
            resolvedFailure = nil
            resolvedAnnouncement = nil
            failedWithPreviousBrief = false
        case .loading(let previous):
            resolvedBrief = previous
            resolvedPhase = previous == nil ? .initialLoading : .refreshing
            resolvedProgress = true
            resolvedFailure = nil
            resolvedAnnouncement = previous == nil ? .loading : .refreshing
            failedWithPreviousBrief = false
        case .loaded(let value):
            resolvedBrief = value
            resolvedPhase = .content
            resolvedProgress = false
            resolvedFailure = nil
            resolvedAnnouncement = nil
            failedWithPreviousBrief = false
        case .failed(let previous, let failure):
            resolvedBrief = previous
            resolvedPhase = .failure
            resolvedProgress = false
            resolvedFailure = failure
            resolvedAnnouncement = .failure(failure.message)
            failedWithPreviousBrief = previous != nil
        }

        brief = resolvedBrief
        phase = resolvedPhase
        badges = Self.badges(
            for: resolvedBrief,
            showsUpdateAvailable: isStale || failedWithPreviousBrief
        )
        showsProgress = resolvedProgress
        failure = resolvedFailure
        announcement = resolvedAnnouncement
        recovery = resolvedFailure?.recovery ?? []
        canRefresh = !resolvedProgress
        showsQuickActions = resolvedBrief != nil
    }

    private static func badges(
        for brief: AIDailyBrief?,
        showsUpdateAvailable: Bool
    ) -> [AIDailyBriefBadge] {
        guard let brief else { return [] }
        var values: [AIDailyBriefBadge] = []
        if brief.source == .local {
            values.append(.localSuggestion)
        }
        if showsUpdateAvailable {
            values.append(.updateAvailable)
        }
        return values
    }
}

struct AIDailyBriefCard: View {
    let presentation: AIDailyBriefPresentation
    let onOpen: () -> Void
    let onRefresh: () -> Void
    let onQuickAction: (AIDailyBriefQuickAction) -> Void
    let onRecovery: (AIAssistantRecovery) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var hasAppeared = false

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            header
            mainContent

            if let failure = presentation.failure {
                failureContent(failure)
            }

            if presentation.showsQuickActions {
                quickActions
            }
        }
        .frame(maxWidth: .infinity, minHeight: 272, alignment: .topLeading)
        .appCard()
        .opacity(hasAppeared ? 1 : 0)
        .offset(y: reduceMotion || hasAppeared ? 0 : 8)
        .animation(
            AppTheme.Motion.resolvedFade(AppTheme.Motion.content, reduceMotion: reduceMotion),
            value: presentation.generatedAt
        )
        .onChange(of: presentation.announcement) {
            guard
                UIAccessibility.isVoiceOverRunning,
                let announcement = presentation.announcement
            else { return }
            UIAccessibility.post(
                notification: .announcement,
                argument: announcement.spokenText
            )
        }
        .onAppear {
            guard !hasAppeared else { return }
            withAnimation(AppTheme.Motion.resolvedFade(AppTheme.Motion.content, reduceMotion: reduceMotion)) {
                hasAppeared = true
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var header: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: AppTheme.Spacing.xs) {
                titleLabel
                badgeRow
                Spacer(minLength: AppTheme.Spacing.xs)
                refreshButton
            }

            VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                HStack(alignment: .center, spacing: AppTheme.Spacing.xs) {
                    titleLabel
                    Spacer(minLength: AppTheme.Spacing.xs)
                    refreshButton
                }
                badgeRow
            }
        }
    }

    private var titleLabel: some View {
        Label(Localization.t("ai.brief.title"), systemImage: "sparkles")
            .font(AppTheme.Typography.headline)
            .foregroundStyle(Color.appText)
    }

    @ViewBuilder
    private var badgeRow: some View {
        if !presentation.badges.isEmpty {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: AppTheme.Spacing.xs) {
                    ForEach(presentation.badges, id: \.self) { badge in
                        badgeLabel(badge)
                    }
                }
                VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                    ForEach(presentation.badges, id: \.self) { badge in
                        badgeLabel(badge)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var refreshButton: some View {
        if presentation.canRefresh {
            Button(action: onRefresh) {
                Image(systemName: "arrow.clockwise")
                    .font(.body.weight(.semibold))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.accentBlue)
            .accessibilityLabel(Localization.t("ai.brief.refresh"))
        } else if presentation.showsProgress, presentation.brief != nil {
            ProgressView()
                .frame(width: 44, height: 44)
                .accessibilityLabel(Localization.t("ai.brief.refreshing"))
        }
    }

    @ViewBuilder
    private var mainContent: some View {
        switch presentation.phase {
        case .initialLoading:
            loadingContent
        case .idle:
            emptyContent
        case .refreshing, .content, .failure:
            if let brief = presentation.brief {
                briefContent(brief)
            } else {
                emptyContent
            }
        }
    }

    private var loadingContent: some View {
        Button(action: onOpen) {
            HStack(alignment: .top, spacing: AppTheme.Spacing.sm) {
                ProgressView()
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                    Text(Localization.t("ai.brief.loading"))
                        .font(AppTheme.Typography.body.weight(.semibold))
                        .foregroundStyle(Color.appText)
                    Text(Localization.t("ai.brief.loadingDetail"))
                        .font(AppTheme.Typography.caption)
                        .foregroundStyle(Color.appMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 112, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Localization.t("ai.brief.loading"))
        .accessibilityValue(Localization.t("ai.brief.loadingDetail"))
    }

    private var emptyContent: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                Text(Localization.t("ai.brief.emptyTitle"))
                    .font(AppTheme.Typography.body.weight(.semibold))
                    .foregroundStyle(Color.appText)
                Text(Localization.t("ai.brief.emptyDetail"))
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(Color.appMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, minHeight: 112, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Localization.t("ai.brief.emptyTitle"))
        .accessibilityValue(Localization.t("ai.brief.emptyDetail"))
        .accessibilityHint(Localization.t("ai.brief.open"))
    }

    private func briefContent(_ brief: AIDailyBrief) -> some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                HStack(spacing: AppTheme.Spacing.xs) {
                    Text(updatedAtText(brief.generatedAt))
                    if presentation.showsProgress {
                        Text(Localization.t("ai.brief.refreshing"))
                            .foregroundStyle(Color.accentBlue)
                    }
                }
                .font(AppTheme.Typography.caption2)
                .foregroundStyle(Color.appMuted)

                Text(brief.content.summary)
                    .font(.system(.title3, design: .rounded, weight: .bold))
                    .foregroundStyle(Color.appText)
                    .fixedSize(horizontal: false, vertical: true)

                Text(brief.content.detail)
                    .font(AppTheme.Typography.body)
                    .foregroundStyle(Color.appMuted)
                    .fixedSize(horizontal: false, vertical: true)

                evidenceView(brief.content.evidence)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Localization.t("ai.brief.open"))
        .accessibilityValue(accessibilityValue(for: brief))
        .accessibilityHint(Localization.t("ai.brief.openHint"))
    }

    @ViewBuilder
    private func evidenceView(_ evidence: [String]) -> some View {
        if !evidence.isEmpty {
            let content = VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                ForEach(evidence, id: \.self) { item in
                    evidenceLabel(item)
                }
            }

            if dynamicTypeSize.isAccessibilitySize {
                content
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: AppTheme.Spacing.sm) {
                        ForEach(evidence, id: \.self) { item in
                            evidenceLabel(item)
                        }
                    }
                    content
                }
            }
        }
    }

    private func evidenceLabel(_ item: String) -> some View {
        Label(item, systemImage: "checkmark.circle")
            .font(AppTheme.Typography.caption2)
            .foregroundStyle(Color.ghostText)
    }

    private func failureContent(_ failure: AIAssistantFailure) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
            Label(failure.message, systemImage: failureIcon(failure))
                .font(AppTheme.Typography.caption)
                .foregroundStyle(Color.red)
                .fixedSize(horizontal: false, vertical: true)

            if !presentation.recovery.isEmpty {
                recoveryActions
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Localization.t("ai.brief.error"))
        .accessibilityValue(failure.message)
    }

    private var recoveryActions: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: AppTheme.Spacing.sm) {
                ForEach(presentation.recovery, id: \.rawValue) { recovery in
                    recoveryButton(recovery)
                }
            }
            VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                ForEach(presentation.recovery, id: \.rawValue) { recovery in
                    recoveryButton(recovery)
                }
            }
        }
    }

    private func recoveryButton(_ recovery: AIAssistantRecovery) -> some View {
        Button {
            onRecovery(recovery)
        } label: {
            Text(recoveryTitle(recovery))
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(Color.accentBlue)
        .accessibilityLabel(recoveryTitle(recovery))
    }

    private var quickActions: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                verticalQuickActions
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: AppTheme.Spacing.xs) {
                        ForEach(AIDailyBriefQuickAction.allCases) { action in
                            quickActionButton(action)
                        }
                    }
                    verticalQuickActions
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var verticalQuickActions: some View {
        VStack(spacing: AppTheme.Spacing.xs) {
            ForEach(AIDailyBriefQuickAction.allCases) { action in
                quickActionButton(action)
            }
        }
    }

    private func quickActionButton(_ action: AIDailyBriefQuickAction) -> some View {
        Button {
            onQuickAction(action)
        } label: {
            Label(Localization.t(action.titleKey), systemImage: action.systemImage)
                .font(.caption.weight(.semibold))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: 44)
                .padding(.horizontal, AppTheme.Spacing.xs)
                .background(Color.blueSoft, in: RoundedRectangle(cornerRadius: AppTheme.Spacing.radiusSm))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.accentBlue)
        .accessibilityLabel(Localization.t(action.titleKey))
    }

    private func badgeLabel(_ badge: AIDailyBriefBadge) -> some View {
        Text(badgeTitle(badge))
            .font(AppTheme.Typography.caption2)
            .foregroundStyle(badge == .localSuggestion ? Color.chipSourceText : Color.warning)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(
                (badge == .localSuggestion ? Color.chipSourceBg : Color.warning.opacity(0.10)),
                in: Capsule()
            )
            .accessibilityLabel(badgeTitle(badge))
    }

    private func badgeTitle(_ badge: AIDailyBriefBadge) -> String {
        switch badge {
        case .localSuggestion:
            return Localization.t("ai.brief.local")
        case .updateAvailable:
            return Localization.t("ai.brief.updateAvailable")
        }
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

    private func updatedAtText(_ date: Date) -> String {
        Localization.t(
            "ai.brief.updatedAt",
            date.formatted(date: .omitted, time: .shortened)
        )
    }

    private func accessibilityValue(for brief: AIDailyBrief) -> String {
        var values = [updatedAtText(brief.generatedAt), brief.content.summary, brief.content.detail]
        values.append(contentsOf: presentation.badges.map(badgeTitle))
        if presentation.showsProgress {
            values.append(Localization.t("ai.brief.refreshing"))
        }
        return values.joined(separator: "，")
    }
}
