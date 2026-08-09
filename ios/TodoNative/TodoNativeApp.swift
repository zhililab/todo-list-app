import SwiftUI
import SwiftData

@main
struct TodoNativeApp: App {
    private let container: ModelContainer

    @StateObject private var trialManager: TrialManager
    @StateObject private var purchaseManager: PurchaseManager
    @StateObject private var planViewModel: TodoViewModel
    @StateObject private var aiViewModel: AIViewModel
    @StateObject private var languageEnvironment: LanguageEnvironment

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
        let vm = TodoViewModel(modelContainer: container)
        let ai = AIViewModel()
        let lang = LanguageEnvironment()

        _trialManager = StateObject(wrappedValue: trial)
        _purchaseManager = StateObject(wrappedValue: purchase)
        _planViewModel = StateObject(wrappedValue: vm)
        _aiViewModel = StateObject(wrappedValue: ai)
        _languageEnvironment = StateObject(wrappedValue: lang)
    }

    var body: some Scene {
        WindowGroup {
            MainTabView()
                .environmentObject(trialManager)
                .environmentObject(purchaseManager)
                .environmentObject(planViewModel)
                .environmentObject(aiViewModel)
                .environmentObject(languageEnvironment)
                .onAppear {
                    NotificationService.setup()
                    NotificationService.requestAuthorization()
                    Task {
                        await purchaseManager.initialize()
                    }
                }
        }
        .modelContainer(container)
    }
}
