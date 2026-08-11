import Foundation
import StoreKit

enum ProRegistrationStatus: Equatable {
    case idle
    case registering
    case registered
    case unavailable(ManagedAIUnavailableReason)
    case failed
}

struct ProRegistrationPresentation: Equatable {
    let messageKey: String
    let canRetry: Bool

    init?(status: ProRegistrationStatus) {
        switch status {
        case .unavailable:
            messageKey = "purchase.registrationUnavailable"
            canRetry = true
        case .failed:
            messageKey = "purchase.registrationRetry"
            canRetry = true
        case .idle, .registering, .registered:
            return nil
        }
    }
}

@MainActor
final class PurchaseManager: ObservableObject {
    @Published var products: [Product] = []
    @Published private(set) var subscriptionPresentations: [String: SubscriptionPresentation] = [:]
    @Published var hasPremium = false
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published private(set) var registrationStatus: ProRegistrationStatus = .idle

    private let trialManager: TrialManager
    private let appConfiguration: AppConfiguration
    private let registrationAvailability: @MainActor () -> ManagedAIAvailability
    private let registerPro: @MainActor (String) async throws -> Void
    private var monitorTask: Task<Void, Never>?

    static let approvedProductIDs: Set<String> = [
        "com.zhili.todo.premium.monthly",
        "com.zhili.todo.premium.yearly"
    ]

    static func shouldProcessTransaction(productID: String) -> Bool {
        approvedProductIDs.contains(productID)
    }

    init(
        trialManager: TrialManager,
        appConfiguration: AppConfiguration = AppConfiguration(),
        registrationAvailability: @escaping @MainActor () -> ManagedAIAvailability = {
            QuotaClient.managedServiceAvailability
        },
        registerPro: @escaping @MainActor (String) async throws -> Void = { transactionJWS in
            try await QuotaClient.registerPro(transactionJwt: transactionJWS)
        }
    ) {
        self.trialManager = trialManager
        self.appConfiguration = appConfiguration
        self.registrationAvailability = registrationAvailability
        self.registerPro = registerPro
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
            let productList = try await Product.products(for: Self.approvedProductIDs)
            let sortedProducts = productList.sorted { $0.price < $1.price }
            var presentations: [String: SubscriptionPresentation] = [:]
            for product in sortedProducts {
                let isEligible = await product.subscription?.isEligibleForIntroOffer ?? false
                if let presentation = SubscriptionPresentation(
                    product: product,
                    isEligibleForIntroductoryOffer: isEligible,
                    configuration: appConfiguration
                ) {
                    presentations[product.id] = presentation
                }
            }
            products = sortedProducts
            subscriptionPresentations = presentations
        } catch {
            self.errorMessage = Localization.t("purchase.fetchFailed", error.localizedDescription)
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
                    await updateEntitlements(shouldRegisterTransactions: false)
                    await registerVerifiedTransaction(jwsRepresentation: result.jwsRepresentation)
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

    func updateEntitlements(shouldRegisterTransactions: Bool = true) async {
        hasPremium = false

        for await result in Transaction.currentEntitlements {
            guard case let .verified(transaction) = result else { continue }
            let productID = transaction.productID
            guard Self.shouldProcessTransaction(productID: productID) else {
                continue
            }
            if transaction.revocationDate == nil {
                if let exp = transaction.expirationDate {
                    if exp > Date() {
                        hasPremium = true
                        if shouldRegisterTransactions {
                            await registerVerifiedTransaction(jwsRepresentation: result.jwsRepresentation)
                        }
                    }
                } else {
                    // Non-expiring entitlement (shouldn't happen for auto-renewable subscriptions, but safe guard)
                    hasPremium = true
                    if shouldRegisterTransactions {
                        await registerVerifiedTransaction(jwsRepresentation: result.jwsRepresentation)
                    }
                }
            }
        }

        trialManager.refreshTrialState()
    }

    func registerVerifiedTransaction(jwsRepresentation: String) async {
        switch registrationAvailability() {
        case .unavailable(let reason):
            registrationStatus = .unavailable(reason)
        case .available:
            registrationStatus = .registering
            do {
                try await registerPro(jwsRepresentation)
                registrationStatus = .registered
            } catch {
                registrationStatus = .failed
            }
        }
    }

    private func observeTransactionUpdates() {
        monitorTask?.cancel()
        monitorTask = Task { [weak self] in
            for await result in Transaction.updates {
                guard let self else { return }
                if case let .verified(transaction) = result {
                    guard Self.shouldProcessTransaction(productID: transaction.productID) else {
                        continue
                    }
                    await transaction.finish()
                    await self.updateEntitlements(shouldRegisterTransactions: false)
                    await self.registerVerifiedTransaction(jwsRepresentation: result.jwsRepresentation)
                }
            }
        }
    }

    deinit {
        monitorTask?.cancel()
    }
}
