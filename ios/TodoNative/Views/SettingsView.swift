import SwiftUI
import UIKit
import UserNotifications

struct SettingsView: View {
    @EnvironmentObject private var trialManager: TrialManager
    @EnvironmentObject private var purchaseManager: PurchaseManager
    @EnvironmentObject private var vm: TodoViewModel
    @EnvironmentObject private var aiVM: AIViewModel
    @EnvironmentObject private var lang: LanguageEnvironment
    @EnvironmentObject private var notificationService: NotificationService

    @State private var exportedText = ""
    @State private var exportFileName = "todo-list-app.md"
    @State private var showPaywall = false
    @State private var showExport = false
    @State private var copied = false
    @State private var showNotificationSettingsPrompt = false
#if DEBUG
    @State private var showTestResult = false
    @State private var sentTestOK = false
#endif
    @AppStorage("companion_name") private var buddyName = ""
    @AppStorage("companion_greeting_enabled") private var buddyGreeting = true

#if DEBUG
    private var pendingCountText: String {
        Localization.t("notice.debugPendingCount", notificationService.pendingReminderCount)
    }
#endif

    private var systemNotificationText: String {
        switch notificationService.systemAuthorizationStatus {
        case .authorized, .ephemeral, .provisional:
            return Localization.t("notice.systemAllowed")
        case .denied:
            return Localization.t("notice.systemDenied")
        case .notDetermined:
            return Localization.t("notice.systemNotDetermined")
        @unknown default:
            return Localization.t("notice.systemDenied")
        }
    }

    private func refreshNotificationStatus() {
        Task { await notificationService.refresh() }
    }

#if DEBUG
    // 发送一条 5 秒后的测试通知，验证权限/链路
    private func sendTestNotification() {
        let content = UNMutableNotificationContent()
        content.title = Localization.t("notification.dueTitle")
        content.body = Localization.t("settings.testBody")
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: "test-notification-\(UUID().uuidString)",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
        )
        UNUserNotificationCenter.current().add(request) { error in
            DispatchQueue.main.async {
                sentTestOK = error == nil
                showTestResult = true
            }
        }
    }
