import SwiftUI
import UIKit
import UserNotifications

struct SettingsView: View {
    @EnvironmentObject private var trialManager: TrialManager
    @EnvironmentObject private var purchaseManager: PurchaseManager
    @EnvironmentObject private var vm: TodoViewModel
    @EnvironmentObject private var aiVM: AIViewModel
    @EnvironmentObject private var lang: LanguageEnvironment

    @State private var exportedText = ""
    @State private var exportFileName = "todo-list-app.md"
    @State private var showPaywall = false
    @State private var showExport = false
    @State private var copied = false
    @State private var notificationStatus: UNAuthorizationStatus = .notDetermined
    @AppStorage("companion_name") private var buddyName = ""
    @AppStorage("companion_greeting_enabled") private var buddyGreeting = true

    private var noticeText: String {
        switch notificationStatus {
        case .authorized, .ephemeral, .provisional:
            return Localization.t("noticeEnabled")
        case .denied:
            return Localization.t("noticeDenied")
        default:
            return Localization.t("noticeEnable")
        }
    }

    private var noticeIcon: String {
        switch notificationStatus {
        case .authorized, .ephemeral, .provisional:
            return "bell.badge.fill"
        case .denied:
            return "bell.slash.fill"
        default:
            return "bell.badge"
        }
    }

    private func refreshNotificationStatus() {
        NotificationService.authorizationStatus { status in
            guard let status else { return }
            DispatchQueue.main.async {
                notificationStatus = status
            }
        }
    }

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
                    Button {
                        switch notificationStatus {
                        case .denied:
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        case .authorized, .ephemeral, .provisional:
                            refreshNotificationStatus()
                        default:
                            NotificationService.requestAuthorization { _ in
                                refreshNotificationStatus()
                            }
                        }
                    } label: {
                        HStack {
                            Text(noticeText)
                                .foregroundStyle(Color.accentBlue)
                            Spacer()
                            Image(systemName: noticeIcon)
                                .foregroundStyle(notificationStatus == .denied ? Color.red : (notificationStatus == .authorized || notificationStatus == .ephemeral || notificationStatus == .provisional ? Color.success : Color.appMuted))
                        }
                    }
                    .onAppear { refreshNotificationStatus() }
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

                    SecureField(Localization.t("ai.key"), text: $aiVM.apiKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityLabel(Localization.t("ai.key"))

                    TextField(Localization.t("ai.baseUrl"), text: $aiVM.customBaseURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .accessibilityLabel(Localization.t("ai.baseUrl"))

                    TextField(Localization.t("ai.model"), text: $aiVM.customModel)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityLabel(Localization.t("ai.model"))

                    Text(aiVM.apiKey.isEmpty
                        ? Localization.t("ai.keyNoConfig")
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
