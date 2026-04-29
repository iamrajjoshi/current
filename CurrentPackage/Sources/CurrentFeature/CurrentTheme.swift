import SwiftUI

enum CurrentTheme {
    static let pageBackground = Color(nsColor: .textBackgroundColor)
    static let subtleBackground = Color(nsColor: .controlBackgroundColor)
    static let divider = Color(nsColor: .separatorColor)
    static let text = Color(nsColor: .labelColor)
    static let secondaryText = Color(nsColor: .secondaryLabelColor)
    static let accent = Color.accentColor

    static let editorFontSize: CGFloat = 15
    static let editorLineHeight: CGFloat = 22
    static let editorHorizontalInset: CGFloat = 4
    static let editorVerticalInset: CGFloat = 8
}