#endif

    var body: some View {
        let _ = lang.language
        NavigationStack {
            Form {
                if !purchaseManager.hasPremium {
                    Section {
                        Button(Localization.t("settings.unlockPremium")) {
                            showPaywall = true
                        }
                        .primaryActionButton()
                    }
                }

                Section(Localization.t("noticeTitle")) {
                    Toggle(Localization.t("noticeEnable"), isOn: Binding(
                        get: { notificationService.isRemindersEnabled },
                        set: { requested in
                            Task {
                                let result = await notificationService.setRemindersEnabled(
                                    requested,
                                    legacyTaskIDs: Set(vm.items.map(\.id))
                                )
                                if result == .enabled {
                                    vm.restoreDueReminders()
                                } else if result == .permissionDenied || result == .restricted {
                                    showNotificationSettingsPrompt = true
                                }
                            }
                        }
                    ))

                    LabeledContent(Localization.t("notice.systemStatus")) {
                        Text(systemNotificationText)
                            .foregroundStyle(notificationService.systemAuthorizationStatus == .denied ? Color.red : Color.appMuted)
                    }

                    if notificationService.systemAuthorizationStatus == .denied {
                        Button(Localization.t("notice.openSettings")) {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        }
                        .foregroundStyle(Color.accentBlue)
                    }

                    Text(Localization.t("notice.permissionExplanation"))
                        .font(AppTheme.Typography.caption2)
                        .foregroundStyle(Color.appMuted)
                    .onAppear { refreshNotificationStatus() }

#if DEBUG
                    Button {
                        sendTestNotification()
                    } label: {
                        HStack {
                            Text(Localization.t("settings.testNotification"))
                                .foregroundStyle(Color.accentBlue)
                            Spacer()
                            Text(pendingCountText)
                                .font(AppTheme.Typography.caption)
                                .foregroundStyle(Color.appMuted)
                        }
                    }
#endif
                }

                Section(Localization.t("settings.account")) {
                    LabeledContent(Localization.t("settings.trial")) {
                        Text(trialManager.isTrialActive ? Localization.t("settings.trialDays", trialManager.remainingDays) : Localization.t("settings.trialEnded"))
                            .foregroundStyle(trialManager.isTrialActive ? Color.warning : .red)
                    }

                    LabeledContent(Localization.t("settings.premium")) {
                        Text(purchaseManager.hasPremium ? Localization.t("settings.subscribed") : Localization.t("settings.notSubscribed"))
                            .foregroundStyle(purchaseManager.hasPremium ? Color.success : .red)
                    }
                }

                Section {
                    Picker(Localization.t("settings.language"), selection: $lang.language) {
                        Text(Localization.t("settings.zh")).tag("zh")
                        Text(Localization.t("settings.en")).tag("en")
                    }
                    .pickerStyle(.navigationLink)
                }

                Section(Localization.t("settings.ai")) {
                    Picker(Localization.t("ai.provider"), selection: $aiVM.providerID) {
                        ForEach(aiVM.providers) { provider in
                            Text(provider.name).tag(provider.id)
                        }
                    }
                    .disabled(aiVM.usesManagedQuota)

                    SecureField(Localization.t("ai.key"), text: $aiVM.apiKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityLabel(Localization.t("ai.key"))

                    Picker(Localization.t("ai.model"), selection: $aiVM.modelSelection) {
                        ForEach(aiVM.availableModels) { option in
                            Text(option.displayName).tag(AIModelSelection.preset(option.id))
                        }
                        Text(Localization.t("ai.model.custom")).tag(AIModelSelection.custom)
                    }
                    .pickerStyle(.navigationLink)
                    .disabled(aiVM.usesManagedQuota)

                    if aiVM.usesCustomModel {
                        TextField(Localization.t("ai.customModelPlaceholder"), text: $aiVM.customModel)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .disabled(aiVM.usesManagedQuota)
                            .accessibilityLabel(Localization.t("ai.customModelPlaceholder"))
                    }

                    if aiVM.showsCustomBaseURL {
                        TextField(Localization.t("ai.baseUrl"), text: $aiVM.customBaseURL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)
                            .disabled(aiVM.usesManagedQuota)
                            .accessibilityLabel(Localization.t("ai.baseUrl"))

                        Text(Localization.t("ai.customBaseURLHint"))
                            .font(AppTheme.Typography.caption2)
                            .foregroundStyle(Color.appMuted)
                    } else if !aiVM.usesManagedQuota {
                        Text(Localization.t("ai.modelSelectorHint"))
                            .font(AppTheme.Typography.caption2)
                            .foregroundStyle(Color.appMuted)
                    }

                    Text(aiVM.usesManagedQuota
                        ? Localization.t("ai.managedFixedModel")
                        : Localization.t("ai.keyConfigured"))
                        .font(AppTheme.Typography.caption2)
                        .foregroundStyle(Color.appMuted)
                }

                Section(Localization.t("buddy.settings")) {
                    TextField(Localization.t("buddy.name"), text: $buddyName)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityLabel(Localization.t("buddy.name"))

                    Toggle(Localization.t("buddy.greeting"), isOn: $buddyGreeting)

                    LabeledContent(Localization.t("buddy.directWrite")) {
                        Text(Localization.t("buddy.comingSoon"))
                            .font(AppTheme.Typography.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                Section(Localization.t("settings.obsidian")) {
                    if purchaseManager.canUsePremiumFeature {
                        Button(Localization.t("settings.generateExport")) {
                            exportFileName = ObsidianExporter.fileName()
                            exportedText = vm.exportMarkdown()
                            showExport = true
                        }
                        .primaryActionButton()
                        .disabled(vm.filteredItems.isEmpty)

                        if !exportedText.isEmpty {
                            LabeledContent(Localization.t("settings.fileName")) { Text(exportFileName).foregroundStyle(.secondary) }
                        }
                    } else {
                        Text(Localization.t("settings.exportLocked"))
                            .foregroundStyle(.secondary)
                        Button(Localization.t("settings.unlockExport")) {
                            showPaywall = true
                        }
                        .primaryActionButton()
                    }
                }

                Section(Localization.t("settings.billing")) {
                    Button(Localization.t("settings.restore")) {
                        Task { await purchaseManager.restorePurchases() }
                    }
                    .foregroundStyle(Color.accentBlue)
                }

                Section(Localization.t("settings.benefits")) {
                    Label(Localization.t("settings.benefitAI"), systemImage: purchaseManager.canUse(.aiPlan) ? "checkmark.circle.fill" : "lock")
                        .foregroundStyle(purchaseManager.canUse(.aiPlan) ? Color.success : .secondary)
                    Label(Localization.t("settings.benefitExport"), systemImage: purchaseManager.canUse(.advancedExporter) ? "checkmark.circle.fill" : "lock")
                        .foregroundStyle(purchaseManager.canUse(.advancedExporter) ? Color.success : .secondary)
                    Label(Localization.t("settings.benefitAnalytics"), systemImage: purchaseManager.canUse(.analyticsBoard) ? "checkmark.circle.fill" : "lock")
                        .foregroundStyle(purchaseManager.canUse(.analyticsBoard) ? Color.success : .secondary)
                }

                if let error = purchaseManager.errorMessage {
                    Section(Localization.t("settings.status")) {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
            }
#if DEBUG
            .alert(
                Localization.t(sentTestOK ? "settings.testNotification" : "settings.testFailed"),
                isPresented: $showTestResult
            ) {
                Button(Localization.t("common.ok"), role: .cancel) {}
            } message: {
                Text(sentTestOK
                    ? Localization.t("settings.testSent")
                    : Localization.t("settings.testDenied"))
            }
#endif
            .alert(Localization.t("notice.systemDenied"), isPresented: $showNotificationSettingsPrompt) {
                Button(Localization.t("common.cancel"), role: .cancel) {}
                Button(Localization.t("notice.openSettings")) {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
            } message: {
                Text(Localization.t("notice.permissionExplanation"))
            }
            .sheet(isPresented: $showExport) {
                NavigationStack {
                    VStack(spacing: 12) {
                        Text(exportFileName)
                            .font(.headline)
                            .padding(.top, 8)

                        TextEditor(text: .constant(exportedText))
                            .font(.system(.caption, design: .monospaced))
                            .padding(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.secondary.opacity(0.25))
                            )
                            .padding(.horizontal)

                        ShareLink(
                            Localization.t("settings.shareFile"),
                            item: exportedText
                        )
                        .primaryActionButton()
                        .padding(.horizontal)

                        Button {
                            UIPasteboard.general.string = exportedText
                            copied = true
                            Task {
                                try? await Task.sleep(nanoseconds: 1_200_000_000)
                                copied = false
                            }
                        } label: {
                            HStack {
                                Image(systemName: copied ? "checkmark.circle.fill" : "doc.on.doc")
                                Text(copied ? Localization.t("settings.copied") : Localization.t("settings.copy"))
                            }
                        }
                        .buttonStyle(.bordered)

                        Spacer()
                    }
                    .padding(.top)
                    .navigationTitle(Localization.t("settings.exportTitle"))
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button(Localization.t("common.done")) { showExport = false }
                        }
                    }
                }
            }
            .sheet(isPresented: $showPaywall) {
                PaywallView()
            }
            .navigationTitle(Localization.t("tab.settings"))
            .onAppear {
                exportFileName = ObsidianExporter.fileName()
            }
        }
    }
}
