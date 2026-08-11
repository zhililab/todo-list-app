import SwiftUI

struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var purchaseManager: PurchaseManager
    @EnvironmentObject private var trialManager: TrialManager
    @EnvironmentObject private var lang: LanguageEnvironment

    @State private var isRefreshingProducts = false
    @State private var purchasingProductIDs: Set<String> = []
    @State private var isRestoring = false

    private let manageSubscriptionsURL = URL(string: "https://apps.apple.com/account/subscriptions")!

    var body: some View {
        let _ = lang.language
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    ForEach(PaywallPresentation.sectionOrder, id: \.self) { section in
                        switch section {
                        case .header: header
                        case .renewalAndCancellation: subscriptionDisclosures
                        case .legalLinks: legalLinks
                        case .products: products
                        case .status: statusMessages
                        case .billingActions: billingActions
                        }
                    }
                    Spacer(minLength: 20)
                }
                .padding(20)
            }
            .navigationTitle(Localization.t("paywall.subscribe"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(Localization.t("paywall.close")) { dismiss() }
                }
            }
        }
        .padding(.top, 6)
    }

    private var header: some View {
        VStack(spacing: 12) {
            Text(Localization.t("paywall.title"))
                .font(.title2.bold())

            Text(trialManager.isTrialActive
                ? Localization.t("paywall.trialLeft", trialManager.remainingDays)
                : Localization.t("paywall.trialEnded"))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if trialManager.isTrialActive {
                Text(Localization.t("paywall.localTrialDisclosure"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Text(Localization.t("paywall.perks"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 6)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var products: some View {
        if purchaseManager.isLoading {
            ProgressView(Localization.t("paywall.loading"))
                .padding(.top, 4)
        } else {
            if purchaseManager.products.isEmpty {
                VStack(spacing: 12) {
                    Text(Localization.t("paywall.noProducts"))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button {
                        isRefreshingProducts = true
                        Task {
                            await purchaseManager.refreshProducts()
                            isRefreshingProducts = false
                        }
                    } label: {
                        actionLabel(
                            Localization.t("paywall.refresh"),
                            isRunning: isRefreshingProducts
                        )
                    }
                    .buttonStyle(.bordered)
                    .disabled(isRefreshingProducts)
                }
            }

            ForEach(purchaseManager.products) { product in
                if let presentation = purchaseManager.subscriptionPresentations[product.id] {
                    Button {
                        purchasingProductIDs.insert(product.id)
                        Task {
                            await purchaseManager.purchase(product)
                            purchasingProductIDs.remove(product.id)
                            if purchaseManager.hasPremium { dismiss() }
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Text(presentation.displayName)
                                    .font(.headline)
                                Spacer()
                                if purchasingProductIDs.contains(product.id) {
                                    ProgressView()
                                }
                            }
                            Text(Localization.t(
                                "paywall.pricePerPeriod",
                                presentation.displayPrice,
                                periodText(presentation.billingPeriod)
                            ))
                            .font(.title3.bold())

                            if let offer = presentation.introductoryOffer {
                                Text(SubscriptionOfferPresentation(offer: offer).localizedDescription)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                    .disabled(PaywallPresentation.isPurchaseDisabled(
                        productID: product.id,
                        activeProductIDs: purchasingProductIDs
                    ))
                    .accessibilityLabel(Localization.t(
                        "paywall.purchaseAccessibility",
                        presentation.displayName,
                        presentation.displayPrice,
                        periodText(presentation.billingPeriod)
                    ))
                }
            }
        }
    }

    @ViewBuilder
    private var statusMessages: some View {
        if let error = purchaseManager.errorMessage {
            Text(error)
                .font(.caption)
                .foregroundStyle(.red)
                .multilineTextAlignment(.center)
                .padding(.top, 4)
                .accessibilityLabel(error)
        }

        switch purchaseManager.registrationStatus {
        case .unavailable:
            Text(Localization.t("purchase.registrationUnavailable"))
                .font(.caption)
                .foregroundStyle(.orange)
                .multilineTextAlignment(.center)
        case .failed:
            Text(Localization.t("purchase.registrationRetry"))
                .font(.caption)
                .foregroundStyle(.orange)
                .multilineTextAlignment(.center)
        case .idle, .registering, .registered:
            EmptyView()
        }
    }

    private var subscriptionDisclosures: some View {
        VStack(spacing: 8) {
            Text(Localization.t("paywall.autoRenewDisclosure"))
            Text(Localization.t("paywall.cancellationDisclosure"))
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
    }

    private var billingActions: some View {
        VStack(spacing: 10) {
            Button {
                isRestoring = true
                Task {
                    await purchaseManager.restorePurchases()
                    isRestoring = false
                }
            } label: {
                actionLabel(Localization.t("settings.restore"), isRunning: isRestoring)
            }
            .buttonStyle(.bordered)
            .disabled(isRestoring)

            Link(Localization.t("settings.manageSubscriptions"), destination: manageSubscriptionsURL)
                .buttonStyle(.bordered)
        }
    }

    private var legalLinks: some View {
        HStack(spacing: 18) {
            if let privacyURL = AppConfiguration().privacyPolicyURL {
                Link(Localization.t("settings.privacy"), destination: privacyURL)
            }
            if let termsURL = AppConfiguration().termsOfUseURL {
                Link(Localization.t("settings.terms"), destination: termsURL)
            }
        }
        .font(.caption)
    }

    private func actionLabel(_ title: String, isRunning: Bool) -> some View {
        HStack(spacing: 8) {
            if isRunning { ProgressView() }
            Text(title)
        }
    }

    private func periodText(_ period: SubscriptionPeriodFacts) -> String {
        SubscriptionOfferPresentation.periodText(period)
    }
}
