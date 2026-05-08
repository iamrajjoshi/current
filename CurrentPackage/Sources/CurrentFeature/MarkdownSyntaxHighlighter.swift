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

    func highlight(_ textStorage: NSTextStorage, selectedRange: NSRange? = nil) {
        let fullRange = NSRange(location: 0, length: textStorage.length)
        guard fullRange.length > 0 else { return }

        highlight(textStorage, in: fullRange, selectedRange: selectedRange)
    }

    func highlightAroundEditedRange(
        _ textStorage: NSTextStorage,
        editedRange: NSRange?,
        selectedRange: NSRange? = nil
    ) {
        let fullRange = NSRange(location: 0, length: textStorage.length)
        guard fullRange.length > 0 else { return }

        let targetRange = MarkdownEditorRenderModel.decorationRange(
            around: editedRange ?? fullRange,
            in: textStorage.string
        )
        guard targetRange.length > 0 else { return }

        highlight(textStorage, in: targetRange, selectedRange: selectedRange)
    }

    func highlightAroundSelectionChange(
        _ textStorage: NSTextStorage,
        oldSelectedRange: NSRange?,
        newSelectedRange: NSRange?
    ) {
        let fullRange = NSRange(location: 0, length: textStorage.length)
        guard fullRange.length > 0 else { return }

        guard let targetRange = MarkdownLiveRenderPolicy.decorationRangeForSelectionChange(
            in: textStorage.string,
            oldSelectedRange: oldSelectedRange,
            newSelectedRange: newSelectedRange
        ) else { return }

        let clampedRange = NSIntersectionRange(targetRange, fullRange)
        guard clampedRange.length > 0 else { return }
        highlight(textStorage, in: clampedRange, selectedRange: newSelectedRange)
    }

    private func highlight(_ textStorage: NSTextStorage, in targetRange: NSRange, selectedRange: NSRange?) {
        let model = MarkdownEditorRenderModel(text: textStorage.string)
        let policy = MarkdownLiveRenderPolicy(model: model, selectedRange: selectedRange)
        clearTemporaryDecorations(textStorage)
        textStorage.beginEditing()
        textStorage.setAttributes(baseAttributes(), range: targetRange)

        let protectedRanges = applyProtected(model.protectedRanges, to: textStorage, attributes: [
            .font: codeFont,
            .foregroundColor: codeColor
        ], targetRange: targetRange)

        applyHeadingLines(model: model, to: textStorage, targetRange: targetRange, protectedRanges: protectedRanges)
        applyGroups(
            pattern: #"(?m)^(\s*>\s?)(.*)$"#,
            to: textStorage,
            targetRange: targetRange,
            protectedRanges: protectedRanges,
            groups: [
                (1, [.foregroundColor: syntaxColor]),
                (2, [.foregroundColor: CurrentTheme.secondaryTextColor])
            ]
        )
        applyGroups(
            pattern: #"(?m)^([ \t]*(?:[-*+]|\d+\.)(?:[ \t]+\[[ xX]\])?[ \t]+)"#,
            to: textStorage,
            targetRange: targetRange,
            protectedRanges: protectedRanges,
            groups: [(1, [.foregroundColor: syntaxColor])]
        )
        applyTaskCheckboxes(to: textStorage, targetRange: targetRange, protectedRanges: protectedRanges)
        applyListParagraphStyles(model: model, to: textStorage, targetRange: targetRange, protectedRanges: protectedRanges)
        applyInlineSpans(model: model, policy: policy, to: textStorage, targetRange: targetRange)
        applyHorizontalRules(model: model, policy: policy, to: textStorage, targetRange: targetRange, protectedRanges: protectedRanges)

        textStorage.endEditing()
        invalidateDecorationDisplay(textStorage, range: targetRange)
    }

    func clearTemporaryDecorations(_ textStorage: NSTextStorage) {
        let fullRange = NSRange(location: 0, length: textStorage.length)
        guard fullRange.length > 0 else { return }

        for layoutManager in textStorage.layoutManagers {
            temporaryDecorationKeys.forEach {
                layoutManager.removeTemporaryAttribute($0, forCharacterRange: fullRange)
            }
        }
    }

    private var syntaxColor: NSColor {
        switch configuration.markdownMarkerVisibility {
        case .hidden:
            return CurrentTheme.mutedTextColor
        case .muted:
            return CurrentTheme.mutedTextColor
        }
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
            .baselineOffset: CurrentTheme.editorBaselineOffset,
            .underlineStyle: 0,
            .underlineColor: CurrentTheme.primaryTextColor,
            .strikethroughStyle: 0,
            .obliqueness: 0,
            .currentHorizontalRule: false,
            .currentHorizontalRuleMarker: false,
            .currentHiddenMarkdownSyntax: false,
            .currentCollapsedMarkdownSyntax: false,
            .spellingState: 0,
            .backgroundColor: NSColor.clear
        ]
    }

    private func hiddenSyntaxAttributes(collapsesWidth: Bool = true) -> [NSAttributedString.Key: Any] {
        [
            .currentHiddenMarkdownSyntax: true,
            .currentCollapsedMarkdownSyntax: collapsesWidth,
            .foregroundColor: NSColor.clear,
            .underlineStyle: 0,
            .underlineColor: NSColor.clear,
            .strikethroughStyle: 0,
            .spellingState: 0,
            .backgroundColor: NSColor.clear
        ]
    }

    private func revealedSyntaxAttributes() -> [NSAttributedString.Key: Any] {
        [
            .currentHiddenMarkdownSyntax: false,
            .currentCollapsedMarkdownSyntax: false,
            .foregroundColor: syntaxColor,
            .underlineStyle: 0,
            .underlineColor: NSColor.clear,
            .strikethroughStyle: 0,
            .spellingState: 0,
            .backgroundColor: NSColor.clear
        ]
    }

    private func horizontalRuleParagraphStyle() -> NSMutableParagraphStyle {
        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = CurrentTheme.editorLineHeight(configuration: configuration)
        paragraph.maximumLineHeight = CurrentTheme.editorLineHeight(configuration: configuration)
        paragraph.lineBreakMode = .byWordWrapping
        paragraph.paragraphSpacingBefore = 0
        paragraph.paragraphSpacing = 0
        return paragraph
    }

    private func horizontalRuleMarkerAttributes(isActive: Bool) -> [NSAttributedString.Key: Any] {
        [
            .currentHorizontalRuleMarker: true,
            .currentHiddenMarkdownSyntax: false,
            .currentCollapsedMarkdownSyntax: false,
            .font: baseFont,
            .foregroundColor: isActive ? syntaxColor : NSColor.clear,
            .baselineOffset: CurrentTheme.editorBaselineOffset,
            .underlineStyle: 0,
            .underlineColor: NSColor.clear,
            .strikethroughStyle: 0,
            .spellingState: 0,
            .backgroundColor: NSColor.clear
        ]
    }

    private var temporaryDecorationKeys: [NSAttributedString.Key] {
        [
            .underlineStyle,
            .underlineColor,
            .strikethroughStyle,
            .obliqueness,
            .spellingState,
            .markedClauseSegment,
            .backgroundColor,
            .link
        ]
    }

    private func invalidateDecorationDisplay(_ textStorage: NSTextStorage) {
        let fullRange = NSRange(location: 0, length: textStorage.length)
        guard fullRange.length > 0 else { return }

        invalidateDecorationDisplay(textStorage, range: fullRange)
    }

    private func invalidateDecorationDisplay(_ textStorage: NSTextStorage, range: NSRange) {
        for layoutManager in textStorage.layoutManagers {
            layoutManager.invalidateDisplay(forCharacterRange: range)
        }
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

    private func headingParagraphStyle(level: Int, prefixWidth: CGFloat) -> NSMutableParagraphStyle {
        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = CurrentTheme.editorHeadingLineHeight(level: level, configuration: configuration)
        paragraph.maximumLineHeight = CurrentTheme.editorHeadingLineHeight(level: level, configuration: configuration)
        paragraph.lineBreakMode = .byWordWrapping
        paragraph.paragraphSpacingBefore = CurrentTheme.editorHeadingSpacingBefore(level: level)
        paragraph.paragraphSpacing = CurrentTheme.editorHeadingSpacingAfter(level: level)
        paragraph.firstLineHeadIndent = 0
        paragraph.headIndent = prefixWidth
        return paragraph
    }

    @discardableResult
    private func applyProtected(
        _ protectedRanges: [NSRange],
        to textStorage: NSTextStorage,
        attributes: [NSAttributedString.Key: Any],
        targetRange: NSRange
    ) -> [NSRange] {
        var ranges: [NSRange] = []
        for protectedRange in protectedRanges {
            guard rangesIntersect(protectedRange, targetRange) else { continue }
            ranges.append(protectedRange)
            addAttributes(attributes, to: textStorage, range: protectedRange, limitedTo: targetRange)
            if protectedRange.length >= 3 {
                addAttributes(
                    [.foregroundColor: syntaxColor],
                    to: textStorage,
                    range: NSRange(location: protectedRange.location, length: 3),
                    limitedTo: targetRange
                )
                let closeStart = NSMaxRange(protectedRange) - 3
                if closeStart >= protectedRange.location {
                    addAttributes(
                        [.foregroundColor: syntaxColor],
                        to: textStorage,
                        range: NSRange(location: closeStart, length: 3),
                        limitedTo: targetRange
                    )
                }
            }
        }
        return ranges
    }

    private func applyGroups(
        pattern: String,
        to textStorage: NSTextStorage,
        targetRange: NSRange,
        protectedRanges: [NSRange],
        groups: [(Int, [NSAttributedString.Key: Any])]
    ) {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return }
        let string = textStorage.string as NSString
        let range = NSRange(location: 0, length: string.length)
        regex.enumerateMatches(in: textStorage.string, range: range) { match, _, _ in
            guard let match else { return }
            guard rangesIntersect(match.range, targetRange) else { return }
            guard !intersectsProtected(match.range, protectedRanges: protectedRanges) else { return }
            for (index, attributes) in groups where index < match.numberOfRanges {
                let groupRange = match.range(at: index)
                guard groupRange.location != NSNotFound, groupRange.length > 0 else { continue }
                addAttributes(attributes, to: textStorage, range: groupRange, limitedTo: targetRange)
            }
        }
    }

    private func applyHeadingLines(
        model: MarkdownEditorRenderModel,
        to textStorage: NSTextStorage,
        targetRange: NSRange,
        protectedRanges: [NSRange]
    ) {
        for heading in model.headings {
            guard rangesIntersect(heading.lineRange, targetRange) else { continue }
            guard !intersectsProtected(heading.lineRange, protectedRanges: protectedRanges) else { continue }
            let headingFont = CurrentTheme.editorHeadingFont(level: heading.level, configuration: configuration)
            let prefix = (textStorage.string as NSString).substring(with: heading.prefixRange)
            let prefixWidth = ceil(prefix.size(withAttributes: [.font: headingFont]).width)

            addAttributes(
                [
                    .font: headingFont,
                    .foregroundColor: CurrentTheme.primaryTextColor,
                    .paragraphStyle: headingParagraphStyle(
                        level: heading.level,
                        prefixWidth: prefixWidth
                    )
                ],
                to: textStorage,
                range: heading.lineRange,
                limitedTo: targetRange
            )
            addAttributes(
                revealedSyntaxAttributes().merging([
                    .font: headingFont,
                    .baselineOffset: CurrentTheme.editorBaselineOffset
                ]) { _, new in new },
                to: textStorage,
                range: heading.prefixRange,
                limitedTo: targetRange
            )

            if heading.hasContent {
                addAttributes([.foregroundColor: CurrentTheme.primaryTextColor], to: textStorage, range: heading.contentRange, limitedTo: targetRange)
            }
        }
    }

    private func applyInlineSpans(
        model: MarkdownEditorRenderModel,
        policy: MarkdownLiveRenderPolicy,
        to textStorage: NSTextStorage,
        targetRange: NSRange
    ) {
        for span in model.inlineSpans {
            guard rangesIntersect(span.fullRange, targetRange) else { continue }
            span.syntaxRanges.forEach { syntaxRange in
                let attributes = policy.syntaxVisibility(for: syntaxRange) == .revealed
                    ? revealedSyntaxAttributes()
                    : hiddenSyntaxAttributes()
                addAttributes(attributes, to: textStorage, range: syntaxRange, limitedTo: targetRange)
            }

            switch span.kind {
            case .bold:
                let currentFont = textStorage.attribute(.font, at: span.contentRange.location, effectiveRange: nil) as? NSFont ?? baseFont
                addAttributes([
                    .font: CurrentTheme.editorBoldFont(matching: currentFont)
                ], to: textStorage, range: span.contentRange, limitedTo: targetRange)
            case .italic:
                addAttributes([
                    .obliqueness: 0.12
                ], to: textStorage, range: span.contentRange, limitedTo: targetRange)
            case .underline:
                addAttributes([
                    .underlineStyle: NSUnderlineStyle.single.rawValue,
                    .underlineColor: CurrentTheme.primaryTextColor
                ], to: textStorage, range: span.contentRange, limitedTo: targetRange)
            case .strikethrough:
                addAttributes([
                    .strikethroughStyle: NSUnderlineStyle.single.rawValue
                ], to: textStorage, range: span.contentRange, limitedTo: targetRange)
            case .inlineCode:
                addAttributes([
                    .font: codeFont,
                    .foregroundColor: codeColor,
                    .backgroundColor: CurrentTheme.inlineCodeBackgroundColor
                ], to: textStorage, range: span.contentRange, limitedTo: targetRange)
            case .link:
                addAttributes([
                    .foregroundColor: CurrentTheme.accentColor
                ], to: textStorage, range: span.contentRange, limitedTo: targetRange)
            }
        }
    }

    private func applyHorizontalRules(
        model: MarkdownEditorRenderModel,
        policy: MarkdownLiveRenderPolicy,
        to textStorage: NSTextStorage,
        targetRange: NSRange,
        protectedRanges: [NSRange]
    ) {
        for displayState in model.horizontalRules {
            guard case .committedDivider(let horizontalRule) = displayState else { continue }
            guard rangesIntersect(horizontalRule.lineRange, targetRange) else { continue }
            guard !intersectsProtected(horizontalRule.lineRange, protectedRanges: protectedRanges) else { continue }
            let isActive = policy.horizontalRuleIsActive(horizontalRule)
            addAttributes([
                .currentHorizontalRule: true,
                .paragraphStyle: horizontalRuleParagraphStyle(),
                .underlineStyle: 0,
                .underlineColor: NSColor.clear,
                .strikethroughStyle: 0,
                .spellingState: 0,
                .backgroundColor: NSColor.clear
            ], to: textStorage, range: horizontalRule.lineRange, limitedTo: targetRange)
            addAttributes(horizontalRuleMarkerAttributes(isActive: isActive), to: textStorage, range: horizontalRule.markerRange, limitedTo: targetRange)
        }
    }

    private func applyTaskCheckboxes(
        to textStorage: NSTextStorage,
        targetRange: NSRange,
        protectedRanges: [NSRange]
    ) {
        applyGroups(
            pattern: #"(?m)^[ \t]*(?:[-*+]|\d+\.)[ \t]+(\[[ xX]\])"#,
            to: textStorage,
            targetRange: targetRange,
            protectedRanges: protectedRanges,
            groups: [
                (1, [
                    .font: CurrentTheme.editorBoldFont(configuration: configuration),
                    .foregroundColor: CurrentTheme.mutedTextColor
                ])
            ]
        )
        applyGroups(
            pattern: #"(?m)^[ \t]*(?:[-*+]|\d+\.)[ \t]+(\[[xX]\])"#,
            to: textStorage,
            targetRange: targetRange,
            protectedRanges: protectedRanges,
            groups: [
                (1, [
                    .font: CurrentTheme.editorBoldFont(configuration: configuration),
                    .foregroundColor: CurrentTheme.accentColor
                ])
            ]
        )
    }

    private func applyListParagraphStyles(
        model: MarkdownEditorRenderModel,
        to textStorage: NSTextStorage,
        targetRange: NSRange,
        protectedRanges: [NSRange]
    ) {
        let string = textStorage.string as NSString
        for list in model.lists {
            guard rangesIntersect(list.lineRange, targetRange) else { continue }
            guard !intersectsProtected(list.lineRange, protectedRanges: protectedRanges) else { continue }
            let prefix = string.substring(with: list.prefixRange)
            addAttributes(
                [.paragraphStyle: listParagraphStyle(prefix: prefix)],
                to: textStorage,
                range: list.lineRange,
                limitedTo: targetRange
            )
        }
    }

    private func intersectsProtected(_ range: NSRange, protectedRanges: [NSRange]) -> Bool {
        protectedRanges.contains { protectedRange in
            NSIntersectionRange(range, protectedRange).length > 0
        }
    }

    private func decorationRange(around range: NSRange, in text: String) -> NSRange {
        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)
        guard fullRange.length > 0 else { return fullRange }

        var clampedLocation = min(max(0, range.location), nsText.length)
        var clampedLength = min(max(0, range.length), nsText.length - clampedLocation)
        if clampedLength == 0 {
            if clampedLocation == nsText.length, clampedLocation > 0 {
                clampedLocation -= 1
            }
            clampedLength = 1
        }

        let editedLineRange = nsText.lineRange(for: NSRange(location: clampedLocation, length: clampedLength))
        var expandedRange = editedLineRange

        if expandedRange.location > 0 {
            let previousLineRange = nsText.lineRange(for: NSRange(location: expandedRange.location - 1, length: 0))
            expandedRange = NSUnionRange(expandedRange, previousLineRange)
        }

        let nextLocation = NSMaxRange(expandedRange)
        if nextLocation < nsText.length {
            let nextLineRange = nsText.lineRange(for: NSRange(location: nextLocation, length: 0))
            expandedRange = NSUnionRange(expandedRange, nextLineRange)
        }

        for fencedRange in MarkdownBlockRendering.fencedCodeBlockRanges(in: text) where rangesIntersect(fencedRange, expandedRange) {
            expandedRange = NSUnionRange(expandedRange, fencedRange)
        }

        return NSIntersectionRange(expandedRange, fullRange)
    }

    private func addAttributes(
        _ attributes: [NSAttributedString.Key: Any],
        to textStorage: NSTextStorage,
        range: NSRange,
        limitedTo targetRange: NSRange
    ) {
        let rangeToApply = NSIntersectionRange(range, targetRange)
        guard rangeToApply.length > 0 else { return }
        textStorage.addAttributes(attributes, range: rangeToApply)
    }

    private func rangesIntersect(_ lhs: NSRange, _ rhs: NSRange) -> Bool {
        NSIntersectionRange(lhs, rhs).length > 0
    }
}
