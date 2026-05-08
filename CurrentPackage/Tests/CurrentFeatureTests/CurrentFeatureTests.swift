import AppKit
import Testing
@testable import CurrentFeature

// This target stays XCTest-free so `swift test` can compile on machines that
// only have Command Line Tools installed.
func currentFeatureTestsCompile() {
    _ = StreamStore.defaultStreamName
}

@Test
func minimizedSearchMatchesExpandTemporarily() {
    let document = DayDocument(
        streamID: UUID(),
        date: Date(timeIntervalSince1970: 0),
        fileURL: URL(fileURLWithPath: "/tmp/day.md"),
        text: "needle notes"
    )
    let minimizedDayIDs = Set([document.id])

    #expect(TimelineDayPresentation.isEffectivelyMinimized(
        document: document,
        isToday: false,
        minimizedDayIDs: minimizedDayIDs,
        searchQuery: ""
    ))
    #expect(!TimelineDayPresentation.isEffectivelyMinimized(
        document: document,
        isToday: false,
        minimizedDayIDs: minimizedDayIDs,
        searchQuery: "needle"
    ))
    #expect(TimelineDayPresentation.isEffectivelyMinimized(
        document: document,
        isToday: false,
        minimizedDayIDs: minimizedDayIDs,
        searchQuery: "missing"
    ))
    #expect(!TimelineDayPresentation.isEffectivelyMinimized(
        document: document,
        isToday: true,
        minimizedDayIDs: minimizedDayIDs,
        searchQuery: ""
    ))
}

@Test
func highlighterUnderlinesOnlyExplicitUnderlineContent() {
    let text = "<u>sdhusiafsd</u>\nadfjkhsd"
    let storage = highlightedStorage(text)
    let nsText = text as NSString
    let openTagIndex = nsText.range(of: "<u>").location
    let contentIndex = nsText.range(of: "sdhusiafsd").location
    let newlineIndex = nsText.range(of: "\n").location
    let followingLineIndex = nsText.range(of: "adfjkhsd").location

    #expect(boolAttribute(.currentHiddenMarkdownSyntax, in: storage, at: openTagIndex))
    #expect(intAttribute(.underlineStyle, in: storage, at: contentIndex) == NSUnderlineStyle.single.rawValue)
    #expect(!boolAttribute(.currentHiddenMarkdownSyntax, in: storage, at: contentIndex))
    #expect(intAttribute(.underlineStyle, in: storage, at: newlineIndex) == 0)
    #expect(intAttribute(.underlineStyle, in: storage, at: followingLineIndex) == 0)
    #expect(backgroundIsClear(in: storage, at: newlineIndex))
    #expect(backgroundIsClear(in: storage, at: followingLineIndex))
}

@Test
func highlighterDoesNotAddUnderlineOrBackgroundToListLines() {
    let text = "1. fdsjflkdf=\n2. fdsfs\n\n<u>sdhusiafsd</u>\nadfjkhsd"
    let storage = highlightedStorage(text)
    let nsText = text as NSString
    let firstListTextIndex = nsText.range(of: "fdsjflkdf=").location
    let secondListTextIndex = nsText.range(of: "fdsfs").location
    let firstNewlineIndex = nsText.range(of: "\n").location

    for index in [firstListTextIndex, secondListTextIndex, firstNewlineIndex] {
        #expect(intAttribute(.underlineStyle, in: storage, at: index) == 0)
        #expect(intAttribute(.strikethroughStyle, in: storage, at: index) == 0)
        #expect(backgroundIsClear(in: storage, at: index))
    }
}

@Test
func highlighterClearsStaleDecorationAttributes() {
    let storage = NSTextStorage(string: "plain")
    storage.addAttributes(
        [
            .underlineStyle: NSUnderlineStyle.single.rawValue,
            .strikethroughStyle: NSUnderlineStyle.single.rawValue,
            .backgroundColor: NSColor.systemBlue,
            .currentHiddenMarkdownSyntax: true,
            .currentCollapsedMarkdownSyntax: true,
            .currentHorizontalRule: true,
            .currentHorizontalRuleMarker: true,
            .spellingState: 1,
            .markedClauseSegment: 0
        ],
        range: NSRange(location: 0, length: storage.length)
    )

    MarkdownSyntaxHighlighter().highlight(storage)

    #expect(intAttribute(.underlineStyle, in: storage, at: 0) == 0)
    #expect(intAttribute(.strikethroughStyle, in: storage, at: 0) == 0)
    #expect(backgroundIsClear(in: storage, at: 0))
    #expect(!boolAttribute(.currentHiddenMarkdownSyntax, in: storage, at: 0))
    #expect(!boolAttribute(.currentCollapsedMarkdownSyntax, in: storage, at: 0))
    #expect(!boolAttribute(.currentHorizontalRule, in: storage, at: 0))
    #expect(!boolAttribute(.currentHorizontalRuleMarker, in: storage, at: 0))
    #expect(intAttribute(.spellingState, in: storage, at: 0) == 0)
    #expect(storage.attribute(.markedClauseSegment, at: 0, effectiveRange: nil) == nil)
}

