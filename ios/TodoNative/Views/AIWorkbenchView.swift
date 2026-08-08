import SwiftUI

struct AIWorkbenchView: View {
    @EnvironmentObject private var vm: TodoViewModel
    @EnvironmentObject private var aiVM: AIViewModel
    @EnvironmentObject private var lang: LanguageEnvironment
    @Environment(\.dismiss) private var dismiss

    @State private var goal = ""

    var body: some View {
        let _ = lang.language
        NavigationStack {
            ScrollView {
                VStack(spacing: AppTheme.Spacing.md) {
                    inputSection
                    statusSection
                    outputSection

                    if !aiVM.suggestedTasks.isEmpty {
                        Button(Localization.t("ai.addToTodo", aiVM.suggestedTasks.count)) {
                            aiVM.importSuggestedTasks()
                        }
                        .primaryActionButton()
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(AppTheme.Spacing.md)
            }
            .navigationTitle(Localization.t("ai.title"))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(Localization.t("common.done")) { dismiss() }
                }
            }
            .onAppear {
                aiVM.importHandler = { texts in
                    let existing = Set(vm.unarchivedItems.map { $0.title })
                    for text in texts where !existing.contains(text) {
                        vm.captureNaturalLanguage(text, type: .personal, sourceGoal: goal)
                    }
                }
            }
        }
        .appBg()
    }

    @ViewBuilder
    private var inputSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(Localization.t("ai.goal"))
                .font(AppTheme.Typography.headline)

            TextEditor(text: $goal)
                .font(AppTheme.Typography.body)
                .frame(minHeight: 100)
                .padding(8)
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.Spacing.radiusSm)
                        .stroke(Color.appLine, lineWidth: 1)
                )
                .accessibilityLabel(Localization.t("ai.goalA11y"))

            VStack(spacing: AppTheme.Spacing.sm) {
                Button(Localization.t("ai.breakdown")) {
                    aiVM.runBreakdown(goal: goal, items: vm.unarchivedItems)
                }
                .primaryActionButton()
                .frame(maxWidth: .infinity)
                .disabled(aiVM.isBusy || goal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Button(Localization.t("ai.summary")) {
                    aiVM.runSummary(items: vm.unarchivedItems, health: vm.healthScore)
                }
                .ghostButton()
                .frame(maxWidth: .infinity)
                .disabled(aiVM.isBusy)

                Button(Localization.t("ai.todayPlan")) {
                    aiVM.runTodayPlan(items: vm.unarchivedItems)
                }
                .ghostButton()
                .frame(maxWidth: .infinity)
                .disabled(aiVM.isBusy)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .appCard()
    }

    @ViewBuilder
    private var statusSection: some View {
        HStack(spacing: 8) {
            if aiVM.isBusy {
                ProgressView()
            }
            Text(aiVM.statusMessage)
                .font(AppTheme.Typography.caption)
                .foregroundStyle(Color.appMuted)
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var outputSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(Localization.t("ai.output"))
                .font(AppTheme.Typography.headline)

            ScrollView {
                Text(aiVM.outputText.isEmpty ? Localization.t("ai.outputEmpty") : aiVM.outputText)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(Color.appText)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minHeight: 160)
            .padding(10)
            .background(Color.appBg)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Spacing.radiusSm))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .appCard()
    }
}
