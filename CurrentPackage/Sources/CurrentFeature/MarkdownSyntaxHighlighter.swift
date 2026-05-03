import AppKit

final class MarkdownSyntaxHighlighter {
    private var configuration: CurrentConfiguration

    init(configuration: CurrentConfiguration = .default) {
        self.configuration = configuration
    }

    func update(configuration: CurrentConfiguration) {
        self.configuration = configuration
    }

    private var baseFont: NSFont {
        CurrentTheme.editorFont(configuration: configuration)
    }

    private var codeFont: NSFont {
        CurrentTheme.editorFont(configuration: configuration)
    }

    func highlight(_ textStorage: NSTextStorage) {
        let fullRange = NSRange(location: 0, length: textStorage.length)
        guard fullRange.length > 0 else { return }

        textStorage.beginEditing()
        textStorage.setAttributes(baseAttributes(), range: fullRange)

        let protectedRanges = applyProtected(pattern: #"(?ms)^```.*?^```"#, to: textStorage, attributes: [
            .font: codeFont,
            .foregroundColor: codeColor
        ])

        applyHeadingLines(to: textStorage, protectedRanges: protectedRanges)
        applyGroups(
            pattern: #"(?m)^(\s*>\s?)(.*)$"#,
            to: textStorage,
            protectedRanges: protectedRanges,
            groups: [
                (1, [.foregroundColor: syntaxColor]),
                (2, [.foregroundColor: CurrentTheme.secondaryTextColor])
            ]
        )
        applyGroups(
            pattern: #"(?m)^([ \t]*(?:[-*+]|\d+\.)(?:[ \t]+\[[ xX]\])?[ \t]+)"#,
            to: textStorage,
            protectedRanges: protectedRanges,
            groups: [(1, [.foregroundColor: syntaxColor])]
        )
        applyListParagraphStyles(to: textStorage, protectedRanges: protectedRanges)
        applyGroups(
            pattern: #"(`+)([^`\n]+)(\1)"#,
            to: textStorage,
            protectedRanges: protectedRanges,
            groups: [
                (1, [.foregroundColor: syntaxColor]),
                (2, [
                    .font: codeFont,
                    .foregroundColor: codeColor,
                    .backgroundColor: CurrentTheme.inlineCodeBackgroundColor
                ]),
                (3, [.foregroundColor: syntaxColor])
            ]
        )
        applyGroups(
            pattern: #"(!?\[)([^\]\n]+)(\]\([^)]+\))"#,
            to: textStorage,
            protectedRanges: protectedRanges,
            groups: [
                (1, [.foregroundColor: syntaxColor]),
                (2, [.foregroundColor: CurrentTheme.accentColor]),
                (3, [.foregroundColor: syntaxColor])
            ]
        )
        applyUnderline(to: textStorage, protectedRanges: protectedRanges)
        applyBold(pattern: #"(?<!\*)\*\*([^*\n]+)\*\*(?!\*)"#, to: textStorage, protectedRanges: protectedRanges)
        apply(pattern: #"(?<!\*)\*\*|\*\*(?!\*)"#, to: textStorage, protectedRanges: protectedRanges, attributes: [
            .foregroundColor: syntaxColor
        ])
        applyBold(pattern: #"(?<!_)__([^_\n]+)__(?!_)"#, to: textStorage, protectedRanges: protectedRanges)
        apply(pattern: #"(?<!_)__|__(?!_)"#, to: textStorage, protectedRanges: protectedRanges, attributes: [
            .foregroundColor: syntaxColor
        ])
        applyGroups(
            pattern: #"(?<!\*)\*([^*\n]+)\*(?!\*)"#,
            to: textStorage,
            protectedRanges: protectedRanges,
            groups: [(1, [.obliqueness: 0.12])]
        )
        apply(pattern: #"(?<!\*)\*|\*(?!\*)"#, to: textStorage, protectedRanges: protectedRanges, attributes: [
            .foregroundColor: syntaxColor
        ])
        applyGroups(
            pattern: #"(?<!_)_([^_\n]+)_(?!_)"#,
            to: textStorage,
            protectedRanges: protectedRanges,
            groups: [(1, [.obliqueness: 0.12])]
        )
        apply(pattern: #"(?<!_)_|_(?!_)"#, to: textStorage, protectedRanges: protectedRanges, attributes: [
            .foregroundColor: syntaxColor
        ])
        apply(pattern: #"(?m)^[-*_]{3,}\s*$"#, to: textStorage, protectedRanges: protectedRanges, attributes: [
            .foregroundColor: syntaxColor
        ])

        textStorage.endEditing()
    }

    private var syntaxColor: NSColor {
        CurrentTheme.mutedTextColor
    }

    private var codeColor: NSColor {
        CurrentTheme.secondaryTextColor
    }

    private func baseAttributes() -> [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = CurrentTheme.editorLineHeight(configuration: configuration)
        paragraph.maximumLineHeight = CurrentTheme.editorLineHeight(configuration: configuration)
        paragraph.lineBreakMode = .byWordWrapping

        return [
            .font: baseFont,
            .foregroundColor: CurrentTheme.primaryTextColor,
            .paragraphStyle: paragraph,
            .baselineOffset: CurrentTheme.editorBaselineOffset
        ]
    }

    private func listParagraphStyle(prefix: String) -> NSMutableParagraphStyle {
        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = CurrentTheme.editorLineHeight(configuration: configuration)
        paragraph.maximumLineHeight = CurrentTheme.editorLineHeight(configuration: configuration)
        paragraph.lineBreakMode = .byWordWrapping
        paragraph.headIndent = ceil((prefix as NSString).size(withAttributes: [.font: baseFont]).width)
        paragraph.firstLineHeadIndent = 0
        return paragraph
    }

    private func headingParagraphStyle(level: Int) -> NSMutableParagraphStyle {
        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = CurrentTheme.editorHeadingLineHeight(level: level, configuration: configuration)
        paragraph.maximumLineHeight = CurrentTheme.editorHeadingLineHeight(level: level, configuration: configuration)
        paragraph.lineBreakMode = .byWordWrapping
        paragraph.paragraphSpacingBefore = CurrentTheme.editorHeadingSpacingBefore(level: level)
        paragraph.paragraphSpacing = CurrentTheme.editorHeadingSpacingAfter(level: level)
        return paragraph
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

    private func applyHeadingLines(to textStorage: NSTextStorage, protectedRanges: [NSRange]) {
        for heading in MarkdownBlockRendering.headingLines(in: textStorage.string) {
            guard !intersectsProtected(heading.lineRange, protectedRanges: protectedRanges) else { continue }
            let headingFont = CurrentTheme.editorHeadingFont(level: heading.level, configuration: configuration)

            textStorage.addAttribute(.paragraphStyle, value: headingParagraphStyle(level: heading.level), range: heading.lineRange)
            textStorage.addAttributes([
                .font: headingFont,
                .foregroundColor: syntaxColor
            ], range: heading.prefixRange)

            if heading.hasContent {
                textStorage.addAttributes([
                    .font: headingFont,
                    .foregroundColor: CurrentTheme.primaryTextColor
                ], range: heading.contentRange)
            }
        }
    }

    private func applyUnderline(to textStorage: NSTextStorage, protectedRanges: [NSRange]) {
        let pattern = #"(<u>)([^<\n]+)(</u>)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return }
        let string = textStorage.string as NSString
        let range = NSRange(location: 0, length: string.length)

        regex.enumerateMatches(in: textStorage.string, range: range) { match, _, _ in
            guard let match else { return }
            guard !intersectsProtected(match.range, protectedRanges: protectedRanges) else { return }

            let openRange = match.range(at: 1)
            let contentRange = match.range(at: 2)
            let closeRange = match.range(at: 3)
            guard contentRange.location != NSNotFound, contentRange.length > 0 else { return }

            textStorage.addAttributes([
                .foregroundColor: syntaxColor
            ], range: openRange)
            textStorage.addAttributes([
                .underlineStyle: NSUnderlineStyle.single.rawValue
            ], range: contentRange)
            textStorage.addAttributes([
                .foregroundColor: syntaxColor
            ], range: closeRange)
        }
    }

    private func applyBold(pattern: String, to textStorage: NSTextStorage, protectedRanges: [NSRange]) {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return }
        let string = textStorage.string as NSString
        let range = NSRange(location: 0, length: string.length)

        regex.enumerateMatches(in: textStorage.string, range: range) { match, _, _ in
            guard let match else { return }
            guard !intersectsProtected(match.range, protectedRanges: protectedRanges) else { return }
            let contentRange = match.range(at: 1)
            guard contentRange.location != NSNotFound, contentRange.length > 0 else { return }

            let currentFont = textStorage.attribute(.font, at: contentRange.location, effectiveRange: nil) as? NSFont ?? baseFont
            textStorage.addAttributes([
                .font: CurrentTheme.editorBoldFont(matching: currentFont)
            ], range: contentRange)
        }
    }

    private func applyListParagraphStyles(to textStorage: NSTextStorage, protectedRanges: [NSRange]) {
        let pattern = #"(?m)^([ \t]*(?:[-*+]|\d+\.)(?:[ \t]+\[[ xX]\])?[ \t]+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return }
        let string = textStorage.string as NSString
        let range = NSRange(location: 0, length: string.length)
        regex.enumerateMatches(in: textStorage.string, range: range) { match, _, _ in
            guard let match else { return }
            guard !intersectsProtected(match.range, protectedRanges: protectedRanges) else { return }
            let prefixRange = match.range(at: 1)
            guard prefixRange.location != NSNotFound else { return }
            let prefix = string.substring(with: prefixRange)
            let lineRange = string.lineRange(for: match.range)
            textStorage.addAttribute(.paragraphStyle, value: listParagraphStyle(prefix: prefix), range: lineRange)
        }
    }

    private func intersectsProtected(_ range: NSRange, protectedRanges: [NSRange]) -> Bool {
        protectedRanges.contains { protectedRange in
            NSIntersectionRange(range, protectedRange).length > 0
        }
    }
}
