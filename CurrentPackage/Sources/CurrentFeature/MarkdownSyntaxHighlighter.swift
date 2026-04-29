import AppKit

final class MarkdownSyntaxHighlighter {
    private let baseFont = CurrentTheme.editorFont
    private let headingFont = CurrentTheme.editorHeadingFont
    private let codeFont = CurrentTheme.editorFont

    func highlight(_ textStorage: NSTextStorage) {
        let fullRange = NSRange(location: 0, length: textStorage.length)
        guard fullRange.length > 0 else { return }

        textStorage.beginEditing()
        textStorage.setAttributes(baseAttributes(), range: fullRange)

        let protectedRanges = applyProtected(pattern: #"(?ms)^```.*?^```"#, to: textStorage, attributes: [
            .font: codeFont,
            .foregroundColor: codeColor
        ])

        applyGroups(
            pattern: #"(?m)^(#{1,6}\s+)(.+)$"#,
            to: textStorage,
            protectedRanges: protectedRanges,
            groups: [
                (1, [.foregroundColor: syntaxColor]),
                (2, [.font: headingFont, .foregroundColor: NSColor.labelColor])
            ]
        )
        applyGroups(
            pattern: #"(?m)^(\s*>\s?)(.*)$"#,
            to: textStorage,
            protectedRanges: protectedRanges,
            groups: [
                (1, [.foregroundColor: syntaxColor]),
                (2, [.foregroundColor: NSColor.secondaryLabelColor])
            ]
        )
        applyGroups(
            pattern: #"(?m)^(\s*(?:[-*+]|\d+\.)\s+(?:\[[ xX]\]\s+)?)"#,
            to: textStorage,
            protectedRanges: protectedRanges,
            groups: [(1, [.foregroundColor: syntaxColor])]
        )
        applyGroups(
            pattern: #"(`+)([^`\n]+)(\1)"#,
            to: textStorage,
            protectedRanges: protectedRanges,
            groups: [
                (1, [.foregroundColor: syntaxColor]),
                (2, [.font: codeFont, .foregroundColor: codeColor, .backgroundColor: NSColor.labelColor.withAlphaComponent(0.06)]),
                (3, [.foregroundColor: syntaxColor])
            ]
        )
        applyGroups(
            pattern: #"(!?\[)([^\]\n]+)(\]\([^)]+\))"#,
            to: textStorage,
            protectedRanges: protectedRanges,
            groups: [
                (1, [.foregroundColor: syntaxColor]),
                (2, [.foregroundColor: NSColor.systemBlue]),
                (3, [.foregroundColor: syntaxColor])
            ]
        )
        applyGroups(
            pattern: #"(?<!\*)\*\*([^*\n]+)\*\*"#,
            to: textStorage,
            protectedRanges: protectedRanges,
            groups: [(1, [.font: CurrentTheme.editorBoldFont])]
        )
        apply(pattern: #"(?<!\*)\*\*|\*\*"#, to: textStorage, protectedRanges: protectedRanges, attributes: [
            .foregroundColor: syntaxColor
        ])
        applyGroups(
            pattern: #"(?<!\*)\*([^*\n]+)\*"#,
            to: textStorage,
            protectedRanges: protectedRanges,
            groups: [(1, [.obliqueness: 0.12])]
        )
        apply(pattern: #"(?<!\*)\*|\*(?!\*)"#, to: textStorage, protectedRanges: protectedRanges, attributes: [
            .foregroundColor: syntaxColor
        ])
        apply(pattern: #"(?m)^[-*_]{3,}\s*$"#, to: textStorage, protectedRanges: protectedRanges, attributes: [
            .foregroundColor: syntaxColor
        ])

        textStorage.endEditing()
    }

    private var syntaxColor: NSColor {
        NSColor.secondaryLabelColor.withAlphaComponent(0.68)
    }

    private var codeColor: NSColor {
        NSColor.secondaryLabelColor
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
            .baselineOffset: CurrentTheme.editorBaselineOffset
        ]
    }

    @discardableResult
    private func applyProtected(
        pattern: String,
        to textStorage: NSTextStorage,
        attributes: [NSAttributedString.Key: Any]
    ) -> [NSRange] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let string = textStorage.string as NSString
        let range = NSRange(location: 0, length: string.length)
        var ranges: [NSRange] = []
        regex.enumerateMatches(in: textStorage.string, range: range) { match, _, _ in
            guard let match else { return }
            ranges.append(match.range)
            textStorage.addAttributes(attributes, range: match.range)
            if match.range.length >= 3 {
                textStorage.addAttributes([.foregroundColor: syntaxColor], range: NSRange(location: match.range.location, length: 3))
                let closeStart = NSMaxRange(match.range) - 3
                if closeStart >= match.range.location {
                    textStorage.addAttributes([.foregroundColor: syntaxColor], range: NSRange(location: closeStart, length: 3))
                }
            }
        }
        return ranges
    }

    private func apply(
        pattern: String,
        to textStorage: NSTextStorage,
        protectedRanges: [NSRange],
        attributes: [NSAttributedString.Key: Any]
    ) {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return }
        let string = textStorage.string as NSString
        let range = NSRange(location: 0, length: string.length)
        regex.enumerateMatches(in: textStorage.string, range: range) { match, _, _ in
            guard let match else { return }
            guard !intersectsProtected(match.range, protectedRanges: protectedRanges) else { return }
            textStorage.addAttributes(attributes, range: match.range)
        }
    }

    private func applyGroups(
        pattern: String,
        to textStorage: NSTextStorage,
        protectedRanges: [NSRange],
        groups: [(Int, [NSAttributedString.Key: Any])]
    ) {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return }
        let string = textStorage.string as NSString
        let range = NSRange(location: 0, length: string.length)
        regex.enumerateMatches(in: textStorage.string, range: range) { match, _, _ in
            guard let match else { return }
            guard !intersectsProtected(match.range, protectedRanges: protectedRanges) else { return }
            for (index, attributes) in groups where index < match.numberOfRanges {
                let groupRange = match.range(at: index)
                guard groupRange.location != NSNotFound, groupRange.length > 0 else { continue }
                textStorage.addAttributes(attributes, range: groupRange)
            }
        }
    }

    private func intersectsProtected(_ range: NSRange, protectedRanges: [NSRange]) -> Bool {
        protectedRanges.contains { protectedRange in
            NSIntersectionRange(range, protectedRange).length > 0
        }
    }
}
