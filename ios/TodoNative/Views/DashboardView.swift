import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var vm: TodoViewModel
    @EnvironmentObject private var aiVM: AIViewModel
    @EnvironmentObject private var purchaseManager: PurchaseManager
    @EnvironmentObject private var trialManager: TrialManager
    @EnvironmentObject private var lang: LanguageEnvironment
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var showPaywall = false
    @State private var showAI = false

    private var isWideLayout: Bool {
        horizontalSizeClass == .regular
    }

    var body: some View {
        let _ = lang.language
        NavigationStack {
            ScrollView {
                VStack(spacing: AppTheme.Spacing.md) {
                    if isWideLayout {
                        HStack(alignment: .top, spacing: AppTheme.Spacing.md) {
                            headerSection
                                .frame(maxWidth: .infinity)
                            statsSection
                                .frame(maxWidth: .infinity)
                        }
                    } else {
                        headerSection
                        statsSection
                    }

                    FeatureGateBanner(
                        isEnabled: purchaseManager.canUsePremiumFeature,
                        title: Localization.t("dashboard.bannerTitle")
                    ) {
                        showPaywall = true
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text(Localization.t("dashboard.todayPlan"))
                                .font(AppTheme.Typography.headline)
                            Spacer()
                            Button(Localization.t("dashboard.aiGenerate")) {
                                aiVM.runTodayPlan(items: vm.unarchivedItems)
                            }
                            .ghostButton()
                            .disabled(aiVM.isBusy)
                            .accessibilityLabel(Localization.t("dashboard.aiGenerateA11y"))

                            Button(Localization.t("dashboard.regenerate")) {
                                aiVM.clearTodayPlanOutput()
                                vm.generatePlan()
                            }
                            .ghostButton()
                            .accessibilityLabel(Localization.t("dashboard.regenerateA11y"))
                        }

                        if aiVM.isTodayPlanOutput, !aiVM.outputText.isEmpty {
                            Text(aiVM.outputText)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(Color.appText)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, AppTheme.Spacing.sm)
                        } else if vm.todayPlan.isEmpty {
                            Text(Localization.t("dashboard.emptyPlan"))
                                .font(AppTheme.Typography.body)
                                .foregroundStyle(Color.appMuted)
                                .padding(.vertical, AppTheme.Spacing.lg)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .accessibilityLabel(Localization.t("dashboard.emptyA11y"))
                        } else {
                            ForEach(vm.todayPlan, id: \.id) { item in
                                TodoCardView(item: item) { status in
                                    vm.updateStatus(item, status: status)
                                } onArchive: {
                                    vm.archive(item)
                                }
                            }
                        }
                    }
                    .appCard()
                }
                .padding(AppTheme.Spacing.md)
            }
            .navigationTitle(Localization.t("dashboard.title"))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 12) {
                        Button(Localization.t("dashboard.aiShort")) { showAI = true }
                        Button(Localization.t("dashboard.subscribe")) { showPaywall = true }
                    }
                }
            }
            .sheet(isPresented: $showAI) {
                AIWorkbenchView()
            }
            .sheet(isPresented: $showPaywall) {
                PaywallView()
            }
        }
        .appBg()
    }

    @ViewBuilder
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(Localization.t("dashboard.title"))
                .font(AppTheme.Typography.title)
            Text(Localization.t("dashboard.subtitle"))
                .font(AppTheme.Typography.caption)
                .foregroundStyle(Color.appMuted)

            Label(
                purchaseManager.hasPremium ? Localization.t("dashboard.premiumOn") : Localization.t("dashboard.freeMode"),
                systemImage: purchaseManager.hasPremium ? "crown.fill" : "clock.fill"
            )
            .font(AppTheme.Typography.caption)
            .foregroundStyle(purchaseManager.hasPremium ? Color.success : Color.warning)

            Text(purchaseManager.hasPremium ? Localization.t("dashboard.subscribed") : Localization.t("dashboard.trialLeft", trialManager.remainingDays))
                .font(AppTheme.Typography.caption)
                .foregroundStyle(Color.appMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .appCard()
    }

    // web .progress-wrap + .stats-grid
    @ViewBuilder
    private var statsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(Localization.t("dashboard.execution"))
                    .font(AppTheme.Typography.headline)
                Spacer()
                Text(Localization.t("dashboard.progress", vm.completionRate, vm.healthScore))
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(Color.appMuted)
            }

            // web .progress-track / #progress-fill（蓝色渐变）
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(hex: 0xF0E6DE))
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [Color(hex: 0x58A3FF), Color(hex: 0x3F75FF)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(0, min(1, CGFloat(vm.completionRate) / 100)) * geo.size.width)
                }
            }
            .frame(height: 8)

            // web .stats-grid（4 个 stat-card）
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: isWideLayout ? 4 : 2), spacing: 8) {
                statCard(label: Localization.t("dashboard.statTotal"), value: "\(vm.unarchivedItems.count)")
                statCard(label: Localization.t("dashboard.statActive"), value: "\(vm.todoItems.count + vm.doingItems.count)", color: .accentBlue)
                statCard(label: Localization.t("dashboard.statCompleted"), value: "\(vm.completedItems.count)", color: .success)
                statCard(label: Localization.t("dashboard.statHealth"), value: "\(vm.healthScore)", color: .warning)
            }

            Text(vm.healthLabel())
                .font(AppTheme.Typography.caption)
                .foregroundStyle(Color.appMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .appCard()
    }

    private func statCard(label: String, value: String, color: Color = Color.appText) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(AppTheme.Typography.caption2)
                .foregroundStyle(Color.appMuted)
            Text(value)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.white)
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Spacing.radiusMd)
                .stroke(Color(hex: 0xEFE4DC), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Spacing.radiusMd))
    }
}
