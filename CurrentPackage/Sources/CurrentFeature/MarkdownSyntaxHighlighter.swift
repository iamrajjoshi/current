import AppKit

final class MarkdownSyntaxHighlighter {
    private let baseFont = NSFont.monospacedSystemFont(ofSize: CurrentTheme.editorFontSize, weight: .regular)
    private let headingFont = NSFont.systemFont(ofSize: 17, weight: .semibold)
    private let codeFont = NSFont.monospacedSystemFont(ofSize: CurrentTheme.editorFontSize, weight: .regular)

    func highlight(_ textStorage: NSTextStorage) {
        let fullRange = NSRange(location: 0, length: textStorage.length)
        guard fullRange.length > 0 else { return }

        textStorage.beginEditing()
        textStorage.setAttributes(baseAttributes(), range: fullRange)

        apply(pattern: #"(?ms)^```.*?^```"#, to: textStorage, attributes: [
            .font: codeFont,
            .foregroundColor: NSColor.systemPurple
        ])
        apply(pattern: #"(?m)^#{1,6}\s.*$"#, to: textStorage, attributes: [
            .font: headingFont,
            .foregroundColor: NSColor.labelColor
        ])
        apply(pattern: #"(?m)^\s*>\s.*$"#, to: textStorage, attributes: [
            .foregroundColor: NSColor.systemIndigo
        ])
        apply(pattern: #"(?m)^\s*(?:[-*+]|\d+\.)\s+(?:\[[ xX]\]\s+)?.*$"#, to: textStorage, attributes: [
            .foregroundColor: NSColor.labelColor
        ])
        apply(pattern: #"`[^`\n]+`"#, to: textStorage, attributes: [
            .font: codeFont,
            .foregroundColor: NSColor.systemPurple
        ])
        apply(pattern: #"\[[^\]\n]+\]\([^)]+\)"#, to: textStorage, attributes: [
            .foregroundColor: NSColor.systemBlue,
            .underlineStyle: NSUnderlineStyle.single.rawValue
        ])
        apply(pattern: #"(?<!\*)\*\*[^*\n]+\*\*"#, to: textStorage, attributes: [
            .font: NSFont.monospacedSystemFont(ofSize: CurrentTheme.editorFontSize, weight: .semibold)
        ])
        apply(pattern: #"(?<!\*)\*[^*\n]+\*"#, to: textStorage, attributes: [
            .obliqueness: 0.12
        ])

        textStorage.endEditing()
    }

    private func baseAttributes() -> [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = CurrentTheme.editorLineHeight
        paragraph.maximumLineHeight = CurrentTheme.editorLineHeight
        paragraph.lineBreakMode = .byWordWrapping

        return [
            .font: baseFont,
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraph,
            .baselineOffset: 1
        ]
    }

    private func apply(
        pattern: String,
        to textStorage: NSTextStorage,
        attributes: [NSAttributedString.Key: Any]
    ) {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return }
        let string = textStorage.string as NSString
        let range = NSRange(location: 0, length: string.length)
        regex.enumerateMatches(in: textStorage.string, range: range) { match, _, _ in
            guard let match else { return }
            textStorage.addAttributes(attributes, range: match.range)
        }
    }
}
