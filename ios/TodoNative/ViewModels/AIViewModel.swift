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
    @Published var quotaExceeded = false

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
            do {
                let text = try await AIService.breakdown(goal: trimmed, items: items)
                outputText = text
                suggestedTasks = AIService.extractTasks(from: text)
                statusMessage = suggestedTasks.isEmpty ? Localization.t("ai.status.saved") : Localization.t("ai.status.breakdownResult", suggestedTasks.count)
            } catch {
                handleAIError(error)
            }
            isBusy = false
        }
    }

    func runSummary(items: [TodoItem], health: Int) {
        isTodayPlanOutput = false
        setBusy(remoteStatus: Localization.t("ai.status.summaryBusy"), localStatus: Localization.t("ai.status.summaryLocal"))
        Task {
            do {
                let text = try await AIService.summary(items: items, health: health)
                outputText = text
                suggestedTasks = []
                statusMessage = Localization.t("ai.status.summaryDone")
            } catch {
                handleAIError(error)
            }
            isBusy = false
        }
    }

    func runTodayPlan(items: [TodoItem]) {
        isTodayPlanOutput = true
        setBusy(remoteStatus: Localization.t("ai.status.planBusy"), localStatus: Localization.t("ai.status.planLocal"))
        Task {
            do {
                let text = try await AIService.todayPlan(items: items)
                outputText = text
                suggestedTasks = []
                statusMessage = Localization.t("ai.status.planDone")
            } catch {
                handleAIError(error)
            }
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

    private func handleAIError(_ error: Error) {
        if let quota = error as? QuotaError, case .quotaExceeded(let kind) = quota {
            statusMessage = kind == "daily"
                ? Localization.t("quota.exceeded.daily")
                : Localization.t("quota.exceeded.free")
            quotaExceeded = true
        } else {
            statusMessage = (error as? LocalizedError)?.errorDescription
                ?? Localization.t("ai.error.empty")
        }
    }
}
