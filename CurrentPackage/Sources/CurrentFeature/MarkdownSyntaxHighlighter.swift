import AppKit

final class MarkdownSyntaxHighlighter {
    struct Context {
        var streamLinks: [MarkdownStreamLinks.Link] = []
        var width: CGFloat
        var documentURL: URL?
    }
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
        CurrentTheme.editorCodeFont(configuration: configuration)
    }

    func highlight(_ textStorage: NSTextStorage, selectedRange: NSRange? = nil) {
        let fullRange = NSRange(location: 0, length: textStorage.length)
        guard fullRange.length > 0 else { return }

        highlight(textStorage, in: fullRange, model: model(for: textStorage), selectedRange: selectedRange)
    }

    func highlightAroundEditedRange(
        _ textStorage: NSTextStorage,
        editedRange: NSRange?,
        selectedRange: NSRange? = nil
    ) {
        let fullRange = NSRange(location: 0, length: textStorage.length)
        guard fullRange.length > 0 else { return }

        let model = model(for: textStorage)
        let targetRange = model.decorationRange(around: editedRange ?? fullRange)
        guard targetRange.length > 0 else { return }

        highlight(textStorage, in: targetRange, model: model, selectedRange: selectedRange)
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
        highlight(textStorage, in: clampedRange, model: model(for: textStorage), selectedRange: newSelectedRange)
    }

    private func model(for storage: NSTextStorage) -> MarkdownEditorRenderModel {
        (storage as? MarkdownTextStorage)?.renderModel ?? MarkdownEditorRenderModel(text: storage.string)
    }

    func highlight(_ textStorage: NSTextStorage, in targetRange: NSRange, model: MarkdownEditorRenderModel, selectedRange: NSRange?, sourceMode: Bool = false, context: Context? = nil) {
        let policy = MarkdownLiveRenderPolicy(model: model, selectedRange: selectedRange)
        let markdownStorage = textStorage as? MarkdownTextStorage
        let context = context ?? Context(streamLinks: markdownStorage?.resolvedStreamLinks ?? [],
                                         width: markdownStorage?.renderWidth ?? CGFloat(configuration.contentWidth),
                                         documentURL: markdownStorage?.documentURL)
        // Markdown owns persistent source attributes. Temporary attributes
        // belong to native find, spelling, and input-method presentation;
        // removing them here can force layout inside a native undo transaction.
        textStorage.beginEditing()
        // Text storage publishes attribute invalidation when its outer editing
        // transaction closes. Calling invalidateDisplay here can force glyph
        // generation while NSTextView is still inside beginEditing/endEditing.
        defer {
            textStorage.fixFontAttribute(in: targetRange)
            textStorage.endEditing()
        }
        var base = baseAttributes()
        if sourceMode { base[.font] = codeFont }
        textStorage.setAttributes(base, range: targetRange)
        guard !sourceMode else { return }

        let protectedRanges = applyProtected(model.protectedRanges, to: textStorage, attributes: [
            .font: codeFont,
            .foregroundColor: codeColor,
            .currentCodeBlock: true
        ], targetRange: targetRange)
        for fence in model.fences {
            let active = policy.isActive(fence.range)
            let paragraph = NSMutableParagraphStyle()
            paragraph.minimumLineHeight = CurrentTheme.editorLineHeight(configuration: configuration)
            paragraph.maximumLineHeight = paragraph.minimumLineHeight
            paragraph.firstLineHeadIndent = 12
            paragraph.headIndent = 12
            addAttributes([.paragraphStyle: paragraph], to: textStorage, range: fence.range, limitedTo: targetRange)
            for boundary in [fence.openingRange, fence.closingRange].compactMap({ $0 }) {
                if active {
                    addAttributes([.foregroundColor: syntaxColor], to: textStorage, range: boundary, limitedTo: targetRange)
                } else {
                    let padding = NSMutableParagraphStyle()
                    padding.minimumLineHeight = 8; padding.maximumLineHeight = 8
                    addAttributes(hiddenSyntaxAttributes(collapsesWidth: false).merging([
                        .paragraphStyle: padding, .currentFenceBoundary: true
                    ]) { _, new in new }, to: textStorage, range: boundary, limitedTo: targetRange)
                }
            }
        }

        applyHeadingLines(model: model, policy: policy, to: textStorage, targetRange: targetRange, protectedRanges: protectedRanges)
        applyHeadingSeparators(model: model, policy: policy, to: textStorage, targetRange: targetRange)
        applyGroups(
            pattern: #"(?m)^([ \t]*>[ \t]?)(.*)$"#,
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
        applyTaskCheckboxes(model: model, policy: policy, to: textStorage, targetRange: targetRange)
        applyListParagraphStyles(model: model, policy: policy, to: textStorage, targetRange: targetRange, protectedRanges: protectedRanges)
        applyQuotes(model: model, policy: policy, to: textStorage, targetRange: targetRange)
        applyInlineSpans(model: model, policy: policy, to: textStorage, targetRange: targetRange)
        applyStreamLinks(context.streamLinks, to: textStorage, targetRange: targetRange)
        applyHorizontalRules(model: model, policy: policy, to: textStorage, targetRange: targetRange, protectedRanges: protectedRanges)
        MarkdownRichBlocks.apply(model.richBlocks, to: textStorage, targetRange: targetRange, selectedRange: selectedRange,
                                 width: context.width, configuration: configuration, documentURL: context.documentURL)
    }

    func clearTemporaryDecorations(_ textStorage: NSTextStorage, in range: NSRange? = nil) {
        let fullRange = range ?? NSRange(location: 0, length: textStorage.length)
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
            .backgroundColor,
            .link
        ]
    }

    private func listParagraphStyle(prefixWidth: CGFloat) -> NSMutableParagraphStyle {
        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = CurrentTheme.editorLineHeight(configuration: configuration)
        paragraph.maximumLineHeight = CurrentTheme.editorLineHeight(configuration: configuration)
        paragraph.lineBreakMode = .byWordWrapping
        paragraph.headIndent = ceil(prefixWidth)
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

    private func applyHeadingSeparators(
        model: MarkdownEditorRenderModel,
        policy: MarkdownLiveRenderPolicy,
        to textStorage: NSTextStorage,
        targetRange: NSRange
    ) {
        for separator in model.headingSeparators {
            guard rangesIntersect(separator, targetRange), !policy.isActive(separator),
                  !intersectsProtected(separator, protectedRanges: model.protectedRanges) else { continue }
            // A single Markdown separator needs less space than an editable
            // body line. Keep the source and full-height active caret intact.
            let paragraph = NSMutableParagraphStyle()
            paragraph.minimumLineHeight = 6
            paragraph.maximumLineHeight = 6
            addAttributes([.paragraphStyle: paragraph], to: textStorage, range: separator, limitedTo: targetRange)
        }
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

        }
        return ranges
    }

    private static let groupPatterns: [String: NSRegularExpression] = {
        let patterns = [
            #"(?m)^([ \t]*>[ \t]?)(.*)$"#,
            #"(?m)^([ \t]*(?:[-*+]|\d+\.)(?:[ \t]+\[[ xX]\])?[ \t]+)"#,
            #"(?m)^[ \t]*(?:[-*+]|\d+\.)[ \t]+(\[[ xX]\])"#,
            #"(?m)^[ \t]*(?:[-*+]|\d+\.)[ \t]+(\[[xX]\])"#
        ]
        return Dictionary(uniqueKeysWithValues: patterns.map { ($0, try! NSRegularExpression(pattern: $0)) })
    }()

    private func applyGroups(
        pattern: String,
        to textStorage: NSTextStorage,
        targetRange: NSRange,
        protectedRanges: [NSRange],
        groups: [(Int, [NSAttributedString.Key: Any])]
    ) {
        guard let regex = Self.groupPatterns[pattern] else { return }
        regex.enumerateMatches(in: textStorage.string, range: targetRange) { match, _, _ in
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
        policy: MarkdownLiveRenderPolicy,
        to textStorage: NSTextStorage,
        targetRange: NSRange,
        protectedRanges: [NSRange]
    ) {
        let source = model.text as NSString
        for heading in model.headings {
            guard rangesIntersect(heading.lineRange, targetRange) else { continue }
            guard !intersectsProtected(heading.lineRange, protectedRanges: protectedRanges) else { continue }
            let headingFont = CurrentTheme.editorHeadingFont(level: heading.level, configuration: configuration)
            let prefix = source.substring(with: heading.prefixRange)
            let prefixWidth = ceil(prefix.size(withAttributes: [.font: headingFont]).width)

            addAttributes(
                [
                    .font: headingFont,
                    .foregroundColor: CurrentTheme.primaryTextColor,
                    .paragraphStyle: headingParagraphStyle(
                        level: heading.level,
                        prefixWidth: policy.isActive(heading.lineRange) ? prefixWidth : 0
                    )
                ],
                to: textStorage,
                range: heading.lineRange,
                limitedTo: targetRange
            )
            // Keep a native glyph at the paragraph start. Nulling this prefix
            // lets incremental layout attach it to the preceding paragraph and
            // reuse that paragraph's baseline after typing or deleting emoji.
            addAttributes(
                (policy.isActive(heading.lineRange) ? revealedSyntaxAttributes() : hiddenSyntaxAttributes(collapsesWidth: false)).merging([
                    .font: policy.isActive(heading.lineRange) ? headingFont : NSFont.systemFont(ofSize: 0.01),
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
                var attributes: [NSAttributedString.Key: Any] = [.foregroundColor: CurrentTheme.accentColor]
                if let syntax = span.syntaxRanges.last {
                    let raw = (model.text as NSString).substring(with: syntax)
                    if raw.hasPrefix("]("), raw.hasSuffix(")") {
                        let destination = String(raw.dropFirst(2).dropLast())
                        if let url = URL(string: destination), ["https", "http", "mailto"].contains(url.scheme?.lowercased() ?? "") { attributes[.link] = url }
                    }
                }
                addAttributes(attributes, to: textStorage, range: span.contentRange, limitedTo: targetRange)
            }
        }
    }

    private func applyStreamLinks(_ links: [MarkdownStreamLinks.Link], to storage: NSTextStorage, targetRange: NSRange) {
        for link in links where NSIntersectionRange(link.sourceRange, targetRange).length > 0 {
            for range in [NSRange(location: link.sourceRange.location, length: 2),
                          NSRange(location: NSMaxRange(link.sourceRange) - 2, length: 2)] {
                addAttributes([.foregroundColor: syntaxColor], to: storage, range: range, limitedTo: targetRange)
            }
            if let url = URL(string: "inkpad-stream://\(link.target.id.uuidString)") {
                addAttributes([.link: url, .foregroundColor: CurrentTheme.accentColor], to: storage,
                              range: link.labelRange, limitedTo: targetRange)
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

    private func applyQuotes(model: MarkdownEditorRenderModel, policy: MarkdownLiveRenderPolicy,
                             to storage: NSTextStorage, targetRange: NSRange) {
        for quote in model.quotes where rangesIntersect(quote.lineRange, targetRange) {
            let paragraph = NSMutableParagraphStyle()
            paragraph.minimumLineHeight = CurrentTheme.editorLineHeight(configuration: configuration)
            paragraph.maximumLineHeight = paragraph.minimumLineHeight
            paragraph.firstLineHeadIndent = 8
            paragraph.headIndent = 22
            addAttributes([.currentQuote: true, .paragraphStyle: paragraph, .foregroundColor: CurrentTheme.secondaryTextColor],
                          to: storage, range: quote.lineRange, limitedTo: targetRange)
            if !policy.isActive(quote.lineRange) {
                addAttributes(hiddenSyntaxAttributes(collapsesWidth: false), to: storage, range: quote.prefixRange, limitedTo: targetRange)
            }
        }
    }

    private func applyTaskCheckboxes(model: MarkdownEditorRenderModel, policy: MarkdownLiveRenderPolicy,
                                    to storage: NSTextStorage, targetRange: NSRange) {
        let source = storage.string as NSString
        for list in model.lists where rangesIntersect(list.lineRange, targetRange) {
            let prefix = source.substring(with: list.prefixRange) as NSString
            let opening = prefix.range(of: "[")
            if opening.location != NSNotFound, opening.location + 3 <= prefix.length {
                let marker = NSRange(location: list.prefixRange.location + opening.location, length: 3)
                let checked = source.character(at: marker.location + 1) != 32
                var attrs: [NSAttributedString.Key: Any] = [.currentTaskCheckbox: checked, .foregroundColor: checked ? CurrentTheme.accentColor : syntaxColor]
                if !policy.isActive(list.lineRange) {
                    attrs[.foregroundColor] = NSColor.clear
                    // Keep [ ], [x], and [X] in one fixed marker gutter even
                    // when the surrounding paragraph uses proportional type.
                    attrs[.font] = codeFont
                    var indentation = 0
                    while indentation < opening.location, prefix.character(at: indentation) == 32 || prefix.character(at: indentation) == 9 { indentation += 1 }
                    // Retain a near-zero leading glyph so TextKit recognizes
                    // the paragraph's first line instead of applying the
                    // wrapped-line indent after a run of null glyphs.
                    var leading = hiddenSyntaxAttributes(collapsesWidth: false)
                    leading[.font] = NSFont.systemFont(ofSize: 0.01)
                    addAttributes(leading, to: storage,
                                  range: NSRange(location: list.prefixRange.location + indentation, length: opening.location - indentation), limitedTo: targetRange)
                }
                addAttributes(attrs, to: storage, range: marker, limitedTo: targetRange)
            } else if !policy.isActive(list.lineRange) {
                let marker = prefix.rangeOfCharacter(from: CharacterSet(charactersIn: "-*+"))
                if marker.location != NSNotFound {
                    let advance = (" " as NSString).size(withAttributes: [.font: codeFont]).width
                    addAttributes([.currentListBullet: true, .foregroundColor: NSColor.clear,
                                   .font: codeFont, .kern: advance * 2], to: storage,
                                  range: NSRange(location: list.prefixRange.location + marker.location, length: 1), limitedTo: targetRange)
                }
            }
        }
    }

    private func applyListParagraphStyles(
        model: MarkdownEditorRenderModel,
        policy: MarkdownLiveRenderPolicy,
        to textStorage: NSTextStorage,
        targetRange: NSRange,
        protectedRanges: [NSRange]
    ) {
        let source = model.text as NSString
        for list in model.lists {
            guard rangesIntersect(list.lineRange, targetRange) else { continue }
            guard !intersectsProtected(list.lineRange, protectedRanges: protectedRanges) else { continue }
            var prefixWidth: CGFloat = 0
            textStorage.enumerateAttributes(in: list.prefixRange) { attributes, range, _ in
                guard attributes[.currentCollapsedMarkdownSyntax] as? Bool != true else { return }
                prefixWidth += source.substring(with: range)
                    .size(withAttributes: attributes).width
            }
            addAttributes(
                [.paragraphStyle: listParagraphStyle(prefixWidth: prefixWidth)],
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
