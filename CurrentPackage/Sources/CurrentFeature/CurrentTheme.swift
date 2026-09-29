import AppKit
import SwiftUI

enum CurrentTheme {
    static let pageBackgroundColor = NSColor.currentAdaptive(light: 0xFFFFFF, dark: 0x1E1E20)
    static let appSurfaceColor = NSColor.currentAdaptive(light: 0xF5F5F6, dark: 0x262628)
    static let chromeBackgroundColor = appSurfaceColor
    static let editorBackgroundColor = pageBackgroundColor
    static let primaryTextColor = NSColor.currentAdaptive(light: 0x242426, dark: 0xF1F1F3)
    static let secondaryTextColor = NSColor.currentAdaptive(light: 0x67676B, dark: 0xB0B0B5)
    static let mutedTextColor = NSColor.currentAdaptive(light: 0x737378, dark: 0xA1A1A8)
    static let dividerColor = NSColor.currentAdaptive(light: 0xE6E6E9, dark: 0x3A3A3E)
    static let softDividerColor = dividerColor.withAlphaComponent(0.65)
    static let fieldBackgroundColor = NSColor.currentAdaptive(light: 0xEBEBEE, dark: 0x323236)
    static let fieldBackgroundActiveColor = NSColor.currentAdaptive(light: 0xE1E1E6, dark: 0x3C3C42)
    static let accentColor = NSColor.currentAdaptive(light: 0x456F98, dark: 0x97B8D9)
    static let accentSoftColor = NSColor.currentAdaptive(light: 0xECF4FC, dark: 0x263747)
    static let inlineCodeBackgroundColor = NSColor.currentAdaptive(light: 0xF2F2F4, dark: 0x2C2C30)
    static let dayDividerColor = dividerColor

    static let pageBackground = Color(nsColor: pageBackgroundColor)
    static let appSurface = Color(nsColor: appSurfaceColor)
    static let chromeBackground = Color(nsColor: chromeBackgroundColor)
    static let editorBackground = editorBackgroundColor
    static let primaryText = Color(nsColor: primaryTextColor)
    static let secondaryText = Color(nsColor: secondaryTextColor)
    static let mutedText = Color(nsColor: mutedTextColor)
    static let divider = Color(nsColor: dividerColor)
    static let softDivider = Color(nsColor: softDividerColor)
    static let fieldBackground = Color(nsColor: fieldBackgroundColor)
    static let fieldBackgroundActive = Color(nsColor: fieldBackgroundActiveColor)
    static let accent = Color(nsColor: accentColor)
    static let accentSoft = Color(nsColor: accentSoftColor)
    static let dayDivider = Color(nsColor: dayDividerColor)

