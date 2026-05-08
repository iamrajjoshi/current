import AppKit
import SwiftUI

final class MarkdownLayoutManager: NSLayoutManager, NSLayoutManagerDelegate {
    override init() {
        super.init()
        delegate = self
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        delegate = self
    }

    func layoutManager(
        _ layoutManager: NSLayoutManager,
        shouldGenerateGlyphs glyphs: UnsafePointer<CGGlyph>,
        properties props: UnsafePointer<NSLayoutManager.GlyphProperty>,
        characterIndexes charIndexes: UnsafePointer<Int>,
        font aFont: NSFont,
        forGlyphRange glyphRange: NSRange
    ) -> Int {
        guard let textStorage else { return 0 }

        var properties = Array(UnsafeBufferPointer(start: props, count: glyphRange.length))
        for offset in 0..<glyphRange.length {
            let characterIndex = charIndexes[offset]
            guard characterIndex >= 0, characterIndex < textStorage.length else { continue }
            let isCollapsedSyntax = (textStorage.attribute(
                .currentCollapsedMarkdownSyntax,
                at: characterIndex,
                effectiveRange: nil
            ) as? Bool) == true
            let isHorizontalRuleMarker = (textStorage.attribute(
                .currentHorizontalRuleMarker,
                at: characterIndex,
                effectiveRange: nil
            ) as? Bool) == true
            if isCollapsedSyntax && !isHorizontalRuleMarker {
                properties[offset].insert(.null)
            }
        }

        properties.withUnsafeBufferPointer { propertyBuffer in
            guard let baseAddress = propertyBuffer.baseAddress else { return }
            layoutManager.setGlyphs(
                glyphs,
                properties: baseAddress,
                characterIndexes: charIndexes,
                font: aFont,
                forGlyphRange: glyphRange
            )
        }
        return glyphRange.length
    }

    func layoutManager(
        _ layoutManager: NSLayoutManager,
        shouldSetLineFragmentRect lineFragmentRect: UnsafeMutablePointer<NSRect>,
        lineFragmentUsedRect: UnsafeMutablePointer<NSRect>,
        baselineOffset: UnsafeMutablePointer<CGFloat>,
        in textContainer: NSTextContainer,
        forGlyphRange glyphRange: NSRange
    ) -> Bool {
        guard let textStorage, glyphRange.length > 0 else { return true }

        let characterRange = self.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
        let model = MarkdownEditorRenderModel(text: textStorage.string)
        guard let ruleLineRange = Self.horizontalRuleLineRangeForDrawing(
            model: model,
            characterRange: characterRange
        ) else {
            return true
        }

        let paragraph = textStorage.attribute(
            .paragraphStyle,
            at: min(ruleLineRange.location, max(0, textStorage.length - 1)),
            effectiveRange: nil
        ) as? NSParagraphStyle
        let lineHeight = max(
            max(paragraph?.minimumLineHeight ?? 0, lineFragmentRect.pointee.height),
            CurrentTheme.editorLineHeight(configuration: .default)
        )
        lineFragmentRect.pointee.size.height = lineHeight
        lineFragmentUsedRect.pointee.size.height = lineHeight
        return true
    }

