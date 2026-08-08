import Foundation

@MainActor
final class AIViewModel: ObservableObject {
    @Published var apiKey: String {
        didSet { OpenAIService.saveAPIKey(apiKey) }
    }
    @Published var providerID: String {
        didSet { OpenAIService.saveProviderID(providerID) }
    }
    @Published var customBaseURL: String {
        didSet { OpenAIService.saveCustomBaseURL(customBaseURL) }
    }
    @Published var customModel: String {
        didSet { OpenAIService.saveCustomModel(customModel) }
    }
    @Published var isBusy = false
    @Published var outputText = ""
    @Published var suggestedTasks: [String] = []
    @Published var statusMessage = ""
    @Published var isTodayPlanOutput = false

    var providers: [AIProvider] { AIProvider.registry }

    var importHandler: (([String]) -> Void)?

    init() {
        apiKey = OpenAIService.apiKey()
        providerID = OpenAIService.providerID()
        customBaseURL = OpenAIService.customBaseURL()
        customModel = OpenAIService.customModel()
    }

    var activeProvider: AIProvider {
        AIProvider.provider(id: providerID)
    }

    var effectiveBaseURL: String {
        customBaseURL.isEmpty ? activeProvider.baseURL : customBaseURL
    }

    var effectiveModel: String {
        customModel.isEmpty ? activeProvider.defaultModel : customModel
    }

    func runBreakdown(goal: String, items: [TodoItem] = []) {
        let trimmed = goal.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            statusMessage = Localization.t("ai.status.noGoal")
            return
        }
        isTodayPlanOutput = false
        setBusy(remoteStatus: Localization.t("ai.status.breakdownBusy"), localStatus: Localization.t("ai.status.breakdownLocal"))
        Task {
            let text = await AIService.breakdown(goal: trimmed, items: items)
            outputText = text
            suggestedTasks = AIService.extractTasks(from: text)
            statusMessage = suggestedTasks.isEmpty ? Localization.t("ai.status.saved") : Localization.t("ai.status.breakdownResult", suggestedTasks.count)
            isBusy = false
        }
    }

    func runSummary(items: [TodoItem], health: Int) {
        isTodayPlanOutput = false
        setBusy(remoteStatus: Localization.t("ai.status.summaryBusy"), localStatus: Localization.t("ai.status.summaryLocal"))
        Task {
            let text = await AIService.summary(items: items, health: health)
            outputText = text
            suggestedTasks = []
            statusMessage = Localization.t("ai.status.summaryDone")
            isBusy = false
        }
    }

    func runTodayPlan(items: [TodoItem]) {
        isTodayPlanOutput = true
        setBusy(remoteStatus: Localization.t("ai.status.planBusy"), localStatus: Localization.t("ai.status.planLocal"))
        Task {
            let text = await AIService.todayPlan(items: items)
            outputText = text
            suggestedTasks = []
            statusMessage = Localization.t("ai.status.planDone")
            isBusy = false
        }
    }

    func importSuggestedTasks() {
        guard !suggestedTasks.isEmpty else {
            statusMessage = Localization.t("ai.status.noImport")
            return
        }
        importHandler?(suggestedTasks)
        suggestedTasks = []
        statusMessage = Localization.t("ai.status.imported")
    }

    func clearTodayPlanOutput() {
        isTodayPlanOutput = false
        outputText = ""
    }

    private func setBusy(remoteStatus: String, localStatus: String) {
        isBusy = true
        statusMessage = apiKey.isEmpty ? localStatus : remoteStatus
    }
}