@Test
func highlighterClearsTemporaryDecorationAttributes() {
    let storage = NSTextStorage(string: "plain")
    let layoutManager = NSLayoutManager()
    let textContainer = NSTextContainer(size: NSSize(width: 200, height: 200))
    layoutManager.addTextContainer(textContainer)
    storage.addLayoutManager(layoutManager)

    let range = NSRange(location: 0, length: storage.length)
    layoutManager.addTemporaryAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, forCharacterRange: range)
    layoutManager.addTemporaryAttribute(.underlineColor, value: NSColor.systemBlue, forCharacterRange: range)
    layoutManager.addTemporaryAttribute(.spellingState, value: 1, forCharacterRange: range)
    layoutManager.addTemporaryAttribute(.markedClauseSegment, value: 0, forCharacterRange: range)

    MarkdownSyntaxHighlighter().highlight(storage)

    #expect(layoutManager.temporaryAttribute(.underlineStyle, atCharacterIndex: 0, effectiveRange: nil) == nil)
    #expect(layoutManager.temporaryAttribute(.underlineColor, atCharacterIndex: 0, effectiveRange: nil) == nil)
    #expect(layoutManager.temporaryAttribute(.spellingState, atCharacterIndex: 0, effectiveRange: nil) == nil)
    #expect(layoutManager.temporaryAttribute(.markedClauseSegment, atCharacterIndex: 0, effectiveRange: nil) == nil)
}

@Test
func highlighterHidesInlineMarkdownSyntaxAndStylesContent() {
    let text = "**bold** and [docs](https://example.com) and `code`"
    let storage = highlightedStorage(text)
    let nsText = text as NSString
    let boldMarkerIndex = nsText.range(of: "**").location
    let boldContentIndex = nsText.range(of: "bold").location
    let linkMarkerIndex = nsText.range(of: "[").location
    let linkContentIndex = nsText.range(of: "docs").location
    let codeMarkerIndex = nsText.range(of: "`").location
    let codeContentIndex = nsText.range(of: "code").location

    #expect(boolAttribute(.currentHiddenMarkdownSyntax, in: storage, at: boldMarkerIndex))
    #expect(boolAttribute(.currentCollapsedMarkdownSyntax, in: storage, at: boldMarkerIndex))
    #expect(!boolAttribute(.currentHiddenMarkdownSyntax, in: storage, at: boldContentIndex))
    #expect(storage.attribute(.font, at: boldContentIndex, effectiveRange: nil) is NSFont)

    #expect(boolAttribute(.currentHiddenMarkdownSyntax, in: storage, at: linkMarkerIndex))
    #expect(!boolAttribute(.currentHiddenMarkdownSyntax, in: storage, at: linkContentIndex))
    #expect(storage.attribute(.foregroundColor, at: linkContentIndex, effectiveRange: nil) as? NSColor == CurrentTheme.accentColor)

    #expect(boolAttribute(.currentHiddenMarkdownSyntax, in: storage, at: codeMarkerIndex))
    #expect(!boolAttribute(.currentHiddenMarkdownSyntax, in: storage, at: codeContentIndex))
    #expect(!backgroundIsClear(in: storage, at: codeContentIndex))
}

@Test
func liveModeRevealsMarkdownSyntaxInActiveBlock() {
    let text = "# **Heading**\nPlain"
    let nsText = text as NSString
    let activeStorage = highlightedStorage(
        text,
        selectedRange: NSRange(location: nsText.range(of: "Heading").location, length: 0)
    )
    let inactiveStorage = highlightedStorage(text)
    let headingPrefixIndex = 0
    let boldMarkerIndex = nsText.range(of: "**").location

    #expect(!boolAttribute(.currentHiddenMarkdownSyntax, in: inactiveStorage, at: headingPrefixIndex))
    #expect(boolAttribute(.currentHiddenMarkdownSyntax, in: inactiveStorage, at: boldMarkerIndex))
    #expect(!boolAttribute(.currentHiddenMarkdownSyntax, in: activeStorage, at: headingPrefixIndex))
    #expect(!boolAttribute(.currentHiddenMarkdownSyntax, in: activeStorage, at: boldMarkerIndex))
    #expect(!foregroundIsClear(in: inactiveStorage, at: headingPrefixIndex))
    #expect(!foregroundIsClear(in: activeStorage, at: headingPrefixIndex))
    #expect(!foregroundIsClear(in: activeStorage, at: boldMarkerIndex))
}

@Test
func liveModeRevealsOnlyActiveHorizontalRuleMarkers() {
    let text = "---\n"
    let inactiveStorage = highlightedStorage(text)
    let activeRuleStorage = highlightedStorage(text, selectedRange: NSRange(location: 0, length: 0))
    let activeFollowingLineStorage = highlightedStorage(text, selectedRange: NSRange(location: (text as NSString).length, length: 0))

    #expect(boolAttribute(.currentHorizontalRule, in: inactiveStorage, at: 0))
    #expect(foregroundIsClear(in: inactiveStorage, at: 0))
    #expect(!foregroundIsClear(in: activeRuleStorage, at: 0))
    #expect(foregroundIsClear(in: activeFollowingLineStorage, at: 0))
}

