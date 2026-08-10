import UIKit
import XCTest

@testable import TodoNative

final class ThemeTests: XCTestCase {
    private struct RGBA: Equatable {
        let red: CGFloat
        let green: CGFloat
        let blue: CGFloat
        let alpha: CGFloat
    }

    private let light = UITraitCollection(userInterfaceStyle: .light)
    private let dark = UITraitCollection(userInterfaceStyle: .dark)

    func testCoreSemanticPaletteResolvesDifferentlyInDarkMode() {
        let colors: [(String, UIColor)] = [
            ("appBg", AppTheme.Palette.appBg),
            ("card", AppTheme.Palette.appCardBg),
            ("text", AppTheme.Palette.appText),
            ("muted", AppTheme.Palette.appMuted),
            ("line", AppTheme.Palette.appLine),
            ("accentSoft", AppTheme.Palette.accentSoft),
            ("blueSoft", AppTheme.Palette.blueSoft),
            ("greenSoft", AppTheme.Palette.greenSoft),
            ("chipText", AppTheme.Palette.chipGreenText),
            ("chipBackground", AppTheme.Palette.chipSourceBg),
            ("userBubble", AppTheme.Palette.buddyUserBubble),
            ("buddyBubble", AppTheme.Palette.buddyBuddyBubble)
        ]

        for (name, color) in colors {
            XCTAssertNotEqual(
                rgba(color.resolvedColor(with: light)),
                rgba(color.resolvedColor(with: dark)),
                "\(name) must adapt to interface style"
            )
        }
    }

    func testDarkBackgroundCardTextAndInputPathMeetContrastTargets() {
        let background = AppTheme.Palette.appBg.resolvedColor(with: dark)
        let card = AppTheme.Palette.appCardBg.resolvedColor(with: dark)
        let text = AppTheme.Palette.appText.resolvedColor(with: dark)
        let muted = AppTheme.Palette.appMuted.resolvedColor(with: dark)
        let line = AppTheme.Palette.appLine.resolvedColor(with: dark)

        XCTAssertGreaterThanOrEqual(contrast(text, background), 7)
        XCTAssertGreaterThanOrEqual(contrast(text, card), 7)
        XCTAssertGreaterThanOrEqual(contrast(muted, card), 4.5)
        XCTAssertGreaterThanOrEqual(contrast(line, card), 1.3)

        // AIWorkbench input uses appBg as its field surface and appText as explicit text color.
        XCTAssertGreaterThanOrEqual(contrast(text, background), 7)
    }

    func testDarkChipAndBubbleSurfacesKeepReadableForegrounds() {
        let chipText = AppTheme.Palette.chipGreenText.resolvedColor(with: dark)
        let chipBackground = AppTheme.Palette.greenSoft.resolvedColor(with: dark)
        let sourceText = AppTheme.Palette.chipSourceText.resolvedColor(with: dark)
        let sourceBackground = AppTheme.Palette.chipSourceBg.resolvedColor(with: dark)
        let text = AppTheme.Palette.appText.resolvedColor(with: dark)
        let userBubble = AppTheme.Palette.buddyUserBubble.resolvedColor(with: dark)
        let buddyBubble = AppTheme.Palette.buddyBuddyBubble.resolvedColor(with: dark)

        XCTAssertGreaterThanOrEqual(contrast(chipText, chipBackground), 4.5)
        XCTAssertGreaterThanOrEqual(contrast(sourceText, sourceBackground), 4.5)
        XCTAssertGreaterThanOrEqual(contrast(text, userBubble), 7)
        XCTAssertGreaterThanOrEqual(contrast(text, buddyBubble), 7)
    }

    func testTaskSurfacesUseSemanticThemeColors() throws {
        let testsDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let sourceDirectory = testsDirectory
            .deletingLastPathComponent()
            .appendingPathComponent("TodoNative")
        let sources = [
            sourceDirectory.appendingPathComponent("Views/TasksView.swift"),
            sourceDirectory.appendingPathComponent("Components/TodoCardView.swift")
        ]
        let forbiddenLightOnlyTokens = [
            ".background(Color.white)",
            "Color(hex: 0xFFFDFB)",
            "active ? Color.accentBlue : Color.white",
            "Color(hex: 0x8E8177)",
            "Color(hex: 0x6A635E)",
            "Color(hex: 0x32302D)",
            "Color(hex: 0x8E8883)"
        ]

        for source in sources {
            let contents = try String(contentsOf: source, encoding: .utf8)
            for token in forbiddenLightOnlyTokens {
                XCTAssertFalse(
                    contents.contains(token),
                    "\(source.lastPathComponent) must use semantic dark-mode-aware colors instead of \(token)"
                )
            }
        }
    }

    private func contrast(_ first: UIColor, _ second: UIColor) -> CGFloat {
        let firstLuminance = luminance(first)
        let secondLuminance = luminance(second)
        return (max(firstLuminance, secondLuminance) + 0.05)
            / (min(firstLuminance, secondLuminance) + 0.05)
    }

    private func luminance(_ color: UIColor) -> CGFloat {
        let components = rgba(color)
        func linear(_ component: CGFloat) -> CGFloat {
            component <= 0.03928
                ? component / 12.92
                : pow((component + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(components.red)
            + 0.7152 * linear(components.green)
            + 0.0722 * linear(components.blue)
    }

    private func rgba(_ color: UIColor) -> RGBA {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        XCTAssertTrue(color.getRed(&red, green: &green, blue: &blue, alpha: &alpha))
        return RGBA(red: red, green: green, blue: blue, alpha: alpha)
    }
}
