import SwiftUI

struct FeatureGateBanner: View {
    @EnvironmentObject private var lang: LanguageEnvironment

    let isEnabled: Bool
    let title: String
    let action: () -> Void

    var body: some View {
        let _ = lang.language
        if isEnabled {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 10) {
                Text(title)
                    .font(AppTheme.Typography.headline)
                    .foregroundStyle(.white)

                Text(Localization.t("banner.freeDesc"))
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(.white.opacity(0.9))

                Button(Localization.t("banner.unlockNow")) {
                    action()
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.brand)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.Spacing.radiusSm))
            }
            .padding(AppTheme.Spacing.md)
            .background(
                LinearGradient(
                    colors: [Color.warning, Color.brand.opacity(0.95)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Spacing.radiusLg))
            .shadow(color: Color.brand.opacity(0.25), radius: 10, y: 6)
        }
    }
}