@Test
func highlighterPreservesNestedInlineMarkdownStyles() {
    let text = "**_important_** and **<u>under</u>**"
    let storage = highlightedStorage(text)
    let nsText = text as NSString
    let italicMarkerIndex = nsText.range(of: "_").location
    let importantContentIndex = nsText.range(of: "important").location
    let underlineMarkerIndex = nsText.range(of: "<u>").location
    let underlineContentIndex = nsText.range(of: "under").location

    #expect(boolAttribute(.currentHiddenMarkdownSyntax, in: storage, at: italicMarkerIndex))
    #expect(!boolAttribute(.currentHiddenMarkdownSyntax, in: storage, at: importantContentIndex))
    #expect(storage.attribute(.obliqueness, at: importantContentIndex, effectiveRange: nil) != nil)
    #expect(boolAttribute(.currentHiddenMarkdownSyntax, in: storage, at: underlineMarkerIndex))
    #expect(intAttribute(.underlineStyle, in: storage, at: underlineContentIndex) == NSUnderlineStyle.single.rawValue)
}

@Test
func highlighterCollapsesRepeatedSameKindInlineMarkers() {
    let text = "****bold**** and <u><u>under</u></u>"
    let storage = highlightedStorage(text)
    let nsText = text as NSString
    let firstBoldMarkerIndex = nsText.range(of: "****").location
    let boldContentIndex = nsText.range(of: "bold").location
    let underlineMarkerIndex = nsText.range(of: "<u><u>").location
    let underlineContentIndex = nsText.range(of: "under").location

    #expect(boolAttribute(.currentHiddenMarkdownSyntax, in: storage, at: firstBoldMarkerIndex))
    #expect(!boolAttribute(.currentHiddenMarkdownSyntax, in: storage, at: boldContentIndex))
    #expect(storage.attribute(.font, at: boldContentIndex, effectiveRange: nil) is NSFont)
    #expect(boolAttribute(.currentHiddenMarkdownSyntax, in: storage, at: underlineMarkerIndex))
    #expect(intAttribute(.underlineStyle, in: storage, at: underlineContentIndex) == NSUnderlineStyle.single.rawValue)
}

@Test
func highlighterMarksHorizontalRulesForCustomDrawing() {
    let text = "Before\n---\nAfter"
    let storage = highlightedStorage(text)
    let nsText = text as NSString
    let ruleIndex = nsText.range(of: "---").location
    let beforeIndex = nsText.range(of: "Before").location

    #expect(boolAttribute(.currentHorizontalRule, in: storage, at: ruleIndex))
    #expect(boolAttribute(.currentHorizontalRuleMarker, in: storage, at: ruleIndex))
    #expect(!boolAttribute(.currentHiddenMarkdownSyntax, in: storage, at: ruleIndex))
    #expect(foregroundIsClear(in: storage, at: ruleIndex))
    #expect(intAttribute(.underlineStyle, in: storage, at: ruleIndex) == 0)
    #expect(intAttribute(.strikethroughStyle, in: storage, at: ruleIndex) == 0)
    #expect(intAttribute(.spellingState, in: storage, at: ruleIndex) == 0)
    #expect(backgroundIsClear(in: storage, at: ruleIndex))
    #expect(!boolAttribute(.currentHorizontalRule, in: storage, at: beforeIndex))
    #expect(!boolAttribute(.currentHorizontalRuleMarker, in: storage, at: beforeIndex))
}

@Test
func highlighterKeepsUncommittedEOFHorizontalRuleVisible() {
    let text = "---"
    let storage = highlightedStorage(text)

    #expect(!boolAttribute(.currentHorizontalRule, in: storage, at: 0))
    #expect(!boolAttribute(.currentHorizontalRuleMarker, in: storage, at: 0))
    #expect(!boolAttribute(.currentHiddenMarkdownSyntax, in: storage, at: 0))
    #expect(!foregroundIsClear(in: storage, at: 0))
}

@Test
func highlighterKeepsHeadingSyntaxOnHeadingMetrics() {
    let text = "# **Heading**"
    let storage = highlightedStorage(text)
    let nsText = text as NSString
    let prefixIndex = 0
    let boldMarkerIndex = nsText.range(of: "**").location
    let contentIndex = nsText.range(of: "Heading").location
    let headingFont = CurrentTheme.editorHeadingFont(level: 1, configuration: .default)
    let prefixFont = storage.attribute(.font, at: prefixIndex, effectiveRange: nil) as? NSFont
    let boldMarkerFont = storage.attribute(.font, at: boldMarkerIndex, effectiveRange: nil) as? NSFont
    let contentFont = storage.attribute(.font, at: contentIndex, effectiveRange: nil) as? NSFont

    #expect(!boolAttribute(.currentHiddenMarkdownSyntax, in: storage, at: prefixIndex))
    #expect(!boolAttribute(.currentCollapsedMarkdownSyntax, in: storage, at: prefixIndex))
    #expect(boolAttribute(.currentHiddenMarkdownSyntax, in: storage, at: boldMarkerIndex))
    #expect(boolAttribute(.currentCollapsedMarkdownSyntax, in: storage, at: boldMarkerIndex))
    #expect(prefixFont?.pointSize == headingFont.pointSize)
    #expect(boldMarkerFont?.pointSize == headingFont.pointSize)
    #expect(contentFont?.pointSize == headingFont.pointSize)
}

