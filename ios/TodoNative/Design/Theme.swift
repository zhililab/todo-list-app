import SwiftUI
import UIKit

enum AppTheme {
    enum Motion {
        static let press = Animation.easeOut(duration: 0.12)
        static let stateChange = Animation.easeInOut(duration: 0.18)
        static let content = Animation.easeOut(duration: 0.24)
        static let progress = Animation.easeOut(duration: 0.32)
        static let settle = Animation.spring(response: 0.32, dampingFraction: 0.86)

        static func resolved(_ animation: Animation, reduceMotion: Bool) -> Animation? {
            reduceMotion ? nil : animation
        }

        static func resolvedFade(_ animation: Animation, reduceMotion: Bool) -> Animation {
            reduceMotion ? .easeOut(duration: 0.12) : animation
        }
    }

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
        static let title = Font.system(.largeTitle, design: .rounded, weight: .semibold)
        static let headline = Font.system(.title3, design: .rounded, weight: .semibold)
        static let body = Font.system(.body, design: .rounded)
        static let caption = Font.system(.caption, design: .rounded, weight: .medium)
        static let caption2 = Font.system(.caption2, design: .rounded)
    }

    enum Palette {
        static let appBg = adaptive(light: 0xF6F3EE, dark: 0x101311)
        static let appBg2 = adaptive(light: 0xE9F1EC, dark: 0x131A16)
        static let appBgBottom = adaptive(light: 0xF4F4F1, dark: 0x151715)
        static let appCardBg = adaptive(light: 0xFFFFFF, dark: 0x1D211E)
        static let appSidebarBg = adaptive(light: 0xFCFAF8, dark: 0x181B19)
        static let appLine = adaptive(light: 0xEFE4DC, dark: 0x46504A)
        static let appText = adaptive(light: 0x2A2A2A, dark: 0xF2F4F2)
        static let appMuted = adaptive(light: 0x7F7A74, dark: 0xB8C0BA)
        static let brand = adaptive(light: 0xD94F3A, dark: 0xFF7664)
        static let accentSoft = adaptive(light: 0xFFF0EB, dark: 0x45251F)
        static let accentBlue = adaptive(light: 0x3B82F6, dark: 0x76A7FF)
        static let blueSoft = adaptive(light: 0xEEF4FF, dark: 0x172A48)
        static let success = adaptive(light: 0x1F9D68, dark: 0x61D59D)
        static let greenSoft = adaptive(light: 0xEEFAF4, dark: 0x16382B)
        static let warning = adaptive(light: 0xFF8A3D, dark: 0xFFB06B)
        static let ghostText = adaptive(light: 0x645D57, dark: 0xD2D7D3)
        static let chipGreenText = adaptive(light: 0x317255, dark: 0x9DE0BF)
        static let chipGreenBorder = adaptive(light: 0xDCEBE2, dark: 0x356A50)
        static let chipSourceText = adaptive(light: 0x9A6A1F, dark: 0xFFD58A)
        static let chipSourceBg = adaptive(light: 0xFFF4D6, dark: 0x3D2D12)
        static let chipSourceBorder = adaptive(light: 0xEFDCB0, dark: 0x725825)
        static let buddyUserBubble = adaptive(light: 0xFDF1EA, dark: 0x3B241D)
        static let buddyBuddyBubble = adaptive(light: 0xFFFFFF, dark: 0x202522)
        static let buddyBubbleLine = adaptive(light: 0xEFE4DC, dark: 0x46504A)

        private static func adaptive(light: UInt32, dark: UInt32) -> UIColor {
            UIColor { traits in
                UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
            }
        }
    }
}

private extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
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
    static let appBg = Color(uiColor: AppTheme.Palette.appBg)
    static let appBg2 = Color(uiColor: AppTheme.Palette.appBg2)
    static let appBgBottom = Color(uiColor: AppTheme.Palette.appBgBottom)
    static let appCardBg = Color(uiColor: AppTheme.Palette.appCardBg)
    static let appSidebarBg = Color(uiColor: AppTheme.Palette.appSidebarBg)
    static let appLine = Color(uiColor: AppTheme.Palette.appLine)
    static let appText = Color(uiColor: AppTheme.Palette.appText)
    static let appMuted = Color(uiColor: AppTheme.Palette.appMuted)
    static let brand = Color(uiColor: AppTheme.Palette.brand)
    static let accentSoft = Color(uiColor: AppTheme.Palette.accentSoft)
    static let accentBlue = Color(uiColor: AppTheme.Palette.accentBlue)
    static let blueSoft = Color(uiColor: AppTheme.Palette.blueSoft)
    static let success = Color(uiColor: AppTheme.Palette.success)
    static let greenSoft = Color(uiColor: AppTheme.Palette.greenSoft)
    static let warning = Color(uiColor: AppTheme.Palette.warning)
    static let ghostText = Color(uiColor: AppTheme.Palette.ghostText)
    static let chipGreenText = Color(uiColor: AppTheme.Palette.chipGreenText)
    static let chipGreenBorder = Color(uiColor: AppTheme.Palette.chipGreenBorder)
    static let chipSourceText = Color(uiColor: AppTheme.Palette.chipSourceText)
    static let chipSourceBg = Color(uiColor: AppTheme.Palette.chipSourceBg)
    static let chipSourceBorder = Color(uiColor: AppTheme.Palette.chipSourceBorder)
    static let buddyUserBubble = Color(uiColor: AppTheme.Palette.buddyUserBubble)
    static let buddyBuddyBubble = Color(uiColor: AppTheme.Palette.buddyBuddyBubble)
    static let buddyBubbleLine = Color(uiColor: AppTheme.Palette.buddyBubbleLine)
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.brand.opacity(configuration.isPressed ? 0.85 : 1))
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Spacing.radiusSm))
            .shadow(color: Color.brand.opacity(0.3), radius: 8, y: 4)
            .scaleEffect(reduceMotion || !configuration.isPressed ? 1 : 0.98)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(AppTheme.Motion.resolved(AppTheme.Motion.press, reduceMotion: reduceMotion), value: configuration.isPressed)
    }
}

// web .ghost-btn：白底细边框
struct GhostButton: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
            .scaleEffect(reduceMotion || !configuration.isPressed ? 1 : 0.98)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(AppTheme.Motion.resolved(AppTheme.Motion.press, reduceMotion: reduceMotion), value: configuration.isPressed)
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
            .background(Color.appCardBg)
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
