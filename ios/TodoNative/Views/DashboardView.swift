import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var vm: TodoViewModel
    @EnvironmentObject private var purchaseManager: PurchaseManager
    @EnvironmentObject private var trialManager: TrialManager
    @EnvironmentObject private var lang: LanguageEnvironment
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showAI = false

    private var isWideLayout: Bool {
        horizontalSizeClass == .regular
    }

    private var listAnimation: Animation? {
        reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.8)
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

                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text(Localization.t("dashboard.todayPlan"))
                                .font(AppTheme.Typography.headline)
                            Spacer()
                            Button(Localization.t("dashboard.regenerate")) {
                                vm.generatePlan()
                            }
                            .ghostButton()
                            .accessibilityLabel(Localization.t("dashboard.regenerateA11y"))

                            Button(Localization.t("ai.todayPlan")) { showAI = true }
                                .ghostButton()
                        }

                        if vm.todayPlan.isEmpty {
                            Text(Localization.t("dashboard.emptyPlan"))
                                .font(AppTheme.Typography.body)
                                .foregroundStyle(Color.appMuted)
                                .padding(.vertical, AppTheme.Spacing.lg)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .accessibilityLabel(Localization.t("dashboard.emptyA11y"))
                        } else {
                            ForEach(vm.todayPlan, id: \.id) { item in
                                TodoCardView(item: item) { status in
                                    withAnimation(listAnimation) { vm.updateStatus(item, status: status) }
                                } onArchive: {
                                    withAnimation(listAnimation) { vm.archive(item) }
                                }
                                .transition(.asymmetric(
                                    insertion: .opacity.combined(with: .move(edge: .bottom)),
                                    removal: .opacity.combined(with: .scale(scale: 0.85))
                                ))
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
                    Button(Localization.t("dashboard.aiShort")) { showAI = true }
                }
            }
            .sheet(isPresented: $showAI) {
                AIWorkbenchView()
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
                        .animation(reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.75), value: vm.completionRate)
                }
            }
            .frame(height: 8)

            // web .stats-grid（4 个 stat-card）
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: isWideLayout ? 4 : 2), spacing: 8) {
                StatCard(label: Localization.t("dashboard.statTotal"), value: "\(vm.unarchivedItems.count)", color: .appText)
                StatCard(label: Localization.t("dashboard.statActive"), value: "\(vm.todoItems.count + vm.doingItems.count)", color: .accentBlue)
                StatCard(label: Localization.t("dashboard.statCompleted"), value: "\(vm.completedItems.count)", color: .success)
                StatCard(label: Localization.t("dashboard.statHealth"), value: "\(vm.healthScore)", color: .warning)
            }

            Text(vm.healthLabel())
                .font(AppTheme.Typography.caption)
                .foregroundStyle(Color.appMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .appCard()
    }
}

private struct StatCard: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let label: String
    let value: String
    let color: Color

    @State private var popScale: CGFloat = 1

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(AppTheme.Typography.caption2)
                .foregroundStyle(Color.appMuted)
            Text(value)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(color)
                .contentTransition(.numericText(countsDown: false))
                .scaleEffect(popScale)
                .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.7), value: value)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.white)
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Spacing.radiusMd)
                .stroke(Color(hex: 0xEFE4DC), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Spacing.radiusMd))
        .onChange(of: value) { _, _ in
            guard !reduceMotion else { return }
            withAnimation(.spring(response: 0.15, dampingFraction: 0.5)) { popScale = 1.08 }
            withAnimation(.spring(response: 0.25, dampingFraction: 0.7).delay(0.09)) { popScale = 1 }
        }
    }
}