@Test
func highlighterKeepsEmptyHeadingBoundaryOnHeadingMetrics() {
    let text = "# \nBody"
    let storage = highlightedStorage(text)
    let newlineIndex = ("# " as NSString).length
    let bodyIndex = (text as NSString).range(of: "Body").location
    let headingFont = CurrentTheme.editorHeadingFont(level: 1, configuration: .default)
    let newlineFont = storage.attribute(.font, at: newlineIndex, effectiveRange: nil) as? NSFont
    let bodyFont = storage.attribute(.font, at: bodyIndex, effectiveRange: nil) as? NSFont
    let newlineParagraph = storage.attribute(.paragraphStyle, at: newlineIndex, effectiveRange: nil) as? NSParagraphStyle

    #expect(newlineFont?.pointSize == headingFont.pointSize)
    #expect(bodyFont?.pointSize == CurrentTheme.editorFont(configuration: .default).pointSize)
    #expect(newlineParagraph?.minimumLineHeight == CurrentTheme.editorHeadingLineHeight(level: 1, configuration: .default))
}

@Test
func horizontalRuleDisplayStateTracksCommittedLines() {
    #expect(MarkdownBlockRendering.horizontalRuleDisplayState(in: "---", at: 3) == .editingMarker(
        MarkdownBlockRendering.HorizontalRuleLine(lineRange: NSRange(location: 0, length: 3), markerRange: NSRange(location: 0, length: 3))
    ))
    #expect(MarkdownBlockRendering.horizontalRuleDisplayState(in: "---\n", at: 3) == .committedDivider(
        MarkdownBlockRendering.HorizontalRuleLine(lineRange: NSRange(location: 0, length: 4), markerRange: NSRange(location: 0, length: 3))
    ))
}

@Test
func markdownLayoutManagerDrawsHorizontalRulesFromRawLinesOnly() {
    let staleText = "2. not a rule"
    let staleStorage = NSTextStorage(string: staleText)
    let staleRange = NSRange(location: 0, length: (staleText as NSString).length)
    staleStorage.addAttribute(.currentHorizontalRule, value: true, range: staleRange)

    #expect(MarkdownLayoutManager.horizontalRuleLineRangeForDrawing(
        in: staleStorage.string,
        characterRange: staleRange
    ) == nil)

    let ruleText = "Before\n---\nAfter"
    let ruleRange = NSRange(location: "Before\n".utf16.count, length: 3)

    #expect(MarkdownLayoutManager.horizontalRuleLineRangeForDrawing(
        in: ruleText,
        characterRange: ruleRange
    ) == NSRange(location: "Before\n".utf16.count, length: 4))

    let ruleWithTrailingNewline = "---\n"
    #expect(MarkdownLayoutManager.horizontalRuleLineRangeForDrawing(
        in: ruleWithTrailingNewline,
        characterRange: NSRange(location: 0, length: 3)
    ) == NSRange(location: 0, length: 4))
    #expect(MarkdownLayoutManager.horizontalRuleLineRangeForDrawing(
        in: ruleWithTrailingNewline,
        characterRange: NSRange(location: 3, length: 1)
    ) == NSRange(location: 0, length: 4))
    let ruleWithBlankLine = "---\n\n"
    #expect(MarkdownLayoutManager.horizontalRuleLineRangeForDrawing(
        in: ruleWithBlankLine,
        characterRange: NSRange(location: 0, length: 3)
    ) == NSRange(location: 0, length: 4))
    #expect(MarkdownLayoutManager.horizontalRuleLineRangeForDrawing(
        in: ruleWithBlankLine,
        characterRange: NSRange(location: 3, length: 1)
    ) == NSRange(location: 0, length: 4))
    #expect(MarkdownLayoutManager.horizontalRuleLineRangeForDrawing(
        in: ruleWithBlankLine,
        characterRange: NSRange(location: 4, length: 1)
    ) == nil)
    #expect(MarkdownLayoutManager.horizontalRuleLineRangeForDrawing(
        in: "---",
        characterRange: NSRange(location: 0, length: 3)
    ) == nil)
}

@Test
func markdownLayoutManagerAnchorsHorizontalRuleToLineFragment() {
    let initialY = horizontalRuleStrokeY(for: "---\n")
    let typingNextLineY = horizontalRuleStrokeY(for: "---\nA")

    #expect(abs(initialY - typingNextLineY) < 0.5)
}

@Test
func horizontalRuleMarkerUsesStableTextKitMetrics() {
    let initial = horizontalRuleLayoutMetrics(for: "---\n")
    let typingNextLine = horizontalRuleLayoutMetrics(for: "---\nA")

    #expect(abs(initial.lineRect.minY - typingNextLine.lineRect.minY) < 0.5)
    #expect(abs(initial.lineRect.height - typingNextLine.lineRect.height) < 0.5)
    #expect(abs(initial.strokeY - typingNextLine.strokeY) < 0.5)
    #expect(initial.lineRect.height >= CurrentTheme.editorLineHeight(configuration: .default))
}