    override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        super.drawBackground(forGlyphRange: glyphsToShow, at: origin)
        drawHorizontalRules(forGlyphRange: glyphsToShow, at: origin)
    }

    private func drawHorizontalRules(forGlyphRange glyphRange: NSRange, at origin: NSPoint) {
        guard let textStorage, textStorage.length > 0 else { return }
        let text = textStorage.string
        let model = MarkdownEditorRenderModel(text: text)
        let markdownStorage = textStorage as? MarkdownTextStorage
        var drawnRuleLineLocations = Set<Int>()

        enumerateLineFragments(forGlyphRange: glyphRange) { _, _, _, lineGlyphRange, _ in
            let characterRange = self.characterRange(forGlyphRange: lineGlyphRange, actualGlyphRange: nil)
            guard let ruleLineRange = Self.horizontalRuleLineRangeForDrawing(
                model: model,
                characterRange: characterRange
            ) else { return }
            guard drawnRuleLineLocations.insert(ruleLineRange.location).inserted else { return }
            guard let displayState = model.horizontalRule(at: ruleLineRange.location),
                  case .committedDivider(let horizontalRule) = displayState else {
                return
            }
            guard markdownStorage?.horizontalRuleIsActive(horizontalRule) != true else { return }

            let markerGlyphRange = self.glyphRange(
                forCharacterRange: horizontalRule.markerRange,
                actualCharacterRange: nil
            )
            guard markerGlyphRange.length > 0 else { return }

            let lineRect = self.lineFragmentRect(forGlyphAt: markerGlyphRange.location, effectiveRange: nil)
            let y = Self.horizontalRuleStrokeY(lineRect: lineRect, originY: origin.y)
            let startX = origin.x + lineRect.minX
            let endX = origin.x + lineRect.maxX
            let path = NSBezierPath()
            path.lineWidth = 1
            path.move(to: NSPoint(x: startX, y: y))
            path.line(to: NSPoint(x: endX, y: y))
            CurrentTheme.dividerColor.setStroke()
            path.stroke()
        }
    }

    static func horizontalRuleLineRangeForDrawing(in text: String, characterRange: NSRange) -> NSRange? {
        horizontalRuleLineRangeForDrawing(
            model: MarkdownEditorRenderModel(text: text),
            characterRange: characterRange
        )
    }

    static func horizontalRuleLineRangeForDrawing(
        model: MarkdownEditorRenderModel,
        characterRange: NSRange
    ) -> NSRange? {
        let nsText = model.text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)
        let boundedRange = NSIntersectionRange(characterRange, fullRange)
        guard boundedRange.length > 0 else { return nil }

        let lineRange = nsText.lineRange(for: NSRange(location: boundedRange.location, length: 0))
        guard NSIntersectionRange(lineRange, boundedRange).length > 0,
              let displayState = model.horizontalRule(at: lineRange.location),
              case .committedDivider(let horizontalRule) = displayState else {
            return nil
        }

        return horizontalRule.lineRange
    }

    static func horizontalRuleStrokeY(lineRect: NSRect, originY: CGFloat) -> CGFloat {
        floor(originY + lineRect.midY) + 0.5
    }
}

final class MarkdownTextView: NSTextView {
    weak static var activeEditor: MarkdownTextView?
    private static var editorsByDayID: [String: WeakMarkdownTextView] = [:]
    var onFocus: (() -> Void)?
    var configuration: CurrentConfiguration = .default
    private var typingMarks = MarkdownTypingMarks()
    var currentDayID: String? {
        didSet {
            Self.unregister(oldValue, editor: self)
            Self.register(self, dayID: currentDayID)
        }
    }

    override func becomeFirstResponder() -> Bool {
        let becameFirstResponder = super.becomeFirstResponder()
        if becameFirstResponder {
            Self.activeEditor = self
            onFocus?()
        }
        return becameFirstResponder
    }

    override func keyDown(with event: NSEvent) {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if handleInlineFormattingShortcut(for: event, modifiers: modifiers) {
            return
        }

        switch event.keyCode {
        case 51 where modifiers.isEmpty:
            if apply(MarkdownListEditing.emptyItemBackspaceEdit(in: string, selectedRange: selectedRange())) {
                return
            }
            if apply(MarkdownBlockEditing.horizontalRuleBackspaceEdit(in: string, selectedRange: selectedRange())) {
                return
            }
            if apply(MarkdownBlockEditing.headingBackspaceEdit(in: string, selectedRange: selectedRange())) {
                return
            }
            if apply(MarkdownInlineFormatting.backspaceEdit(in: string, selectedRange: selectedRange())) {
                return
            }
        case 36 where modifiers == .command,
             76 where modifiers == .command:
            if apply(MarkdownListEditing.taskToggleEdit(in: string, selectedRange: selectedRange())) {
                return
            }
        case 36 where modifiers.isEmpty,
             76 where modifiers.isEmpty:
            if apply(MarkdownListEditing.continuationEdit(in: string, selectedRange: selectedRange())) {
                return
            }
        case 48 where modifiers.isEmpty || modifiers == .shift:
            if apply(MarkdownListEditing.indentationEdit(
                in: string,
                selectedRange: selectedRange(),
                outdent: modifiers == .shift
            )) {
                return
            }
        default:
            break
        }
        super.keyDown(with: event)
    }

