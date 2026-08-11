import SwiftUI

struct AIConsentView: View {
    let route: AIConsentRoute
    let privacyPolicyURL: URL?
    let onDecline: () -> Void
    let onContinue: () -> Void

    private var routeDetailKey: String {
        switch route.kind {
        case .managed: return "ai.consent.managedRouteDetail"
        case .bringYourOwnKey: return "ai.consent.byokRouteDetail"
        }
    }

    private var recipient: String {
        switch route.kind {
        case .managed:
            return Localization.t("ai.consent.managedRecipient", route.recipientName)
        case .bringYourOwnKey:
            return route.recipientName
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
                    Image(systemName: "sparkles.rectangle.stack")
                        .font(.largeTitle)
                        .foregroundStyle(Color.brand)
                        .accessibilityHidden(true)

                    Text(Localization.t("ai.consent.summary"))
                        .font(.body)

                    disclosureSection(
                        title: Localization.t("ai.consent.transmittedTitle"),
                        detail: Localization.t("ai.consent.transmittedContent")
                    )

                    disclosureSection(
                        title: Localization.t("ai.consent.recipientTitle"),
                        detail: "\(Localization.t("ai.consent.recipient", recipient))\n\(Localization.t(routeDetailKey))"
                    )

                    Text(Localization.t("ai.consent.declineDetail"))
                        .font(.body)
                    Text(Localization.t("ai.consent.revokeDetail"))
                        .font(.body)

                    if let privacyPolicyURL {
                        Link(Localization.t("ai.consent.privacy"), destination: privacyPolicyURL)
                            .font(.body)
                            .frame(minHeight: 44)
                            .accessibilityLabel(Localization.t("ai.consent.privacy"))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(AppTheme.Spacing.lg)
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: AppTheme.Spacing.sm) {
                    Button(action: onContinue) {
                        Text(Localization.t("ai.consent.continue"))
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityLabel(Localization.t("ai.consent.continue"))

                    Button(role: .cancel, action: onDecline) {
                        Text(Localization.t("ai.consent.decline"))
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel(Localization.t("ai.consent.decline"))
                }
                .padding(.horizontal, AppTheme.Spacing.lg)
                .padding(.vertical, AppTheme.Spacing.sm)
                .background(.bar)
            }
            .navigationTitle(Localization.t("ai.consent.title"))
            .navigationBarTitleDisplayMode(.inline)
        }
        .interactiveDismissDisabled()
    }

    private func disclosureSection(title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
            Text(title)
                .font(.headline)
            Text(detail)
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}
