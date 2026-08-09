import Foundation

@MainActor
final class AIViewModel: ObservableObject {
    @Published var apiKey: String {
        didSet { OpenAIService.saveAPIKey(apiKey) }
    }
    @Published var providerID: String {
        didSet {
            guard !isLoadingProviderConfiguration else { return }
            OpenAIService.saveProviderID(providerID)
            loadProviderConfiguration()
        }
    }
    @Published var modelSelection: AIModelSelection {
        didSet {
            guard !isLoadingProviderConfiguration else { return }
            OpenAIService.saveModelSelection(modelSelection, providerID: providerID)
        }
    }
    @Published var customBaseURL: String {
        didSet {
            guard !isLoadingProviderConfiguration else { return }
            OpenAIService.saveCustomBaseURL(customBaseURL, providerID: providerID)
        }
    }
    @Published var customModel: String {
        didSet {
            guard !isLoadingProviderConfiguration else { return }
            OpenAIService.saveCustomModel(customModel, providerID: providerID)
        }
    }
    @Published var isBusy = false
    @Published var outputText = ""
    @Published var suggestedTasks: [String] = []
    @Published var statusMessage = ""
    @Published var isTodayPlanOutput = false
    @Published var quotaExceeded = false

    private var isLoadingProviderConfiguration = true

    var providers: [AIProvider] { AIProvider.registry }

    var importHandler: (([String]) -> Void)?

    init() {
        apiKey = OpenAIService.apiKey()
        let storedProviderID = OpenAIService.providerID()
        providerID = storedProviderID
        modelSelection = OpenAIService.modelSelection(providerID: storedProviderID)
        customBaseURL = OpenAIService.customBaseURL(providerID: storedProviderID)
        customModel = OpenAIService.customModel(providerID: storedProviderID)
        isLoadingProviderConfiguration = false
    }

    var activeProvider: AIProvider {
        AIProvider.provider(id: providerID)
    }

    var availableModels: [AIModelOption] { activeProvider.models }

    var usesCustomModel: Bool {
        if case .custom = modelSelection { return true }
        return false
    }

    var showsCustomBaseURL: Bool { providerID == "custom" }

    var usesManagedQuota: Bool { apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var effectiveBaseURL: String {
        customBaseURL.isEmpty ? activeProvider.baseURL : customBaseURL
    }

    var effectiveModel: String {
        switch modelSelection {
        case .custom:
            return customModel.isEmpty ? activeProvider.defaultModel : customModel
        case .preset(let id):
            return activeProvider.models.contains { $0.id == id } ? id : activeProvider.defaultModel
        }
    }

    private func loadProviderConfiguration() {
        isLoadingProviderConfiguration = true
        modelSelection = OpenAIService.modelSelection(providerID: providerID)
        customBaseURL = OpenAIService.customBaseURL(providerID: providerID)
        customModel = OpenAIService.customModel(providerID: providerID)
        isLoadingProviderConfiguration = false
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