    override func doCommand(by commandSelector: Selector) {
        if handleInlineFormattingCommand(commandSelector) {
            return
        }
        super.doCommand(by: commandSelector)
    }

    override func insertText(_ insertString: Any, replacementRange: NSRange) {
        guard let insertedText = Self.plainString(from: insertString),
              replacementRange.length == 0,
              !typingMarks.isEmpty,
              !insertedText.isEmpty,
              insertedText.rangeOfCharacter(from: .newlines) == nil else {
            super.insertText(insertString, replacementRange: replacementRange)
            return
        }

        let model = MarkdownEditorRenderModel(text: string)
        if typingMarks.isSatisfied(by: model.inlineMarks(at: replacementRange.location)) {
            super.insertText(insertString, replacementRange: replacementRange)
            return
        }

        let wrapped = typingMarks.wrap(insertedText)
        super.insertText(wrapped.replacement, replacementRange: replacementRange)
        setSelectedRange(NSRange(location: replacementRange.location + wrapped.visibleOffset, length: 0))
    }

    override func selectionRange(
        forProposedRange proposedCharRange: NSRange,
        granularity: NSSelectionGranularity
    ) -> NSRange {
        let proposed = super.selectionRange(forProposedRange: proposedCharRange, granularity: granularity)
        return MarkdownSelectionNormalization.normalizedVisibleSelection(in: string, selectedRange: proposed)
    }

    override func firstRect(forCharacterRange charRange: NSRange, actualRange: NSRangePointer?) -> NSRect {
        if let rect = MarkdownVisibleCaret.firstRect(in: self, for: charRange) {
            actualRange?.pointee = charRange
            return rect
        }
        return super.firstRect(forCharacterRange: charRange, actualRange: actualRange)
    }

    override func drawInsertionPoint(in rect: NSRect, color: NSColor, turnedOn flag: Bool) {
        if let adjustedRect = MarkdownVisibleCaret.insertionRect(in: self) {
            super.drawInsertionPoint(in: adjustedRect, color: color, turnedOn: flag)
            return
        }
        super.drawInsertionPoint(in: rect, color: color, turnedOn: flag)
    }

    @objc func toggleBoldface(_ sender: Any?) {
        _ = applyInlineFormatting(kind: .bold)
    }

    @objc func toggleItalics(_ sender: Any?) {
        _ = applyInlineFormatting(kind: .italic)
    }

    override func underline(_ sender: Any?) {
        if applyInlineFormatting(kind: .underline) {
            return
        }
        super.underline(sender)
    }

    override func paste(_ sender: Any?) {
        if let text = MarkdownPasteConverter.bestString(from: NSPasteboard.general) {
            insertText(text, replacementRange: selectedRange())
            return
        }
        super.paste(sender)
    }

    static func insertTimestampIntoActiveEditor() {
        guard let editor = activeEditor else { return }
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        editor.insertText("[\(formatter.string(from: Date()))] ", replacementRange: editor.selectedRange())
    }

    static func focusEditor(dayID: String) {
        pruneEditorRegistry()
        guard let editor = editorsByDayID[dayID]?.textView else { return }
        editor.window?.makeFirstResponder(editor)
        editor.setSelectedRange(NSRange(location: editor.string.utf16.count, length: 0))
        editor.scrollRangeToVisible(editor.selectedRange())
    }

    private static func register(_ editor: MarkdownTextView, dayID: String?) {
        guard let dayID else { return }
        editorsByDayID[dayID] = WeakMarkdownTextView(textView: editor)
    }

    private static func unregister(_ dayID: String?, editor: MarkdownTextView) {
        guard let dayID,
              editorsByDayID[dayID]?.textView === editor else { return }
        editorsByDayID.removeValue(forKey: dayID)
    }

    private static func pruneEditorRegistry() {
        editorsByDayID = editorsByDayID.filter { $0.value.textView != nil }
    }

