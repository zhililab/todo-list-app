import SwiftUI

struct MainTabView: View {
    @EnvironmentObject private var vm: TodoViewModel
    @EnvironmentObject private var purchaseManager: PurchaseManager
    @EnvironmentObject private var trialManager: TrialManager
    @EnvironmentObject private var lang: LanguageEnvironment

    @State private var selectedTab = 0
    @State private var showingPaywall = false

    var body: some View {
        let _ = lang.language
        return TabView(selection: $selectedTab) {
            DashboardView()
                .tabItem { Label(Localization.t("tab.today"), systemImage: "calendar.badge.plus") }
                .tag(0)

            TasksView()
                .tabItem { Label(Localization.t("tab.tasks"), systemImage: "checklist") }
                .tag(1)

            SettingsView()
                .tabItem { Label(Localization.t("tab.settings"), systemImage: "gearshape") }
                .tag(2)

            CompanionView()
                .tabItem { Label(Localization.t("tab.companion"), systemImage: "bubble.left.and.bubble.right") }
                .tag(3)
        }
        .onAppear {
            if trialManager.remainingDays == 0 && !purchaseManager.hasPremium {
                showingPaywall = true
            }
        }
        .sheet(isPresented: $showingPaywall) {
            PaywallView()
        }
    }
}
