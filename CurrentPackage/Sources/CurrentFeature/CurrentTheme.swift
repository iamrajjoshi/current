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

    static let contentMaxWidth: CGFloat = 700
    static let editorFontSize: CGFloat = 13
    static let editorLineHeight: CGFloat = 22
    static let editorHorizontalInset: CGFloat = 0
    static let editorVerticalInset: CGFloat = 8
    static var editorFont: NSFont {
        NSFont.monospacedSystemFont(ofSize: editorFontSize, weight: .regular)
    }
    static var editorBoldFont: NSFont {
        NSFont.monospacedSystemFont(ofSize: editorFontSize, weight: .semibold)
    }
    static var editorHeadingFont: NSFont {
        NSFont.monospacedSystemFont(ofSize: editorFontSize + 1, weight: .semibold)
    }
    static let editorBaselineOffset: CGFloat = 1
    static let streamLabel = Font.system(size: 11, weight: .medium)
    static let searchText = Font.system(size: 12, weight: .regular)
    static let iconButton = Font.system(size: 14, weight: .regular)
    static let tinyLabel = Font.system(size: 10, weight: .medium)
    static let metadata = Font.system(size: 10, weight: .regular)
    static let dayLabel = Font.system(size: 11, weight: .semibold)
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