    private func handleInlineFormattingShortcut(
        for event: NSEvent,
        modifiers: NSEvent.ModifierFlags
    ) -> Bool {
        guard let key = event.charactersIgnoringModifiers?.lowercased() else { return false }

        switch (key, modifiers) {
        case ("b", .command):
            return applyInlineFormatting(kind: .bold)
        case ("i", .command):
            return applyInlineFormatting(kind: .italic)
        case ("u", .command):
            return applyInlineFormatting(kind: .underline)
        case ("s", [.command, .shift]):
            return applyInlineFormatting(kind: .strikethrough)
        case ("e", .command):
            return applyInlineFormatting(kind: .inlineCode)
        case ("k", .command):
            return apply(MarkdownInlineFormatting.linkEdit(
                in: string,
                selectedRange: selectedRange(),
                urlString: NSPasteboard.general.string(forType: .string) ?? ""
            ))
        default:
            return false
        }
    }

    private func handleInlineFormattingCommand(_ commandSelector: Selector) -> Bool {
        let kind: MarkdownInlineFormatting.Kind
        switch NSStringFromSelector(commandSelector) {
        case "toggleBoldface:":
            kind = .bold
        case "toggleItalics:":
            kind = .italic
        case "underline:":
            kind = .underline
        default:
            return false
        }

        return applyInlineFormatting(kind: kind)
    }

    private func applyInlineFormatting(kind: MarkdownInlineFormatting.Kind) -> Bool {
        let selection = selectedRange()
        if selection.length == 0 {
            typingMarks.toggle(kind)
            setBaseTypingAttributes(typingAttributes)
            return true
        }

        typingMarks = MarkdownTypingMarks()
        return apply(MarkdownInlineFormatting.formattingEdit(kind: kind, in: string, selectedRange: selection))
    }

    private func apply(_ edit: MarkdownListEditing.TextEdit?) -> Bool {
        guard let edit else { return false }
        insertText(edit.replacement, replacementRange: edit.range)
        setSelectedRange(edit.selectedRangeAfterEdit)
        return true
    }

    func setBaseTypingAttributes(_ attributes: [NSAttributedString.Key: Any]) {
        typingAttributes = typingMarks.applying(to: attributes, configuration: configuration)
    }

    private static func plainString(from insertString: Any) -> String? {
        if let string = insertString as? String {
            return string
        }
        if let attributedString = insertString as? NSAttributedString {
            return attributedString.string
        }
        return nil
    }
}

private struct WeakMarkdownTextView {
    weak var textView: MarkdownTextView?
}

struct MarkdownEditorView: NSViewRepresentable {
    @Binding var text: String
    @Binding var measuredHeight: CGFloat
    var dayID: String?
    var configuration: CurrentConfiguration = .default
    var focusOnAppear: Bool
    var minimumHeight: CGFloat = 72
    var onFocus: () -> Void = {}