@Test
func markdownEditorPlainTypingAttributesClearEditorMetadata() {
    let attributes = MarkdownEditorView.plainTypingAttributes(configuration: .default)

    #expect(attributes[.currentHorizontalRule] as? Bool == false)
    #expect(attributes[.currentHorizontalRuleMarker] as? Bool == false)
    #expect(attributes[.currentHiddenMarkdownSyntax] as? Bool == false)
    #expect(attributes[.currentCollapsedMarkdownSyntax] as? Bool == false)
    #expect((attributes[.spellingState] as? Int) == 0)
    #expect((attributes[.underlineStyle] as? Int) == 0)
}

@Test
func markdownLayoutManagerCollapsesHiddenSyntaxWidth() {
    let hiddenWidth = measuredWidth(for: highlightedStorage("**bold**"))
    let visibleContentWidth = measuredWidth(for: NSTextStorage(
        string: "bold",
        attributes: [.font: CurrentTheme.editorBoldFont(configuration: .default)]
    ))
    let rawMarkerWidth = measuredWidth(for: NSTextStorage(
        string: "**bold**",
        attributes: [.font: CurrentTheme.editorBoldFont(configuration: .default)]
    ))

    #expect(abs(hiddenWidth - visibleContentWidth) < 1)
    #expect(hiddenWidth < rawMarkerWidth - 4)
}

@Test
func markdownLayoutManagerReservesHiddenHeadingPrefixWidth() {
    let text = "# Heading"
    let hiddenStorage = highlightedStorage(text)
    let activeStorage = highlightedStorage(
        text,
        selectedRange: NSRange(location: (text as NSString).length, length: 0)
    )
    let hiddenPrefixWidth = measuredWidth(for: hiddenStorage)
    let activePrefixWidth = measuredWidth(for: activeStorage)
    let visibleHeadingWidth = measuredWidth(for: NSTextStorage(
        string: "Heading",
        attributes: [.font: CurrentTheme.editorHeadingFont(level: 1, configuration: .default)]
    ))
    let hiddenParagraph = hiddenStorage.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle

    #expect(abs(hiddenPrefixWidth - activePrefixWidth) < 1)
    #expect(hiddenPrefixWidth > visibleHeadingWidth + 4)
    #expect(hiddenParagraph?.firstLineHeadIndent == 0)
}

@Test
func markdownTextLayoutMeasurerUsesRenderedMarkdownLayout() {
    let text = "# Heading\n---\n**bold**"
    let helperHeight = MarkdownTextLayoutMeasurer.measuredHeight(
        text: text,
        width: 700,
        minimumHeight: 0,
        configuration: .default
    )
    let directLayoutHeight = measuredHeight(for: highlightedStorage(text), width: 700)

    #expect(abs(helperHeight - directLayoutHeight) < 1)
}

@Test
func markdownTextLayoutMeasurerKeepsCommittedRuleHeightStableWhileTypingNextLine() {
    let committedRuleHeight = MarkdownTextLayoutMeasurer.measuredHeight(
        text: "---\n",
        width: 700,
        minimumHeight: 0,
        configuration: .default
    )
    let typingNextLineHeight = MarkdownTextLayoutMeasurer.measuredHeight(
        text: "---\nA",
        width: 700,
        minimumHeight: 0,
        configuration: .default
    )

    #expect(abs(committedRuleHeight - typingNextLineHeight) <= 1)
}

@Test
func inlineFormattingPreservesComposedCharacters() {
    let text = "Hi 👨‍👩‍👧‍👦 cafe\u{301}"
    let nsText = text as NSString
    let emojiRange = nsText.range(of: "👨‍👩‍👧‍👦")
    let accentRange = nsText.range(of: "e\u{301}")

    let emojiEdit = MarkdownInlineFormatting.formattingEdit(
        kind: .bold,
        in: text,
        selectedRange: emojiRange
    )
    #expect(emojiEdit?.replacement == "Hi **👨‍👩‍👧‍👦** cafe\u{301}")
    #expect(emojiEdit?.selectedRangeAfterEdit == NSRange(location: emojiRange.location + 2, length: emojiRange.length))

    let accentEdit = MarkdownInlineFormatting.formattingEdit(
        kind: .italic,
        in: text,
        selectedRange: accentRange
    )
    #expect(accentEdit?.replacement == "Hi 👨‍👩‍👧‍👦 caf_e\u{301}_")
    #expect(accentEdit?.selectedRangeAfterEdit == NSRange(location: accentRange.location + 1, length: accentRange.length))
}

@Test
func inlineFormattingExcludesMultilineListPrefixes() {
    let text = "1. one\n2. two"
    let edit = MarkdownInlineFormatting.formattingEdit(
        kind: .bold,
        in: text,
        selectedRange: NSRange(location: 0, length: (text as NSString).length)
    )

    #expect(edit?.replacement == "1. **one**\n2. **two**")
    #expect(edit?.selectedRangeAfterEdit == NSRange(location: 5, length: 14))
}

