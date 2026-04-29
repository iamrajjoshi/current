import AppKit
import SwiftUI

enum CurrentTheme {
    static let pageBackground = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.isDarkMode ? NSColor(calibratedWhite: 0.105, alpha: 1) : NSColor(calibratedWhite: 0.985, alpha: 1)
    })
    static let chromeBackground = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.isDarkMode ? NSColor(calibratedWhite: 0.13, alpha: 0.92) : NSColor(calibratedWhite: 0.97, alpha: 0.92)
    })
    static let editorBackground = NSColor(name: nil) { appearance in
        appearance.isDarkMode ? NSColor(calibratedWhite: 0.105, alpha: 1) : NSColor(calibratedWhite: 0.985, alpha: 1)
    }
    static let divider = Color.primary.opacity(0.06)
    static let strongDivider = Color.primary.opacity(0.10)
    static let text = Color.primary
    static let secondaryText = Color.secondary
    static let accent = Color.accentColor
    static let mutedAccent = Color.accentColor.opacity(0.75)
    static let contentMaxWidth: CGFloat = 680

    static let editorFontSize: CGFloat = 12
    static let editorLineHeight: CGFloat = 20
    static let editorHorizontalInset: CGFloat = 0
    static let editorVerticalInset: CGFloat = 6
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
    static let tinyLabel = Font.system(size: 10, weight: .medium)
    static let dayLabel = Font.system(size: 10, weight: .semibold)
}

private extension NSAppearance {
    var isDarkMode: Bool {
        bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }
}
