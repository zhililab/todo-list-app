import SwiftUI
import SwiftData

@main
struct TodoNativeApp: App {
    @Environment(\.scenePhase) private var scenePhase
    private let container: ModelContainer

    @StateObject private var trialManager: TrialManager
    @StateObject private var purchaseManager: PurchaseManager
    @StateObject private var planViewModel: TodoViewModel
    @StateObject private var aiViewModel: AIViewModel
    @StateObject private var languageEnvironment: LanguageEnvironment
    @StateObject private var notificationService: NotificationService

    init() {
        do {
            container = try ModelContainer(
                for: TodoItem.self,
                configurations: ModelConfiguration(schema: Schema([TodoItem.self]))
            )
        } catch {
            fatalError("Failed to initialize model container: \(error)")
        }

        let trial = TrialManager()
        let purchase = PurchaseManager(trialManager: trial)
        let notifications = NotificationService()
        let vm = TodoViewModel(modelContainer: container, reminderScheduler: notifications)
        let ai = AIViewModel()
        let lang = LanguageEnvironment()

        _trialManager = StateObject(wrappedValue: trial)
        _purchaseManager = StateObject(wrappedValue: purchase)
        _planViewModel = StateObject(wrappedValue: vm)
        _aiViewModel = StateObject(wrappedValue: ai)
        _languageEnvironment = StateObject(wrappedValue: lang)
        _notificationService = StateObject(wrappedValue: notifications)
    }

    var body: some Scene {
        WindowGroup {
            MainTabView()
                .environmentObject(trialManager)
                .environmentObject(purchaseManager)
                .environmentObject(planViewModel)
                .environmentObject(aiViewModel)
                .environmentObject(languageEnvironment)
                .environmentObject(notificationService)
                .onAppear {
                    NotificationService.setup()
                    Task {
                        await notificationService.refresh()
                        if notificationService.isRemindersEnabled {
                            planViewModel.restoreDueReminders()
                        }
                        await purchaseManager.initialize()
                    }
                }
                .onChange(of: scenePhase) {
                    guard scenePhase == .active else { return }
                    Task {
                        await notificationService.refresh()
                        if notificationService.isRemindersEnabled {
                            planViewModel.restoreDueReminders()
                        }
                    }
                }
        }
        .modelContainer(container)
    }
}