@Test
func inlineFormattingExcludesHeadingPrefixes() {
    let text = "## Heading"
    let edit = MarkdownInlineFormatting.formattingEdit(
        kind: .bold,
        in: text,
        selectedRange: NSRange(location: 0, length: (text as NSString).length)
    )

    #expect(edit?.replacement == "## **Heading**")
    #expect(edit?.selectedRangeAfterEdit == NSRange(location: 5, length: 7))
}

@Test
func emptyListBackspaceExitsOnlyEmptyItems() {
    let bullet = MarkdownListEditing.emptyItemBackspaceEdit(
        in: "- ",
        selectedRange: NSRange(location: 2, length: 0)
    )
    #expect(bullet == MarkdownListEditing.TextEdit(
        range: NSRange(location: 0, length: 2),
        replacement: "",
        selectedRangeAfterEdit: NSRange(location: 0, length: 0)
    ))

    let ordered = MarkdownListEditing.emptyItemBackspaceEdit(
        in: "1. ",
        selectedRange: NSRange(location: 3, length: 0)
    )
    #expect(ordered == MarkdownListEditing.TextEdit(
        range: NSRange(location: 0, length: 3),
        replacement: "",
        selectedRangeAfterEdit: NSRange(location: 0, length: 0)
    ))

    let task = MarkdownListEditing.emptyItemBackspaceEdit(
        in: "- [ ] ",
        selectedRange: NSRange(location: 6, length: 0)
    )
    #expect(task?.replacement == "")
    #expect(task?.selectedRangeAfterEdit == NSRange(location: 0, length: 0))

    let orderedTask = MarkdownListEditing.emptyItemBackspaceEdit(
        in: "1. [x] ",
        selectedRange: NSRange(location: 7, length: 0)
    )
    #expect(orderedTask?.replacement == "")
    #expect(orderedTask?.selectedRangeAfterEdit == NSRange(location: 0, length: 0))

    let indentedText = "Before\n  - \nAfter"
    let indented = MarkdownListEditing.emptyItemBackspaceEdit(
        in: indentedText,
        selectedRange: NSRange(location: "Before\n  - ".utf16.count, length: 0)
    )
    #expect(indented == MarkdownListEditing.TextEdit(
        range: NSRange(location: "Before\n".utf16.count, length: "  - ".utf16.count),
        replacement: "",
        selectedRangeAfterEdit: NSRange(location: "Before\n".utf16.count, length: 0)
    ))
}

@Test
func emptyListBackspaceIgnoresNonEmptyAndFencedItems() {
    #expect(MarkdownListEditing.emptyItemBackspaceEdit(
        in: "- item",
        selectedRange: NSRange(location: 2, length: 0)
    ) == nil)
    #expect(MarkdownListEditing.emptyItemBackspaceEdit(
        in: "1. item",
        selectedRange: NSRange(location: 3, length: 0)
    ) == nil)

    let fenced = "```\n- \n```"
    #expect(MarkdownListEditing.emptyItemBackspaceEdit(
        in: fenced,
        selectedRange: NSRange(location: "```\n- ".utf16.count, length: 0)
    ) == nil)
}

@Test
func selectionNormalizationKeepsCollapsedHeadingCaretsInLiveMode() {
    #expect(MarkdownSelectionNormalization.normalizedVisibleSelection(
        in: "# Heading",
        selectedRange: NSRange(location: 0, length: 0)
    ) == NSRange(location: 0, length: 0))
    #expect(MarkdownSelectionNormalization.normalizedVisibleSelection(
        in: "# Heading",
        selectedRange: NSRange(location: 1, length: 0)
    ) == NSRange(location: 1, length: 0))
    #expect(MarkdownSelectionNormalization.normalizedVisibleSelection(
        in: "# Heading",
        selectedRange: NSRange(location: 2, length: 0)
    ) == NSRange(location: 2, length: 0))
    #expect(MarkdownSelectionNormalization.normalizedVisibleSelection(
        in: "#",
        selectedRange: NSRange(location: 0, length: 0)
    ) == NSRange(location: 0, length: 0))
    #expect(MarkdownSelectionNormalization.normalizedVisibleSelection(
        in: "1. item",
        selectedRange: NSRange(location: 0, length: 0)
    ) == NSRange(location: 0, length: 0))
}

@Test
func markdownEditorRenderModelCollectsSharedDecorationFacts() {
    let text = "# **Heading**\n1. <u>item</u>\n---\n"
    let model = MarkdownEditorRenderModel(text: text)

    #expect(model.headings.count == 1)
    #expect(model.lists.count == 1)
    #expect(model.horizontalRules.count == 1)
    #expect(model.inlineSpans.contains { $0.kind == .bold })
    #expect(model.inlineSpans.contains { $0.kind == .underline })
    #expect(model.hiddenSyntaxRanges.contains(NSRange(location: 0, length: 2)))
    #expect(model.structuralContentRange(at: ("# **Heading**\n" as NSString).length) == model.lists[0].contentRange)
}

@Test
func markdownTextStorageDecoratesDuringTextKitEditing() {
    let storage = MarkdownTextStorage(string: "# Heading")

    #expect(!boolAttribute(.currentHiddenMarkdownSyntax, in: storage, at: 0))

    storage.replaceCharacters(in: NSRange(location: 0, length: 2), with: "")

    let font = storage.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
    #expect(!boolAttribute(.currentHiddenMarkdownSyntax, in: storage, at: 0))
    #expect(font?.pointSize == CurrentTheme.editorFont(configuration: .default).pointSize)
}

