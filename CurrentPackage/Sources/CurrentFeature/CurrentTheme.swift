import AppKit
import SwiftUI

enum CurrentTheme {
    static let pageBackgroundColor = NSColor.currentHex(0xFFFFFF)
    static let appSurfaceColor = NSColor.currentHex(0xF6F5F4)
    static let chromeBackgroundColor = NSColor.currentHex(0xF6F5F4, alpha: 0.82)
    static let editorBackgroundColor = NSColor.currentHex(0xFFFFFF)
    static let primaryTextColor = NSColor.currentBlack(alpha: 0.92)
    static let secondaryTextColor = NSColor.currentHex(0x615D59)
    static let mutedTextColor = NSColor.currentHex(0xA39E98)
    static let dividerColor = NSColor.currentBlack(alpha: 0.10)
    static let softDividerColor = NSColor.currentBlack(alpha: 0.06)
    static let fieldBackgroundColor = NSColor.currentBlack(alpha: 0.035)
    static let fieldBackgroundActiveColor = NSColor.currentBlack(alpha: 0.055)
    static let accentColor = NSColor.currentHex(0x0075DE)
    static let accentSoftColor = NSColor.currentHex(0xF2F9FF)
    static let inlineCodeBackgroundColor = NSColor.currentBlack(alpha: 0.045)
    static let dayDividerColor = NSColor.currentBlack(alpha: 0.055)

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
    static let timelineHorizontalPadding: CGFloat = 56
    static let timelineTopPadding: CGFloat = 118
    static let timelineBottomPadding: CGFloat = 132
    static let timelineTopFadeHeight: CGFloat = 132
    static let timelineTopFadeSolidHeight: CGFloat = 58
    static let timelineScrollbarFadeClearance: CGFloat = 28
    static let historyPreloadDistance: CGFloat = 280
    static let historyResetDistance: CGFloat = 32
    static let scrollTargetAnchorY: CGFloat = 0.18
    static let dayLabelRailWidth: CGFloat = 146
    static let dayDividerSpacing: CGFloat = 12
    static let dayDividerIntrinsicHeight: CGFloat = 14
    static let daySectionVerticalPaddingCollapsed: CGFloat = 8
    static let daySectionVerticalPaddingExpanded: CGFloat = 13
    static let dayEditorTopPadding: CGFloat = 14
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
        return .system(size: editorFontSize(configuration: configuration), design: .monospaced)
    }
    static func editorFont(configuration: CurrentConfiguration) -> NSFont {
        configuredFont(
            family: configuration.fontFamily,
            size: editorFontSize(configuration: configuration),
            weight: .regular
        )
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
            return lineHeight + 6
        case 2:
            return lineHeight + 3
        case 3:
            return lineHeight + 1
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
    static let dayLabel = Font.system(size: 10.5, weight: .medium)
}

private func editorHeadingFontSize(level: Int, configuration: CurrentConfiguration = .default) -> CGFloat {
    let baseSize = CurrentTheme.editorFontSize(configuration: configuration)
    switch level {
    case 1:
        return baseSize + 4
    case 2:
        return baseSize + 2
    case 3:
        return baseSize + 1
    default:
        return baseSize
    }
}

private func configuredFont(family: String?, size: CGFloat, weight: NSFont.Weight) -> NSFont {
    guard let family, !family.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        return NSFont.monospacedSystemFont(ofSize: size, weight: weight)
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
    return NSFont.monospacedSystemFont(ofSize: size, weight: weight)
}

private extension NSColor {
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
