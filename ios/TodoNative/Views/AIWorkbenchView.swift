import SwiftUI
import UIKit

struct AIWorkbenchView: View {
    @EnvironmentObject private var vm: TodoViewModel
    @EnvironmentObject private var aiVM: AIViewModel
    @EnvironmentObject private var briefing: AIBriefingViewModel
    @EnvironmentObject private var lang: LanguageEnvironment
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var isContextExpanded = false
    @State private var quotaSnapshot: QuotaSnapshot?
    @State private var confirmation: AIWorkbenchConfirmationPresentation?
    @State private var confirmationToken = UUID()
    @State private var isGoalPickerPresented = false

    private let onRecovery: (AIAssistantRecovery) -> Void

    init(onRecovery: @escaping (AIAssistantRecovery) -> Void = { _ in }) {
        self.onRecovery = onRecovery
    }

    private var modePresentation: AIWorkbenchModePresentation {
        AIWorkbenchModePresentation(mode: briefing.mode)
    }

    private var contextPresentation: AIWorkbenchContextPresentation {
        AIWorkbenchContextPresentation(context: assistantContext)
    }

    private var assistantContext: AIAssistantContext {
        AIAssistantContext(items: vm.unarchivedItems, health: vm.healthScore)
    }

    private var goalPickerPresentation: AIGoalPickerPresentation {
        AIGoalPickerPresentation(items: vm.items, query: "")
    }

    private var goalCandidateRevision: String {
        AIGoalPickerPresentation.candidateRevision(items: vm.items)
    }

    private var selectedGoalCandidate: AIGoalPickerCandidate? {
        guard let selectedGoalTaskID = briefing.selectedGoalTaskID else { return nil }
        return goalPickerPresentation.all.first { $0.id == selectedGoalTaskID }
    }

    private var currentSelectedGoalFingerprint: String? {
        briefing.selectedGoalContext(in: vm.items)?.fingerprint
    }

    private var latestResultSource: AIAssistantSource? {
        workbenchPresentation.currentResultSource
    }

    private var workbenchPresentation: AIWorkbenchSessionPresentation {
        AIWorkbenchSessionPresentation(
            state: briefing.workbenchState,
            currentMode: briefing.mode,
            currentGoal: briefing.goal,
            currentContextFingerprint: assistantContext.fingerprint,
            currentSelectedGoalFingerprint: currentSelectedGoalFingerprint
        )
    }

    private var servicePresentation: AIWorkbenchServicePresentation {
        AIWorkbenchServicePresentation(
            apiKey: aiVM.apiKey,
            managedBaseURL: QuotaClient.baseURL,
            providerName: aiVM.activeProvider.name,
            model: aiVM.effectiveModel,
            latestResultSource: latestResultSource,
            quotaSnapshot: quotaSnapshot,
            failure: workbenchPresentation.failure
        )
    }