    static let contentMaxWidth: CGFloat = CGFloat(CurrentConfiguration.default.contentWidth)
    static let timelineHorizontalPadding: CGFloat = 32
    static let timelineTopPadding: CGFloat = 8
    static let timelineBottomPadding: CGFloat = 80
    static let timelineTopFadeHeight: CGFloat = 132
    static let timelineTopFadeSolidHeight: CGFloat = 58
    static let timelineScrollbarFadeClearance: CGFloat = 28
    static let historyPreloadDistance: CGFloat = 280
    static let historyResetDistance: CGFloat = 32
    static let scrollTargetAnchorY: CGFloat = 0.18
    static let daySaveStateOrbSize: CGFloat = 5
    static let dayDividerDateStatusSpacing: CGFloat = 11
    static let dayDividerStatusLineSpacing: CGFloat = 10
    static let dayDividerIntrinsicHeight: CGFloat = 16
    static let daySectionVerticalPaddingCollapsed: CGFloat = 8
    static let daySectionVerticalPaddingExpanded: CGFloat = 12
    static let dayEditorTopPadding: CGFloat = 6
    static let editorFontSize: CGFloat = CGFloat(CurrentConfiguration.default.fontSize)
    static let editorLineHeight: CGFloat = CGFloat(CurrentConfiguration.default.lineHeight)
    static let editorHorizontalInset: CGFloat = 0
    static let editorVerticalInset: CGFloat = 8
    static var editorFont: NSFont {
        editorFont(configuration: .default)
    }
    static var editorBoldFont: NSFont {
        editorBoldFont(configuration: .default)
    }
    static var editorHeadingFont: NSFont {
        editorHeadingFont(level: 3)
    }
    static func contentMaxWidth(configuration: CurrentConfiguration) -> CGFloat {
        CGFloat(configuration.contentWidth)
    }
    static func editorFontSize(configuration: CurrentConfiguration) -> CGFloat {
        CGFloat(configuration.fontSize)
    }
    static func editorLineHeight(configuration: CurrentConfiguration) -> CGFloat {
        CGFloat(configuration.lineHeight)
    }
    static func editorSwiftUIFont(configuration: CurrentConfiguration) -> Font {
        if let fontFamily = configuration.fontFamily {
            return .custom(fontFamily, size: editorFontSize(configuration: configuration))
        }
        return .system(size: editorFontSize(configuration: configuration), design: .default)
    }
    static func editorFont(configuration: CurrentConfiguration) -> NSFont {
        configuredFont(
            family: configuration.fontFamily,
            size: editorFontSize(configuration: configuration),
            weight: .regular
        )
    }
    static func editorCodeFont(configuration: CurrentConfiguration) -> NSFont {
        NSFont.monospacedSystemFont(ofSize: max(11, editorFontSize(configuration: configuration) - 1), weight: .regular)
    }
    static func editorBoldFont(configuration: CurrentConfiguration) -> NSFont {
        configuredFont(
            family: configuration.fontFamily,
            size: editorFontSize(configuration: configuration),
            weight: .semibold
        )
    }
    static func editorHeadingFont(level: Int) -> NSFont {
        editorHeadingFont(level: level, configuration: .default)
    }
    static func editorHeadingFont(level: Int, configuration: CurrentConfiguration) -> NSFont {
        configuredFont(
            family: configuration.fontFamily,
            size: editorHeadingFontSize(level: level, configuration: configuration),
            weight: .semibold
        )
    }
    static func editorHeadingLineHeight(level: Int) -> CGFloat {
        editorHeadingLineHeight(level: level, configuration: .default)
    }
    static func editorHeadingLineHeight(level: Int, configuration: CurrentConfiguration) -> CGFloat {
        let lineHeight = editorLineHeight(configuration: configuration)
        switch level {
        case 1:
            return lineHeight + 8.4
        case 2:
            return lineHeight + 2.4
        case 3:
            return lineHeight + 2
        default:
            return lineHeight
        }
    }
    static func editorHeadingSpacingBefore(level: Int) -> CGFloat {
        switch level {
        case 1:
            return 8
        case 2:
            return 6
        case 3:
            return 3
        default:
            return 0
        }
    }
    static func editorHeadingSpacingAfter(level: Int) -> CGFloat {
        switch level {
        case 1:
            return 3
        case 2:
            return 2
        default:
            return 0
        }
    }
    static func editorBoldFont(matching font: NSFont) -> NSFont {
        configuredFont(family: font.familyName, size: font.pointSize, weight: .semibold)
    }
    static let editorBaselineOffset: CGFloat = 1
    static let streamLabel = Font.system(size: 11, weight: .medium)
    static let searchText = Font.system(size: 12, weight: .regular)
    static let iconButton = Font.system(size: 14, weight: .regular)
    static let tinyLabel = Font.system(size: 10, weight: .medium)
    static let metadata = Font.system(size: 10, weight: .regular)
    static let dayLabel = Font.system(size: 12, weight: .regular)
}

private func editorHeadingFontSize(level: Int, configuration: CurrentConfiguration = .default) -> CGFloat {
    let baseSize = CurrentTheme.editorFontSize(configuration: configuration)
    switch level {
    case 1:
        return baseSize + 10
    case 2:
        return baseSize + 5
    case 3:
        return baseSize + 2
    default:
        return baseSize
    }
}

private func configuredFont(family: String?, size: CGFloat, weight: NSFont.Weight) -> NSFont {
    guard let family, !family.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        return NSFont.systemFont(ofSize: size, weight: weight)
    }

    let managerWeight = weight == .semibold ? 8 : 5
    if let font = NSFontManager.shared.font(
        withFamily: family,
        traits: [],
        weight: managerWeight,
        size: size
    ) {
        return font
    }
    if let font = NSFont(name: family, size: size) {
        return font
    }
    return NSFont.systemFont(ofSize: size, weight: weight)
}

private extension NSColor {
    static func currentAdaptive(light: Int, dark: Int) -> NSColor {
        NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return .currentHex(isDark ? dark : light)
        }
    }

    static func currentHex(_ hex: Int, alpha: CGFloat = 1) -> NSColor {
        NSColor(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }

    static func currentBlack(alpha: CGFloat) -> NSColor {
        NSColor(srgbRed: 0, green: 0, blue: 0, alpha: alpha)
    }
}
