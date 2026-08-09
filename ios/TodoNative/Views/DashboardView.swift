import SwiftUI

enum DashboardAccessStatus: Equatable {
    case premium
    case trial(remainingDays: Int)
    case free

    static func resolve(hasPremium: Bool, trialState: TrialState) -> DashboardAccessStatus {
        if hasPremium {
            return .premium
        }

        switch trialState {
        case .premium:
            return .premium
        case let .trial(remainingDays):
            return .trial(remainingDays: remainingDays)
        case .free:
            return .free
        }
    }
}

enum DashboardSheet: String, Identifiable {
    case aiPlan
    case paywall

    var id: String { rawValue }

    static func aiRoute(canUseAIPlan: Bool) -> DashboardSheet {
        canUseAIPlan ? .aiPlan : .paywall
    }

    static func membershipRoute(accessStatus: DashboardAccessStatus) -> DashboardSheet? {
        accessStatus == .premium ? nil : .paywall
    }
}

struct DashboardView: View {
    @EnvironmentObject private var vm: TodoViewModel
    @EnvironmentObject private var purchaseManager: PurchaseManager
    @EnvironmentObject private var trialManager: TrialManager
    @EnvironmentObject private var lang: LanguageEnvironment
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var activeSheet: DashboardSheet?

    private var listAnimation: Animation? {
        AppTheme.Motion.resolvedFade(AppTheme.Motion.content, reduceMotion: reduceMotion)
    }

    private var planTransition: AnyTransition {
        if reduceMotion {
            return .opacity
        }
        return .asymmetric(
            insertion: .opacity.combined(with: .offset(y: 8)),
            removal: .opacity
        )
    }

    private var accessStatus: DashboardAccessStatus {
        DashboardAccessStatus.resolve(
            hasPremium: purchaseManager.hasPremium,
            trialState: trialManager.trialState
        )
    }

    private var membershipText: String {
        switch accessStatus {
        case .premium:
            return Localization.t("dashboard.premiumOn")
        case let .trial(remainingDays):
            return Localization.t("dashboard.trialLeft", remainingDays)
        case .free:
            return Localization.t("dashboard.freeMode")
        }
    }

    private var membershipColor: Color {
        switch accessStatus {
        case .premium:
            return .success
        case .trial:
            return .warning
        case .free:
            return .appMuted
        }
    }

