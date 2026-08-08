import SwiftUI
import UIKit

enum AppTheme {
    enum Spacing {
        static let xs: CGFloat = 6
        static let sm: CGFloat = 10
        static let md: CGFloat = 14
        static let lg: CGFloat = 18
        static let xl: CGFloat = 24
        static let radiusLg: CGFloat = 18
        static let radiusMd: CGFloat = 12
        static let radiusSm: CGFloat = 8
        static let radius: CGFloat = 18
    }

    enum Typography {
        static let title = Font.system(size: 34, weight: .semibold, design: .rounded)
        static let headline = Font.system(size: 20, weight: .semibold, design: .rounded)
        static let body = Font.system(size: 16, weight: .regular, design: .rounded)
        static let caption = Font.system(size: 13, weight: .medium, design: .rounded)
        static let caption2 = Font.system(size: 12, weight: .regular, design: .rounded)
    }
}

extension Color {
    init(hex: UInt32, alpha: Double = 1.0) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255.0,
            green: Double((hex >> 8) & 0xFF) / 255.0,
            blue: Double(hex & 0xFF) / 255.0,
            opacity: alpha
        )
    }
}

// 与 web 端 styles.css :root 配色一致（暖色手帐风）
extension Color {
    static let appBg = Color(hex: 0xF6F3EE)
    static let appBg2 = Color(hex: 0xE9F1EC)
    static let appBgBottom = Color(hex: 0xF4F4F1)
    static let appCardBg = Color.white
    static let appSidebarBg = Color(hex: 0xFCFAF8)
    static let appLine = Color(hex: 0xEFE4DC)
    static let appText = Color(hex: 0x2A2A2A)
    static let appMuted = Color(hex: 0x7F7A74)
    static let brand = Color(hex: 0xD94F3A)
    static let accentSoft = Color(hex: 0xFFF0EB)
    static let accentBlue = Color(hex: 0x3B82F6)
    static let blueSoft = Color(hex: 0xEEF4FF)
    static let success = Color(hex: 0x1F9D68)
    static let greenSoft = Color(hex: 0xEEFAF4)
    static let warning = Color(hex: 0xFF8A3D)
    static let ghostText = Color(hex: 0x645D57)
    static let chipGreenText = Color(hex: 0x317255)
    static let chipGreenBorder = Color(hex: 0xDCEBE2)
    static let chipSourceText = Color(hex: 0x9A6A1F)
    static let chipSourceBg = Color(hex: 0xFFF4D6)
    static let chipSourceBorder = Color(hex: 0xEFDCB0)
}

// web .app-shell 背景：渐变 + 白面板
struct AppBgModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(
                LinearGradient(
                    colors: [.appBg2, .appBg, .appBgBottom],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
            )
    }
}

// web .panel：白底 + 1px 边框 + 柔和阴影 + 18px 圆角
struct AppCardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(AppTheme.Spacing.md)
            .background(
                Color.appCardBg
                    .overlay(
                        RoundedRectangle(cornerRadius: AppTheme.Spacing.radiusLg)
                            .stroke(Color.appLine, lineWidth: 1)
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Spacing.radiusLg))
            .shadow(color: Color(red: 68/255, green: 77/255, blue: 68/255).opacity(0.11), radius: 16, x: 0, y: 8)
    }
}

// web #add-task / #ai-breakdown：珊瑚红主按钮
struct PrimaryActionButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.brand.opacity(configuration.isPressed ? 0.7 : 1))
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Spacing.radiusSm))
            .shadow(color: Color.brand.opacity(0.3), radius: 8, y: 4)
    }
}

// web .ghost-btn：白底细边框
struct GhostButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.medium))
            .foregroundStyle(Color.ghostText)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(Color.appCardBg)
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.Spacing.radiusSm)
                    .stroke(Color.appLine, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Spacing.radiusSm))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

// web .task-chips span：浅绿胶囊
struct TaskChipStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.system(size: 12, weight: .medium, design: .rounded))
            .foregroundStyle(Color.chipGreenText)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(
                Capsule().fill(Color.greenSoft)
                    .overlay(Capsule().stroke(Color.chipGreenBorder, lineWidth: 1))
            )
    }
}

// web .task-item：白底分隔行，无卡片圆角
struct TaskRowStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(AppTheme.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white)
            .overlay(
                Rectangle()
                    .fill(Color.appLine)
                    .frame(height: 1),
                alignment: .bottom
            )
    }
}

extension View {
    func appBg() -> some View {
        modifier(AppBgModifier())
    }

    func appCard() -> some View {
        modifier(AppCardStyle())
    }

    func primaryActionButton() -> some View {
        buttonStyle(PrimaryActionButton())
    }

    func ghostButton() -> some View {
        buttonStyle(GhostButton())
    }

    func taskChip() -> some View {
        modifier(TaskChipStyle())
    }

    func taskRow() -> some View {
        modifier(TaskRowStyle())
    }
}
