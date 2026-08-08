import SwiftUI

struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var purchaseManager: PurchaseManager
    @EnvironmentObject private var trialManager: TrialManager
    @EnvironmentObject private var lang: LanguageEnvironment
    @State private var loading = false

    var body: some View {
        let _ = lang.language
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    VStack(spacing: 10) {
                        Text(Localization.t("paywall.title"))
                            .font(.title2.bold())

                        Text(trialManager.isTrialActive
                            ? Localization.t("paywall.trialLeft", trialManager.remainingDays)
                            : Localization.t("paywall.trialEnded"))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)

                    Text(Localization.t("paywall.perks"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 6)

                    if loading || purchaseManager.isLoading {
                        ProgressView(Localization.t("paywall.loading"))
                            .padding(.top, 4)
                    } else {
                        if purchaseManager.products.isEmpty {
                            VStack(spacing: 12) {
                                Text(Localization.t("paywall.noProducts"))
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                                Button(Localization.t("paywall.refresh")) {
                                    loading = true
                                    Task {
                                        await purchaseManager.refreshProducts()
                                        loading = false
                                    }
                                }
                                .buttonStyle(.bordered)
                            }
                        }

                        ForEach(purchaseManager.products) { product in
                            Button {
                                Task {
                                    await purchaseManager.purchase(product)
                                    if purchaseManager.hasPremium {
                                        dismiss()
                                    }
                                }
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(product.displayName)
                                        .font(.headline)
                                    Text(product.displayPrice)
                                        .font(.title3.bold())
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding()
                                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    if let error = purchaseManager.errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                            .padding(.top, 4)
                    }

                    if trialManager.remainingDays > 0 && !purchaseManager.hasPremium {
                        Text(Localization.t("paywall.manage"))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }

                    Button(Localization.t("settings.restore")) {
                        Task {
                            await purchaseManager.restorePurchases()
                        }
                    }
                    .buttonStyle(.bordered)

                    Spacer(minLength: 20)
                }
                .padding(20)
            }
            .navigationTitle(Localization.t("paywall.subscribe"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(Localization.t("paywall.close")) {
                        dismiss()
                    }
                }
            }
        }
        .padding(.top, 6)
    }
}