    var body: some View {
        let _ = lang.language
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                    executionSummary
                    todayPlan
                }
                .padding(AppTheme.Spacing.md)
            }
            .navigationTitle(Localization.t("dashboard.title"))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(Localization.t("dashboard.aiShort")) {
                        presentAIPlan()
                    }
                }
            }
            .sheet(item: $activeSheet) { sheet in
                switch sheet {
                case .aiPlan:
                    AIWorkbenchView()
                case .paywall:
                    PaywallView()
                }
            }
        }
        .appBg()
    }

    private var executionSummary: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                    completionHeading
                    membershipButton
                }
            } else {
                HStack(alignment: .firstTextBaseline) {
                    completionHeading
                    Spacer()
                    membershipButton
                }
            }

            ProgressView(value: Double(vm.completionRate), total: 100)
                .tint(Color.accentBlue)
                .animation(AppTheme.Motion.resolved(AppTheme.Motion.progress, reduceMotion: reduceMotion), value: vm.completionRate)
                .accessibilityLabel(Localization.t("dashboard.execution"))
                .accessibilityValue(Localization.t("dashboard.progress", vm.completionRate, vm.healthScore))

            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                    summaryMetrics
                }
            } else {
                HStack(spacing: AppTheme.Spacing.lg) {
                    summaryMetrics
                    Spacer(minLength: 0)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .appCard()
    }

    private var completionHeading: some View {
        HStack(alignment: .firstTextBaseline, spacing: AppTheme.Spacing.xs) {
                Text("\(vm.completionRate)%")
                    .font(.system(.title, design: .rounded, weight: .bold))
                    .foregroundStyle(Color.appText)
                    .contentTransition(reduceMotion ? .identity : .numericText(countsDown: false))
                    .animation(AppTheme.Motion.resolved(AppTheme.Motion.stateChange, reduceMotion: reduceMotion), value: vm.completionRate)
                Text(Localization.t("dashboard.execution"))
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(Color.appMuted)
        }
    }

    @ViewBuilder
    private var membershipButton: some View {
        if accessStatus == .premium {
            membershipLabel
                .frame(minHeight: 44)
                .accessibilityLabel(membershipText)
        } else {
            Button {
                activeSheet = DashboardSheet.membershipRoute(accessStatus: accessStatus)
            } label: {
                membershipLabel
            }
            .buttonStyle(.plain)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
            .accessibilityLabel(membershipText)
        }
    }

    private var membershipLabel: some View {
        Label(membershipText, systemImage: accessStatus == .premium ? "crown.fill" : "clock.fill")
            .font(AppTheme.Typography.caption)
            .foregroundStyle(membershipColor)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(membershipColor.opacity(0.12), in: Capsule())
    }

    @ViewBuilder
    private var summaryMetrics: some View {
        Group {
            SummaryMetric(
                    label: Localization.t("dashboard.statActive"),
                    value: vm.todoItems.count + vm.doingItems.count,
                    color: .accentBlue,
                    reduceMotion: reduceMotion
                )
            SummaryMetric(
                    label: Localization.t("dashboard.statCompleted"),
                    value: vm.completedItems.count,
                    color: .success,
                    reduceMotion: reduceMotion
                )
            SummaryMetric(
                    label: Localization.t("dashboard.statHealth"),
                    value: vm.healthScore,
                    color: .warning,
                    reduceMotion: reduceMotion
                )
        }
    }

    private var todayPlan: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            HStack {
                Text(Localization.t("dashboard.todayPlan"))
                    .font(AppTheme.Typography.headline)
                Spacer()
                if !vm.todayPlan.isEmpty {
                    Menu {
                        Button(Localization.t("dashboard.regenerate")) {
                            vm.generatePlan()
                        }
                        Button(Localization.t("dashboard.aiOptimize")) {
                            presentAIPlan()
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.title3)
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel(Localization.t("dashboard.todayPlan"))
                }
            }

            if vm.todayPlan.isEmpty {
                VStack(spacing: AppTheme.Spacing.sm) {
                    Text(Localization.t("dashboard.emptyPlan"))
                        .font(AppTheme.Typography.body)
                        .foregroundStyle(Color.appMuted)
                        .multilineTextAlignment(.center)
                        .accessibilityLabel(Localization.t("dashboard.emptyA11y"))
                    Button(Localization.t("dashboard.aiGenerate")) {
                        presentAIPlan()
                    }
                    .primaryActionButton()
                    .accessibilityLabel(Localization.t("dashboard.aiGenerateA11y"))
                }
                .padding(.vertical, AppTheme.Spacing.sm)
                .frame(maxWidth: .infinity)
            } else {
                ForEach(vm.todayPlan, id: \.id) { item in
                    TodoCardView(item: item) { status in
                        withAnimation(listAnimation) {
                            vm.updateStatus(item, status: status)
                        }
                    } onArchive: {
                        withAnimation(listAnimation) {
                            vm.archive(item)
                        }
                    }
                    .transition(planTransition)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .appCard()
    }

    private func presentAIPlan() {
        activeSheet = DashboardSheet.aiRoute(canUseAIPlan: purchaseManager.canUse(.aiPlan))
    }
}

private struct SummaryMetric: View {
    let label: String
    let value: Int
    let color: Color
    let reduceMotion: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(AppTheme.Typography.caption2)
                .foregroundStyle(Color.appMuted)
            Text("\(value)")
                .font(.system(.headline, design: .rounded, weight: .bold))
                .foregroundStyle(color)
                .contentTransition(reduceMotion ? .identity : .numericText(countsDown: false))
                .animation(AppTheme.Motion.resolved(AppTheme.Motion.stateChange, reduceMotion: reduceMotion), value: value)
        }
    }
}