@Test
func markdownTextStorageRedecoratesActiveBlocksOnSelectionChanges() {
    let text = "# One\n## Two"
    let storage = MarkdownTextStorage(string: text)
    let secondPrefixLocation = ("# One\n" as NSString).length

    storage.updateSelectedRange(NSRange(location: 2, length: 0))
    #expect(!boolAttribute(.currentHiddenMarkdownSyntax, in: storage, at: 0))
    #expect(!boolAttribute(.currentHiddenMarkdownSyntax, in: storage, at: secondPrefixLocation))

    storage.updateSelectedRange(NSRange(location: secondPrefixLocation + 3, length: 0))
    #expect(!boolAttribute(.currentHiddenMarkdownSyntax, in: storage, at: 0))
    #expect(!boolAttribute(.currentHiddenMarkdownSyntax, in: storage, at: secondPrefixLocation))
}

@Test
@MainActor
func visibleCaretKeepsEmptyHeadingOnHeadingLineMetrics() {
    for (text, level) in [("# ", 1), ("## ", 2), ("### ", 3)] {
        let emptyView = markdownRenderedTextView(string: text)
        emptyView.setSelectedRange(NSRange(location: (text as NSString).length, length: 0))
        (emptyView.textStorage as? MarkdownTextStorage)?.updateSelectedRange(emptyView.selectedRange())
        let emptyMetrics = headingLineFragmentMetrics(for: text)
        let typedMetrics = headingLineFragmentMetrics(for: text + "A")

        #expect(MarkdownVisibleCaret.insertionRect(in: emptyView) == nil)
        #expect(abs(emptyMetrics.minY - typedMetrics.minY) < 0.5)
        #expect(abs(emptyMetrics.height - typedMetrics.height) < 0.5)
        #expect(abs(emptyMetrics.height - CurrentTheme.editorHeadingLineHeight(level: level, configuration: .default)) < 0.5)
    }
}

@Test
@MainActor
func collapsedFormattingShortcutUsesPendingTypingMarks() {
    let textView = markdownRenderedTextView(string: "")

    textView.toggleBoldface(nil)
    textView.insertText("a", replacementRange: textView.selectedRange())
    #expect(textView.string == "**a**")
    #expect(textView.selectedRange() == NSRange(location: 3, length: 0))

    textView.insertText("b", replacementRange: textView.selectedRange())
    #expect(textView.string == "**ab**")
    #expect(textView.selectedRange() == NSRange(location: 4, length: 0))
}

@Test
@MainActor
func markdownTextViewFormattingActionsApplyMarkdownEdits() {
    let boldView = markdownTextView(string: "Format me")
    boldView.setSelectedRange(("Format me" as NSString).range(of: "me"))
    boldView.toggleBoldface(nil)

    #expect(boldView.string == "Format **me**")
    #expect(boldView.selectedRange() == NSRange(location: 9, length: 2))

    let underlineView = markdownTextView(string: "Format me")
    underlineView.setSelectedRange(("Format me" as NSString).range(of: "me"))
    underlineView.underline(nil)

    #expect(underlineView.string == "Format <u>me</u>")
    #expect(underlineView.selectedRange() == NSRange(location: 10, length: 2))

    let commandView = markdownTextView(string: "Format me")
    commandView.setSelectedRange(("Format me" as NSString).range(of: "me"))
    commandView.doCommand(by: Selector(("toggleBoldface:")))

    #expect(commandView.string == "Format **me**")
    #expect(commandView.selectedRange() == NSRange(location: 9, length: 2))
}

@Test
func scopedHighlighterClearsStaleDecorationsOnEditedLine() {
    let highlighter = MarkdownSyntaxHighlighter()
    let storage = NSTextStorage(string: "# Heading\nBody")
    highlighter.highlight(storage)

    #expect(!boolAttribute(.currentHiddenMarkdownSyntax, in: storage, at: 0))

    storage.replaceCharacters(in: NSRange(location: 0, length: 2), with: "")
    highlighter.highlightAroundEditedRange(storage, editedRange: NSRange(location: 0, length: 0))

    let font = storage.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
    let paragraph = storage.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle

    #expect(!boolAttribute(.currentHiddenMarkdownSyntax, in: storage, at: 0))
    #expect(font?.pointSize == CurrentTheme.editorFont(configuration: .default).pointSize)
    #expect(paragraph?.minimumLineHeight == CurrentTheme.editorLineHeight(configuration: .default))
}

private func highlightedStorage(_ text: String, selectedRange: NSRange? = nil) -> NSTextStorage {
    let storage = NSTextStorage(string: text)
    MarkdownSyntaxHighlighter().highlight(storage, selectedRange: selectedRange)
    return storage
}