    nonisolated static func plainTypingAttributes(configuration: CurrentConfiguration) -> [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = CurrentTheme.editorLineHeight(configuration: configuration)
        paragraph.maximumLineHeight = CurrentTheme.editorLineHeight(configuration: configuration)
        paragraph.lineBreakMode = .byWordWrapping

        return [
            .font: CurrentTheme.editorFont(configuration: configuration),
            .foregroundColor: CurrentTheme.primaryTextColor,
            .paragraphStyle: paragraph,
            .baselineOffset: CurrentTheme.editorBaselineOffset,
            .underlineStyle: 0,
            .strikethroughStyle: 0,
            .currentHorizontalRule: false,
            .currentHorizontalRuleMarker: false,
            .currentHiddenMarkdownSyntax: false,
            .currentCollapsedMarkdownSyntax: false,
            .spellingState: 0,
            .backgroundColor: NSColor.clear
        ]
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.appearance = NSAppearance(named: .aqua)
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder

        let textStorage = MarkdownTextStorage(string: text, configuration: configuration)
        let layoutManager = MarkdownLayoutManager()
        let textContainer = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        textStorage.addLayoutManager(layoutManager)
        layoutManager.addTextContainer(textContainer)

        let textView = MarkdownTextView(frame: .zero, textContainer: textContainer)
        textView.configuration = configuration
        textView.appearance = NSAppearance(named: .aqua)
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.usesFindPanel = true
        textView.usesFontPanel = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticTextCompletionEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.enabledTextCheckingTypes = 0
        textView.linkTextAttributes = [
            .foregroundColor: CurrentTheme.primaryTextColor,
            .underlineStyle: 0
        ]
        textView.backgroundColor = CurrentTheme.editorBackground
        textView.drawsBackground = true
        textView.insertionPointColor = CurrentTheme.primaryTextColor
        textView.textColor = CurrentTheme.primaryTextColor
        textView.onFocus = {
            context.coordinator.parent.onFocus()
        }
        textView.textContainerInset = NSSize(
            width: CurrentTheme.editorHorizontalInset,
            height: CurrentTheme.editorVerticalInset
        )
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.heightTracksTextView = false
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.minSize = NSSize(width: 0, height: 0)
        textView.currentDayID = dayID

        context.coordinator.textView = textView
        context.coordinator.updateTypingAttributes(for: textView)
        scrollView.documentView = textView

        DispatchQueue.main.async {
            context.coordinator.remeasure(in: scrollView)
            if focusOnAppear, !context.coordinator.didFocusInitially {
                context.coordinator.didFocusInitially = true
                textView.window?.makeFirstResponder(textView)
                textView.setSelectedRange(NSRange(location: textView.string.utf16.count, length: 0))
                (textView.textStorage as? MarkdownTextStorage)?.updateSelectedRange(textView.selectedRange())
                textView.scrollRangeToVisible(textView.selectedRange())
            }
        }

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let configurationChanged = context.coordinator.highlightedConfiguration != configuration
        context.coordinator.parent = self
        guard let textView = scrollView.documentView as? MarkdownTextView else { return }
        let textChanged = !context.coordinator.isUpdatingFromTextView && textView.string != text
        let widthChanged = abs(context.coordinator.lastMeasuredWidth - scrollView.contentSize.width) > 1

        textView.currentDayID = dayID
        textView.onFocus = {
            context.coordinator.parent.onFocus()
        }

        guard textChanged || configurationChanged || widthChanged else { return }

        scrollView.appearance = NSAppearance(named: .aqua)
        textView.appearance = NSAppearance(named: .aqua)
        textView.backgroundColor = CurrentTheme.editorBackground
        textView.insertionPointColor = CurrentTheme.primaryTextColor
        textView.textColor = CurrentTheme.primaryTextColor
        if configurationChanged {
            textView.configuration = configuration
            (textView.textStorage as? MarkdownTextStorage)?.configuration = configuration
            context.coordinator.updateTypingAttributes(for: textView)
        }

        if textChanged {
            context.coordinator.isUpdatingFromSwiftUI = true
            let selection = textView.selectedRange()
            textView.string = text
            textView.setSelectedRange(selection.location <= textView.string.utf16.count ? selection : NSRange(location: textView.string.utf16.count, length: 0))
            (textView.textStorage as? MarkdownTextStorage)?.updateSelectedRange(textView.selectedRange())
            (textView.textStorage as? MarkdownTextStorage)?.applyDecorations()
            context.coordinator.highlightedConfiguration = configuration
            context.coordinator.isUpdatingFromSwiftUI = false
        } else if configurationChanged {
            (textView.textStorage as? MarkdownTextStorage)?.applyDecorations()
            context.coordinator.highlightedConfiguration = configuration
        }

        DispatchQueue.main.async {
            context.coordinator.remeasure(in: scrollView)
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MarkdownEditorView
        weak var textView: MarkdownTextView?
        var isUpdatingFromSwiftUI = false
        var isUpdatingFromTextView = false
        var didFocusInitially = false
        var highlightedConfiguration: CurrentConfiguration
        var lastMeasuredWidth: CGFloat = 0
        private var isNormalizingSelection = false

        init(_ parent: MarkdownEditorView) {
            self.parent = parent
            self.highlightedConfiguration = parent.configuration
        }

        func textDidBeginEditing(_ notification: Notification) {
            guard let textView = notification.object as? MarkdownTextView else { return }
            MarkdownTextView.activeEditor = textView
            parent.onFocus()
            (textView.textStorage as? MarkdownTextStorage)?.updateSelectedRange(textView.selectedRange())
            updateTypingAttributes(for: textView)
        }

        func textDidEndEditing(_ notification: Notification) {
            guard let textView = notification.object as? MarkdownTextView else { return }
            (textView.textStorage as? MarkdownTextStorage)?.updateSelectedRange(nil)
            if let scrollView = textView.enclosingScrollView {
                remeasure(in: scrollView)
            }
        }

        func textDidChange(_ notification: Notification) {
            guard !isUpdatingFromSwiftUI,
                  let textView = notification.object as? MarkdownTextView else { return }
            isUpdatingFromTextView = true
            highlightedConfiguration = parent.configuration
            updateTypingAttributes(for: textView)
            (textView.textStorage as? MarkdownTextStorage)?.updateSelectedRange(textView.selectedRange())
            parent.text = textView.string
            isUpdatingFromTextView = false
            if let scrollView = textView.enclosingScrollView {
                remeasure(in: scrollView)
            }
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? MarkdownTextView else { return }
            if !isNormalizingSelection {
                let selection = textView.selectedRange()
                let normalizedSelection = MarkdownSelectionNormalization.normalizedVisibleSelection(
                    in: textView.string,
                    selectedRange: selection
                )
                if normalizedSelection != selection {
                    isNormalizingSelection = true
                    textView.setSelectedRange(normalizedSelection)
                    isNormalizingSelection = false
                }
            }
            updateTypingAttributes(for: textView)
            (textView.textStorage as? MarkdownTextStorage)?.updateSelectedRange(textView.selectedRange())
            if let scrollView = textView.enclosingScrollView {
                remeasure(in: scrollView)
            }
        }

        func remeasure(in scrollView: NSScrollView) {
            guard let textView = scrollView.documentView as? MarkdownTextView,
                  let layoutManager = textView.layoutManager,
                  let textContainer = textView.textContainer else { return }

            textContainer.containerSize = NSSize(width: max(1, scrollView.contentSize.width), height: CGFloat.greatestFiniteMagnitude)
            layoutManager.ensureLayout(for: textContainer)
            let used = layoutManager.usedRect(for: textContainer)
            let target = max(parent.minimumHeight, ceil(used.height + textView.textContainerInset.height * 2 + 6))
            lastMeasuredWidth = scrollView.contentSize.width
            if abs(parent.measuredHeight - target) > 1 {
                parent.measuredHeight = target
            }
        }

        func updateTypingAttributes(for textView: NSTextView) {
            var attributes = MarkdownEditorView.plainTypingAttributes(configuration: parent.configuration)

            let selection = textView.selectedRange()
            let model = MarkdownEditorRenderModel(text: textView.string)
            if selection.length == 0,
               let heading = model.heading(at: selection.location),
               selection.location >= heading.contentRange.location {
                let paragraph = NSMutableParagraphStyle()
                paragraph.minimumLineHeight = CurrentTheme.editorHeadingLineHeight(level: heading.level, configuration: parent.configuration)
                paragraph.maximumLineHeight = CurrentTheme.editorHeadingLineHeight(level: heading.level, configuration: parent.configuration)
                paragraph.lineBreakMode = .byWordWrapping
                paragraph.paragraphSpacingBefore = CurrentTheme.editorHeadingSpacingBefore(level: heading.level)
                paragraph.paragraphSpacing = CurrentTheme.editorHeadingSpacingAfter(level: heading.level)
                attributes[.font] = CurrentTheme.editorHeadingFont(level: heading.level, configuration: parent.configuration)
                attributes[.paragraphStyle] = paragraph
            }

            if let markdownTextView = textView as? MarkdownTextView {
                markdownTextView.configuration = parent.configuration
                markdownTextView.setBaseTypingAttributes(attributes)
            } else {
                textView.typingAttributes = attributes
            }
        }

    }
}
