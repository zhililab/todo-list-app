import SwiftUI

struct MainTabView: View {
    @EnvironmentObject private var lang: LanguageEnvironment

    @State private var selectedTab = 0

    var body: some View {
        let _ = lang.language
        return TabView(selection: $selectedTab) {
            DashboardView()
                .tabItem { Label(Localization.t("tab.today"), systemImage: "calendar.badge.plus") }
                .tag(0)

            TasksView()
                .tabItem { Label(Localization.t("tab.tasks"), systemImage: "checklist") }
                .tag(1)

            CompanionView()
                .tabItem { Label(Localization.t("tab.companion"), systemImage: "bubble.left.and.bubble.right") }
                .tag(2)

            SettingsView()
                .tabItem { Label(Localization.t("tab.settings"), systemImage: "gearshape") }
                .tag(3)
        }
    }
}