@MainActor
private func markdownTextView(string: String) -> MarkdownTextView {
    let textStorage = NSTextStorage(string: string)
    let layoutManager = MarkdownLayoutManager()
    let textContainer = NSTextContainer(size: NSSize(width: 700, height: 1_000))
    textContainer.lineFragmentPadding = 0
    textStorage.addLayoutManager(layoutManager)
    layoutManager.addTextContainer(textContainer)

    let textView = MarkdownTextView(
        frame: NSRect(x: 0, y: 0, width: 700, height: 1_000),
        textContainer: textContainer
    )
    textView.isRichText = false
    return textView
}

@MainActor
private func markdownRenderedTextView(string: String) -> MarkdownTextView {
    let textStorage = MarkdownTextStorage(string: string)
    let layoutManager = MarkdownLayoutManager()
    let textContainer = NSTextContainer(size: NSSize(width: 700, height: 1_000))
    textContainer.lineFragmentPadding = 0
    textStorage.addLayoutManager(layoutManager)
    layoutManager.addTextContainer(textContainer)

    let textView = MarkdownTextView(
        frame: NSRect(x: 0, y: 0, width: 700, height: 1_000),
        textContainer: textContainer
    )
    textView.isRichText = false
    textView.configuration = .default
    return textView
}

private func headingLineFragmentMetrics(for text: String) -> NSRect {
    let storage = MarkdownTextStorage(string: text)
    let layoutManager = MarkdownLayoutManager()
    let textContainer = NSTextContainer(size: NSSize(width: 700, height: 1_000))
    textContainer.lineFragmentPadding = 0
    storage.addLayoutManager(layoutManager)
    layoutManager.addTextContainer(textContainer)
    layoutManager.ensureLayout(for: textContainer)
    return layoutManager.lineFragmentRect(forGlyphAt: 0, effectiveRange: nil)
}

private func measuredWidth(for storage: NSTextStorage) -> CGFloat {
    let layoutManager = MarkdownLayoutManager()
    let textContainer = NSTextContainer(size: NSSize(width: 1_000, height: 1_000))
    textContainer.lineFragmentPadding = 0
    storage.addLayoutManager(layoutManager)
    layoutManager.addTextContainer(textContainer)
    layoutManager.ensureLayout(for: textContainer)
    return layoutManager.usedRect(for: textContainer).width
}

private func measuredHeight(for storage: NSTextStorage, width: CGFloat) -> CGFloat {
    let layoutManager = MarkdownLayoutManager()
    let textContainer = NSTextContainer(
        size: NSSize(width: width, height: CGFloat.greatestFiniteMagnitude)
    )
    textContainer.lineFragmentPadding = 0
    storage.addLayoutManager(layoutManager)
    layoutManager.addTextContainer(textContainer)
    layoutManager.ensureLayout(for: textContainer)
    let used = layoutManager.usedRect(for: textContainer)
    return ceil(used.height + CurrentTheme.editorVerticalInset * 2 + 6)
}

private func horizontalRuleStrokeY(for text: String) -> CGFloat {
    horizontalRuleLayoutMetrics(for: text).strokeY
}

private struct HorizontalRuleLayoutMetrics {
    var lineRect: NSRect
    var strokeY: CGFloat
}

private func horizontalRuleLayoutMetrics(for text: String) -> HorizontalRuleLayoutMetrics {
    let storage = highlightedStorage(text)
    let layoutManager = MarkdownLayoutManager()
    let textContainer = NSTextContainer(size: NSSize(width: 700, height: CGFloat.greatestFiniteMagnitude))
    textContainer.lineFragmentPadding = 0
    storage.addLayoutManager(layoutManager)
    layoutManager.addTextContainer(textContainer)
    layoutManager.ensureLayout(for: textContainer)

    let markerGlyphRange = layoutManager.glyphRange(
        forCharacterRange: NSRange(location: 0, length: 3),
        actualCharacterRange: nil
    )
    let lineRect = layoutManager.lineFragmentRect(forGlyphAt: markerGlyphRange.location, effectiveRange: nil)
    return HorizontalRuleLayoutMetrics(
        lineRect: lineRect,
        strokeY: MarkdownLayoutManager.horizontalRuleStrokeY(lineRect: lineRect, originY: 0)
    )
}

private func intAttribute(_ key: NSAttributedString.Key, in storage: NSTextStorage, at index: Int) -> Int {
    switch storage.attribute(key, at: index, effectiveRange: nil) {
    case let value as Int:
        return value
    case let value as NSNumber:
        return value.intValue
    default:
        return 0
    }
}

private func boolAttribute(_ key: NSAttributedString.Key, in storage: NSTextStorage, at index: Int) -> Bool {
    switch storage.attribute(key, at: index, effectiveRange: nil) {
    case let value as Bool:
        return value
    case let value as NSNumber:
        return value.boolValue
    default:
        return false
    }
}

private func backgroundIsClear(in storage: NSTextStorage, at index: Int) -> Bool {
    guard let color = storage.attribute(.backgroundColor, at: index, effectiveRange: nil) as? NSColor else {
        return true
    }
    return color.alphaComponent == 0
}

private func foregroundIsClear(in storage: NSTextStorage, at index: Int) -> Bool {
    guard let color = storage.attribute(.foregroundColor, at: index, effectiveRange: nil) as? NSColor else {
        return false
    }
    return color.alphaComponent == 0
}