    private var quotaConfigurationID: String {
        let apiKey = aiVM.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseURL = (QuotaClient.baseURL ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return apiKey.isEmpty ? "managed:\(baseURL)" : "custom"
    }

    private var selectedApplication: AIWorkbenchApplication {
        briefing.selectedTasksForApplication(
            existingItems: vm.unarchivedItems,
            currentContext: assistantContext,
            currentSelectedGoalFingerprint: currentSelectedGoalFingerprint
        )
    }

    private var resultPresentation: AIWorkbenchResultPresentation? {
        guard let session = workbenchPresentation.session else { return nil }
        return AIWorkbenchResultPresentation(
            mode: briefing.mode,
            importableCount: selectedApplication.count,
            hasSuggestedTasks: !session.result.suggestedTasks.isEmpty,
            isSessionImportable: workbenchPresentation.isFresh
                && workbenchPresentation.phase != .loading
        )
    }

    private var isLoading: Bool {
        workbenchPresentation.phase == .loading
    }

    private var canGenerate: Bool {
        modePresentation.canGenerate(
            goal: briefing.goal,
            selectedGoalFingerprint: currentSelectedGoalFingerprint
        )
    }

    private var accessibilityAnnouncement: String? {
        switch workbenchPresentation.phase {
        case .idle:
            return nil
        case .loading:
            return Localization.t("ai.workbench.loading")
        case .result:
            return Localization.t("ai.workbench.resultReady")
        case .failed:
            return workbenchPresentation.failure?.message
        }
    }

    var body: some View {
        let _ = lang.language
        NavigationStack {
            ScrollView {
                VStack(spacing: AppTheme.Spacing.md) {
                    serviceStatus
                    modeSelector
                    contextDisclosure
                    promptCard
                    AIWorkbenchResultView(
                        presentation: workbenchPresentation,
                        mode: briefing.mode,
                        selectedTaskIDs: briefing.selectedTaskIDs,
                        onToggle: briefing.toggleTask,
                        onRetry: runWorkbench,
                        onRecovery: recover
                    )
                    .animation(
                        AppTheme.Motion.resolvedFade(
                            AppTheme.Motion.content,
                            reduceMotion: reduceMotion
                        ),
                        value: briefing.workbenchState
                    )
                }
                .padding(AppTheme.Spacing.md)
            }
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom) {
                bottomActions
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(Localization.t("common.done")) {
                        dismiss()
                    }
                    .frame(minWidth: 44, minHeight: 44)
                    .accessibilityLabel(Localization.t("common.done"))
                }
            }
            .onChange(of: accessibilityAnnouncement) {
                guard
                    UIAccessibility.isVoiceOverRunning,
                    let announcement = accessibilityAnnouncement
                else { return }
                UIAccessibility.post(
                    notification: .announcement,
                    argument: announcement
                )
            }
            .onAppear(perform: reconcileSelectedGoal)
            .onChange(of: goalCandidateRevision) {
                reconcileSelectedGoal()
            }
            .task(id: quotaConfigurationID) {
                await refreshManagedQuota()
            }
            .overlay(alignment: .top) {
                confirmationBanner
                    .padding(.horizontal, AppTheme.Spacing.md)
                    .padding(.top, AppTheme.Spacing.sm)
            }
        }
        .sheet(isPresented: $isGoalPickerPresented) {
            AIGoalPicker(
                items: vm.items,
                selectedGoalTaskID: briefing.selectedGoalTaskID,
                onSelect: selectGoalCandidate,
                onDirectInput: useDirectGoalInput
            )
        }
        .appBg()
    }

    private var serviceStatus: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            Text(Localization.t("ai.workbench.title"))
                .font(AppTheme.Typography.caption)
                .foregroundStyle(Color.accentBlue)
                .textCase(.uppercase)

            Text(Localization.t("ai.workbench.subtitle"))
                .font(.system(.title2, design: .rounded, weight: .bold))
                .foregroundStyle(Color.appText)
                .fixedSize(horizontal: false, vertical: true)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: AppTheme.Spacing.xs) {
                    serviceLabel
                    Spacer(minLength: 0)
                }
                VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                    serviceLabel
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .appCard()
    }

    private var serviceLabel: some View {
        Label {
            VStack(alignment: .leading, spacing: 1) {
                Text(Localization.t(servicePresentation.statusKey))
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(Color.appText)
                if
                    let remaining = servicePresentation.quotaRemaining,
                    let limit = servicePresentation.quotaLimit
                {
                    Text(Localization.t("ai.workbench.status.remaining", remaining, limit))
                        .font(AppTheme.Typography.caption2)
                        .foregroundStyle(Color.appMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let detail = servicePresentation.detail, !detail.isEmpty {
                    Text(detail)
                        .font(AppTheme.Typography.caption2)
                        .foregroundStyle(Color.appMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        } icon: {
            Image(systemName: serviceIcon)
                .foregroundStyle(serviceColor)
        }
        .frame(minHeight: 44, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Localization.t("ai.workbench.service"))
        .accessibilityValue(
            [
                Localization.t(servicePresentation.statusKey),
                serviceQuotaDetail,
                servicePresentation.detail
            ]
                .compactMap { $0 }
                .joined(separator: "，")
        )
    }

    private var serviceQuotaDetail: String? {
        guard
            let remaining = servicePresentation.quotaRemaining,
            let limit = servicePresentation.quotaLimit
        else { return nil }
        return Localization.t("ai.workbench.status.remaining", remaining, limit)
    }

    @ViewBuilder
    private var confirmationBanner: some View {
        if
            let confirmation,
            confirmation.isVisible,
            let messageKey = confirmation.messageKey
        {
            Label(
                Localization.t(messageKey, confirmation.count),
                systemImage: "checkmark.circle.fill"
            )
            .font(AppTheme.Typography.body.weight(.semibold))
            .foregroundStyle(Color.appText)
            .padding(.horizontal, AppTheme.Spacing.md)
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
            .background(Color.appCardBg, in: RoundedRectangle(cornerRadius: AppTheme.Spacing.radiusMd))
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.Spacing.radiusMd)
                    .stroke(Color.appLine, lineWidth: 1)
            )
            .shadow(color: Color.appText.opacity(0.12), radius: 12, y: 4)
            .transition(.move(edge: .top).combined(with: .opacity))
            .accessibilityElement(children: .combine)
        }
    }

    @ViewBuilder
    private var modeSelector: some View {
        if dynamicTypeSize.isAccessibilitySize {
            Menu {
                Picker(Localization.t("ai.workbench.mode"), selection: $briefing.mode) {
                    modeOptions
                }
            } label: {
                HStack(spacing: AppTheme.Spacing.sm) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(Localization.t("ai.workbench.mode"))
                            .font(AppTheme.Typography.caption2)
                            .foregroundStyle(Color.appMuted)
                        Text(Localization.t(modePresentation.titleKey))
                            .font(AppTheme.Typography.body.weight(.semibold))
                            .foregroundStyle(Color.appText)
                    }
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .foregroundStyle(Color.accentBlue)
                }
                .padding(.horizontal, AppTheme.Spacing.md)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(Color.appCardBg)
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.Spacing.radiusMd)
                        .stroke(Color.appLine, lineWidth: 1)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Localization.t("ai.workbench.mode"))
            .accessibilityValue(Localization.t(modePresentation.titleKey))
        } else {
            Picker(Localization.t("ai.workbench.mode"), selection: $briefing.mode) {
                modeOptions
            }
            .pickerStyle(.segmented)
            .frame(minHeight: 44)
            .accessibilityLabel(Localization.t("ai.workbench.mode"))
            .accessibilityValue(Localization.t(modePresentation.titleKey))
        }
    }

    @ViewBuilder
    private var modeOptions: some View {
        ForEach(AIWorkbenchMode.allCases) { mode in
            Text(Localization.t(AIWorkbenchModePresentation(mode: mode).titleKey))
                .tag(mode)
        }
    }

    private var contextDisclosure: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
            DisclosureGroup(isExpanded: $isContextExpanded) {
                Text(
                    Localization.t(
                        "ai.workbench.contextDetail",
                        contextPresentation.todoCount,
                        contextPresentation.doingCount,
                        contextPresentation.doneCount
                    )
                )
                .font(AppTheme.Typography.caption)
                .foregroundStyle(Color.appMuted)
                .padding(.top, AppTheme.Spacing.xs)
                .fixedSize(horizontal: false, vertical: true)
            } label: {
                VStack(alignment: .leading, spacing: 3) {
                    Text(Localization.t("ai.workbench.context"))
                        .font(AppTheme.Typography.caption)
                        .foregroundStyle(Color.accentBlue)
                    Text(
                        Localization.t(
                            "ai.workbench.contextSummary",
                            contextPresentation.taskCount,
                            contextPresentation.deadlineCount,
                            contextPresentation.health
                        )
                    )
                    .font(AppTheme.Typography.body)
                    .foregroundStyle(Color.appText)
                    .fixedSize(horizontal: false, vertical: true)
                }
                .frame(minHeight: 44, alignment: .leading)
            }

            Label(
                Localization.t("ai.workbench.noAutomaticChanges"),
                systemImage: "hand.raised.fill"
            )
            .font(AppTheme.Typography.caption)
            .foregroundStyle(Color.appMuted)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .combine)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .appCard()
    }

    private var promptCard: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            Text(Localization.t(modePresentation.questionKey))
                .font(AppTheme.Typography.headline)
                .foregroundStyle(Color.appText)
                .fixedSize(horizontal: false, vertical: true)

            if briefing.mode == .breakdown {
                if let selectedGoalCandidate {
                    AISelectedGoalSummary(
                        candidate: selectedGoalCandidate,
                        onChange: { isGoalPickerPresented = true },
                        onClear: briefing.clearSelectedGoalTask
                    )
                } else {
                    Button {
                        isGoalPickerPresented = true
                    } label: {
                        Label(
                            Localization.t("ai.goalPicker.chooseExisting"),
                            systemImage: "list.bullet.rectangle"
                        )
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.accentBlue)
                    .accessibilityLabel(Localization.t("ai.goalPicker.chooseExisting"))
                }
            }

            TextField(
                Localization.t(modePresentation.placeholderKey),
                text: $briefing.goal,
                axis: .vertical
            )
            .font(AppTheme.Typography.body)
            .foregroundStyle(Color.appText)
            .lineLimit(3...8)
            .padding(AppTheme.Spacing.sm)
            .frame(maxWidth: .infinity, minHeight: 104, alignment: .topLeading)
            .background(Color.appBg, in: RoundedRectangle(cornerRadius: AppTheme.Spacing.radiusSm))
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.Spacing.radiusSm)
                    .stroke(Color.appLine, lineWidth: 1)
            )
            .accessibilityLabel(Localization.t("ai.workbench.goalA11y"))
            .accessibilityValue(briefing.goal)

            promptChips

            Button(action: runWorkbench) {
                HStack(spacing: AppTheme.Spacing.xs) {
                    if isLoading {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Image(systemName: "sparkles")
                    }
                    Text(Localization.t(modePresentation.primaryActionKey))
                }
                .frame(maxWidth: .infinity, minHeight: 50)
            }
            .primaryActionButton()
            .disabled(isLoading || !canGenerate)
            .accessibilityLabel(Localization.t(modePresentation.primaryActionKey))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .appCard()
    }

    @ViewBuilder
    private var promptChips: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                ForEach(modePresentation.chipKeys, id: \.self) { key in
                    promptChip(key)
                }
            }
        } else {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: AppTheme.Spacing.xs) {
                    ForEach(modePresentation.chipKeys, id: \.self) { key in
                        promptChip(key)
                    }
                }
                VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                    ForEach(modePresentation.chipKeys, id: \.self) { key in
                        promptChip(key)
                    }
                }
            }
        }
    }

    private func promptChip(_ key: String) -> some View {
        let title = Localization.t(key)
        return Button {
            applyPromptChip(title)
        } label: {
            Text(title)
                .font(AppTheme.Typography.caption)
                .foregroundStyle(Color.chipGreenText)
                .multilineTextAlignment(.leading)
                .padding(.horizontal, 10)
                .frame(minHeight: 44)
                .background(Color.greenSoft, in: Capsule())
                .overlay(Capsule().stroke(Color.chipGreenBorder, lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }

    @ViewBuilder
    private var bottomActions: some View {
        if let presentation = resultPresentation {
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(spacing: AppTheme.Spacing.xs) {
                        regenerateButton
                        importButton(presentation)
                    }
                } else {
                    HStack(spacing: AppTheme.Spacing.sm) {
                        regenerateButton
                        importButton(presentation)
                    }
                }
            }
            .padding(.horizontal, AppTheme.Spacing.md)
            .padding(.vertical, AppTheme.Spacing.sm)
            .background(.ultraThinMaterial)
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(Color.appLine)
                    .frame(height: 1)
            }
        }
    }

    private var regenerateButton: some View {
        Button(Localization.t("ai.workbench.regenerate"), action: runWorkbench)
            .ghostButton()
            .frame(maxWidth: .infinity, minHeight: 50)
            .disabled(isLoading || !canGenerate)
            .accessibilityLabel(Localization.t("ai.workbench.regenerate"))
    }

    @ViewBuilder
    private func importButton(_ presentation: AIWorkbenchResultPresentation) -> some View {
        if presentation.showsImport, let importKey = presentation.importKey {
            Button {
                importSelectedTasks()
            } label: {
                Text(Localization.t(importKey, presentation.importCount))
                    .frame(maxWidth: .infinity, minHeight: 50)
            }
            .primaryActionButton()
            .disabled(!presentation.canImport)
            .accessibilityLabel(Localization.t(importKey, presentation.importCount))
            .accessibilityValue(
                presentation.canImport
                    ? Localization.t("ai.workbench.selected")
                    : Localization.t("ai.workbench.notSelected")
            )
        }
    }

    private var serviceIcon: String {
        switch servicePresentation.kind {
        case .custom:
            return "key.fill"
        case .managed:
            return "cloud.fill"
        case .local:
            return "iphone"
        }
    }

    private var serviceColor: Color {
        switch servicePresentation.tone {
        case .neutral:
            return .accentBlue
        case .success:
            return .success
        case .warning:
            return .warning
        case .critical:
            return .brand
        }
    }

    private func applyPromptChip(_ prompt: String) {
        let trimmedGoal = briefing.goal.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedGoal.localizedCaseInsensitiveContains(prompt) else { return }
        briefing.goal = trimmedGoal.isEmpty
            ? prompt
            : "\(briefing.goal)\n\(prompt)"
    }

    private func selectGoalCandidate(_ candidate: AIGoalPickerCandidate) {
        guard
            let currentItem = vm.items.first(where: { $0.id == candidate.id }),
            AIGoalPickerCandidate(item: currentItem) != nil
        else {
            reconcileSelectedGoal()
            return
        }
        briefing.selectGoalTask(currentItem)
        isGoalPickerPresented = false
    }

    private func useDirectGoalInput() {
        briefing.clearSelectedGoalTask()
        isGoalPickerPresented = false
    }

    private func reconcileSelectedGoal() {
        briefing.reconcileSelectedGoal(in: vm.items)
    }

    private func runWorkbench() {
        guard !isLoading, canGenerate else { return }
        Task {
            await briefing.runWorkbench(
                items: vm.unarchivedItems,
                health: vm.healthScore
            )
            await refreshManagedQuota()
        }
    }

    private func importSelectedTasks() {
        let application = selectedApplication
        let presentation = AIWorkbenchResultPresentation(
            mode: briefing.mode,
            importableCount: application.count,
            hasSuggestedTasks: true
        )
        guard
            presentation.canImport,
            let announcementKey = presentation.importAnnouncementKey
        else { return }

        guard let provenance = workbenchPresentation.session?.provenance else { return }
        let sourceGoal = provenance.mode == .todayPlan
            ? "ai-today-plan"
            : provenance.goal.trimmingCharacters(in: .whitespacesAndNewlines)
        let appliedCount: Int
        if provenance.mode == .todayPlan {
            appliedCount = vm.applyTodayPlan(application, sourceGoal: sourceGoal)
        } else {
            appliedCount = vm.importSuggestedTasks(
                application.newTasks,
                sourceGoal: sourceGoal
            ).count
        }
        guard appliedCount > 0 else { return }

        let confirmation = AIWorkbenchConfirmationPresentation(
            mode: provenance.mode,
            appliedCount: appliedCount
        )
        showConfirmation(confirmation)

        guard UIAccessibility.isVoiceOverRunning else { return }
        UIAccessibility.post(
            notification: .announcement,
            argument: Localization.t(announcementKey, appliedCount)
        )
    }

    @MainActor
    private func refreshManagedQuota() async {
        let hasAPIKey = !aiVM.apiKey
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty
        let hasManagedBaseURL = !(QuotaClient.baseURL ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty
        guard !hasAPIKey, hasManagedBaseURL else {
            quotaSnapshot = nil
            return
        }
        quotaSnapshot = try? await QuotaClient.quota()
    }

    @MainActor
    private func showConfirmation(_ presentation: AIWorkbenchConfirmationPresentation) {
        guard presentation.isVisible else { return }
        let token = UUID()
        confirmationToken = token
        withAnimation(AppTheme.Motion.resolvedFade(AppTheme.Motion.content, reduceMotion: reduceMotion)) {
            confirmation = presentation
        }

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            guard confirmationToken == token else { return }
            withAnimation(AppTheme.Motion.resolvedFade(AppTheme.Motion.content, reduceMotion: reduceMotion)) {
                confirmation = nil
            }
        }
    }

    private func recover(_ recovery: AIAssistantRecovery) {
        dismiss()
        onRecovery(recovery)
    }
}
