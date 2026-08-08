import Foundation
import StoreKit

@MainActor
final class PurchaseManager: ObservableObject {
    @Published var products: [Product] = []
    @Published var hasPremium = false
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let trialManager: TrialManager
    private var monitorTask: Task<Void, Never>?

    // 你在 App Store Connect 里创建的 product ids
    private let productIDs: Set<String> = [
        "com.zhili.todo.premium.monthly",
        "com.zhili.todo.premium.yearly"
    ]

    init(trialManager: TrialManager) {
        self.trialManager = trialManager
    }

    func initialize() async {
        isLoading = true
        await refreshProducts()
        await updateEntitlements()
        observeTransactionUpdates()
        isLoading = false
    }

    var canUsePremiumFeature: Bool {
        return hasPremium || trialManager.isTrialActive
    }

    func canUse(_ feature: PremiumFeature) -> Bool {
        switch feature {
        case .aiPlan, .advancedExporter, .taskTemplate, .analyticsBoard, .themePack:
            return canUsePremiumFeature
        }
    }

    func refreshProducts() async {
        errorMessage = nil
        do {
            let productList = try await Product.products(for: productIDs)
            self.products = productList.sorted { $0.price < $1.price }
        } catch {
            self.errorMessage = Localization.t("purchase.fetchFailed", error.localizedDescription)
            print(error.localizedDescription)
        }
    }

    func purchase(_ product: Product) async {
        errorMessage = nil
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let result):
                switch result {
                case .verified(let transaction):
                    await transaction.finish()
                    await updateEntitlements()
                    errorMessage = Localization.t("purchase.success")
                case .unverified(let transaction, _):
                    print("Purchase not verified: \(transaction.productID)")
                    errorMessage = Localization.t("purchase.verifyFailed")
                }
            case .userCancelled:
                errorMessage = Localization.t("purchase.cancelled")
            case .pending:
                errorMessage = Localization.t("purchase.pending")
            default:
                break
            }
        } catch {
            errorMessage = Localization.t("purchase.failed", error.localizedDescription)
        }
    }

    func restorePurchases() async {
        errorMessage = nil
        do {
            try await AppStore.sync()
            await updateEntitlements()
        } catch {
            errorMessage = Localization.t("purchase.restoreFailed", error.localizedDescription)
        }
    }

    func refreshEntitlements() async {
        await updateEntitlements()
    }

    func updateEntitlements() async {
        hasPremium = false

        for await result in Transaction.currentEntitlements {
            guard case let .verified(transaction) = result else { continue }
            let productID = transaction.productID
            guard productIDs.contains(productID) else {
                continue
            }
            if transaction.revocationDate == nil {
                if let exp = transaction.expirationDate {
                    if exp > Date() {
                        hasPremium = true
                        break
                    }
                } else {
                    // Non-expiring entitlement (shouldn't happen for auto-renewable subscriptions, but safe guard)
                    hasPremium = true
                    break
                }
            }
        }

        trialManager.refreshTrialState()
    }

    private func observeTransactionUpdates() {
        monitorTask?.cancel()
        monitorTask = Task { [weak self] in
            for await result in Transaction.updates {
                guard let self else { return }
                if case let .verified(transaction) = result {
                    await transaction.finish()
                    await self.updateEntitlements()
                }
            }
        }
    }

    deinit {
        monitorTask?.cancel()
    }
}
