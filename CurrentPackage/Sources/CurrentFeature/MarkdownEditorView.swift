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

    override func processEditing(for textStorage: NSTextStorage, edited editMask: NSTextStorageEditActions,
                                 range newCharRange: NSRange, changeInLength delta: Int, invalidatedRange invalidatedCharRange: NSRange) {
        super.processEditing(for: textStorage, edited: editMask, range: newCharRange,
                             changeInLength: delta, invalidatedRange: invalidatedCharRange)
        if editMask.contains(.editedAttributes) {
            // AppKit does not know that our custom attributes change glyph
            // properties. Refresh those glyphs after its character bookkeeping.
            invalidateGlyphs(forCharacterRange: invalidatedCharRange, changeInLength: 0, actualCharacterRange: nil)
            // Reset geometry for the same affected source, including custom
            // fence boundaries and rich blocks, without relaying out the note.
            invalidateLayout(forCharacterRange: invalidatedCharRange, actualCharacterRange: nil)
        }
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

        let sourceLength = textStorage.length
        var properties = Array(UnsafeBufferPointer(start: props, count: glyphRange.length))
        var collapsedRange = NSRange(location: 0, length: 0)
        var ruleRange = NSRange(location: 0, length: 0)
        var isCollapsedSyntax = false
        var isHorizontalRuleMarker = false
        for offset in 0..<glyphRange.length {
            let characterIndex = charIndexes[offset]
            guard characterIndex >= 0, characterIndex < sourceLength else { continue }
            if !NSLocationInRange(characterIndex, collapsedRange) {
                isCollapsedSyntax = (textStorage.attribute(.currentCollapsedMarkdownSyntax,
                    at: characterIndex, effectiveRange: &collapsedRange) as? Bool) == true
            }
            if !NSLocationInRange(characterIndex, ruleRange) {
                isHorizontalRuleMarker = (textStorage.attribute(.currentHorizontalRuleMarker,
                    at: characterIndex, effectiveRange: &ruleRange) as? Bool) == true
            }
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
        if characterRange.location < textStorage.length,
           (textStorage.attribute(.currentFenceBoundary, at: characterRange.location, effectiveRange: nil) as? Bool) == true {
            lineFragmentRect.pointee.size.height = 8
            lineFragmentUsedRect.pointee.size.height = 8
            baselineOffset.pointee = min(baselineOffset.pointee, 8)
            return true
        }
        if let height = MarkdownRichBlocks.lineHeight(in: textStorage, characterRange: characterRange) {
            lineFragmentRect.pointee.size.height = height
            lineFragmentUsedRect.pointee.size.height = height
            baselineOffset.pointee = min(baselineOffset.pointee, height)
            return true
        }
        guard characterRange.location < textStorage.length,
              (textStorage.attribute(.currentHorizontalRule, at: characterRange.location, effectiveRange: nil) as? Bool) == true else { return true }
        let ruleLineRange = (textStorage.string as NSString).lineRange(for: NSRange(location: characterRange.location, length: 0))

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
        drawBlockBackgrounds(forGlyphRange: glyphsToShow, at: origin)
        super.drawBackground(forGlyphRange: glyphsToShow, at: origin)
        drawListMarkers(forGlyphRange: glyphsToShow, at: origin)
        drawHorizontalRules(forGlyphRange: glyphsToShow, at: origin)
        MarkdownRichBlocks.draw(in: self, glyphRange: glyphsToShow, origin: origin)
    }

    private func drawBlockBackgrounds(forGlyphRange glyphRange: NSRange, at origin: NSPoint) {
        guard let storage = textStorage else { return }
        enumerateLineFragments(forGlyphRange: glyphRange) { rect, _, _, glyphs, _ in
            let range = self.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
            guard range.location < storage.length else { return }
            if (storage.attribute(.currentCodeBlock, at: range.location, effectiveRange: nil) as? Bool) == true {
                CurrentTheme.inlineCodeBackgroundColor.setFill()
                NSBezierPath(rect: rect.offsetBy(dx: origin.x, dy: origin.y)).fill()
            }
            if (storage.attribute(.currentQuote, at: range.location, effectiveRange: nil) as? Bool) == true {
                CurrentTheme.dividerColor.setFill()
                NSBezierPath(roundedRect: NSRect(x: origin.x + 2, y: origin.y + rect.minY, width: 3, height: rect.height), xRadius: 1.5, yRadius: 1.5).fill()
            }
        }
    }

    private func drawListMarkers(forGlyphRange glyphRange: NSRange, at origin: NSPoint) {
        guard let storage = textStorage else { return }
        let characters = characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
        for key in [NSAttributedString.Key.currentTaskCheckbox, .currentListBullet] {
            storage.enumerateAttribute(key, in: characters) { value, range, _ in
                guard let value = value as? Bool,
                      (storage.attribute(.foregroundColor, at: range.location, effectiveRange: nil) as? NSColor)?.alphaComponent == 0 else { return }
                let glyphs = self.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
                guard let container = self.textContainer(forGlyphAt: glyphs.location, effectiveRange: nil) else { return }
                let bounds = self.boundingRect(forGlyphRange: glyphs, in: container).offsetBy(dx: origin.x, dy: origin.y)
                if key == .currentListBullet {
                    CurrentTheme.secondaryTextColor.setFill()
                    NSBezierPath(ovalIn: NSRect(x: bounds.midX - 2, y: bounds.midY - 2, width: 4, height: 4)).fill()
                } else {
                    let box = NSRect(x: bounds.midX - 6, y: bounds.midY - 6, width: 12, height: 12)
                    let path = NSBezierPath(roundedRect: box, xRadius: 3, yRadius: 3)
                    (value ? CurrentTheme.accentColor : CurrentTheme.mutedTextColor).setStroke()
                    path.lineWidth = 1.1
                    path.stroke()
                    if value {
                        CurrentTheme.accentColor.setFill(); path.fill()
                        let check = NSBezierPath()
                        check.move(to: NSPoint(x: box.minX + 3, y: box.midY))
                        check.line(to: NSPoint(x: box.minX + 5, y: box.maxY - 3))
                        check.line(to: NSPoint(x: box.maxX - 2.5, y: box.minY + 3))
                        NSColor.white.setStroke(); check.lineWidth = 1.4; check.stroke()
                    }
                }
            }
        }
    }

    private func drawHorizontalRules(forGlyphRange glyphRange: NSRange, at origin: NSPoint) {
        guard let textStorage, textStorage.length > 0 else { return }
        let storage = textStorage
        enumerateLineFragments(forGlyphRange: glyphRange) { lineRect, _, _, lineGlyphRange, _ in
            let range = self.characterRange(forGlyphRange: lineGlyphRange, actualGlyphRange: nil)
            guard range.location < storage.length,
                  (storage.attribute(.currentHorizontalRule, at: range.location, effectiveRange: nil) as? Bool) == true,
                  (storage.attribute(.foregroundColor, at: range.location, effectiveRange: nil) as? NSColor)?.alphaComponent == 0 else { return }
            let y = Self.horizontalRuleStrokeY(lineRect: lineRect, originY: origin.y)
            let path = NSBezierPath()
            path.lineWidth = 1
            path.move(to: NSPoint(x: origin.x + lineRect.minX, y: y))
            path.line(to: NSPoint(x: origin.x + lineRect.maxX, y: y))
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
    fileprivate var settledGeometry: (sourceRevision: Int, decorationRevision: Int, width: CGFloat, height: CGFloat)?
    fileprivate var waitsForInitialGeometry = false

    override var acceptsFirstResponder: Bool {
        (!waitsForInitialGeometry || isGeometrySettled) && super.acceptsFirstResponder
    }

    var isGeometrySettled: Bool {
        guard let settledGeometry, let storage = textStorage as? MarkdownTextStorage,
              !hasMarkedText(), !storage.suspendsDecorations, !storage.isProcessingEdit,
              let textContainer, let layoutManager,
              settledGeometry.sourceRevision == storage.sourceRevision,
              settledGeometry.decorationRevision == storage.decorationRevision,
              abs(settledGeometry.width - textContainer.containerSize.width) < 0.5,
              layoutManager.firstUnlaidCharacterIndex() >= storage.length else { return false }
        if let scrollView = enclosingScrollView,
           abs(settledGeometry.width - max(1, scrollView.contentSize.width)) >= 0.5
            || abs(settledGeometry.height - scrollView.contentSize.height) > 1 { return false }
        return true
    }

    private static var editorsByDayID: [String: WeakMarkdownTextView] = [:]
    private static var retainedSessions: [String: MarkdownTextView] = [:]
    private static var sessionOrder: [String] = []

    static func reusableEditor(for dayID: String?) -> MarkdownTextView? {
        guard let dayID, let editor = retainedSessions[dayID] else { return nil }
        if let window = editor.window {
            // Collection reuse can keep an invisible old hosting view attached
            // to its window. Transfer its document view, preserving native undo,
            // but never take a visible editor or interrupt marked-text input.
            guard !editor.hasMarkedText(),
                  editor.isHiddenOrHasHiddenAncestor || editor.visibleRect.isEmpty,
                  let oldScrollView = editor.enclosingScrollView,
                  oldScrollView.documentView === editor else { return nil }
            if window.firstResponder === editor { window.makeFirstResponder(nil) }
        }
        // A windowless old scroll view can still retain documentView and run
        // a delayed SwiftUI update. Remove that reference before any transfer.
        if let oldScrollView = editor.enclosingScrollView, oldScrollView.documentView === editor {
            oldScrollView.documentView = nil
        }
        editor.delegate = nil
        editor.onFocus = nil
        (editor.textStorage as? MarkdownTextStorage)?.onAsyncLayoutChange = nil
        sessionOrder.removeAll { $0 == dayID }
        sessionOrder.append(dayID)
        return editor
    }

    static func retainSession(_ editor: MarkdownTextView, dayID: String?) {
        guard let dayID else { return }
        retainedSessions[dayID] = editor
        sessionOrder.removeAll { $0 == dayID }
        sessionOrder.append(dayID)
        let detached = retainedSessions.values.filter { $0.window == nil && $0 !== activeEditor }
        var detachedCount = detached.count
        var cost = detached.reduce(0) { $0 + ($1.textStorage?.length ?? 0) }
        for key in sessionOrder where detachedCount > 8 || cost > 250_000 {
            guard key != dayID, let candidate = retainedSessions[key], candidate !== activeEditor,
                  candidate.window == nil else { continue }
            cost -= candidate.textStorage?.length ?? 0
            detachedCount -= 1
            retainedSessions.removeValue(forKey: key)
        }
        sessionOrder.removeAll { retainedSessions[$0] == nil }
    }
    var onFocus: (() -> Void)?
    var configuration: CurrentConfiguration = .default
    private var typingMarks = MarkdownTypingMarks()
    var currentDayID: String? {
        didSet {
            if let oldValue, oldValue != currentDayID, Self.retainedSessions[oldValue] === self {
                Self.retainedSessions.removeValue(forKey: oldValue)
                Self.sessionOrder.removeAll { $0 == oldValue }
                documentUndoManager.removeAllActions()
            }
            Self.unregister(oldValue, editor: self)
            Self.register(self, dayID: currentDayID)
        }
    }

    override func becomeFirstResponder() -> Bool {
        guard !waitsForInitialGeometry || isGeometrySettled else { return false }
        let becameFirstResponder = super.becomeFirstResponder()
        if becameFirstResponder {
            waitsForInitialGeometry = false
            Self.activeEditor = self
            onFocus?()
        }
        return becameFirstResponder
    }

    private let documentUndoManager = UndoManager()
    private var isDraggingSelection = false
    private var isInsertingStreamCompletion = false
    private var isPresentingStreamCompletions = false
    private(set) var streamCompletionScheduled = false
    private var hasStreamCompletionSession = false
    override var undoManager: UndoManager? { documentUndoManager }

    @objc func undo(_ sender: Any?) {
        guard !hasMarkedText(), documentUndoManager.canUndo else { return }
        breakUndoCoalescing()
        documentUndoManager.undo()
    }

    @objc func redo(_ sender: Any?) {
        guard !hasMarkedText(), documentUndoManager.canRedo else { return }
        breakUndoCoalescing()
        documentUndoManager.redo()
    }

    override func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        switch item.action {
        case #selector(undo(_:)): return !hasMarkedText() && documentUndoManager.canUndo
        case #selector(redo(_:)): return !hasMarkedText() && documentUndoManager.canRedo
        default: return super.validateUserInterfaceItem(item)
        }
    }

    override func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(undo(_:)) || menuItem.action == #selector(redo(_:)) {
            return validateUserInterfaceItem(menuItem)
        }
        return super.validateMenuItem(menuItem)
    }

    override var rangeForUserCompletion: NSRange {
        guard !hasMarkedText(), let storage = textStorage as? MarkdownTextStorage,
              let completion = storage.streamLinkCompletion(at: selectedRange()) else { return super.rangeForUserCompletion }
        return completion.replacementRange
    }

    override func completions(forPartialWordRange charRange: NSRange, indexOfSelectedItem index: UnsafeMutablePointer<Int>) -> [String]? {
        guard !hasMarkedText(), let storage = textStorage as? MarkdownTextStorage,
              let completion = storage.streamLinkCompletion(at: selectedRange()),
              completion.replacementRange == charRange else {
            hasStreamCompletionSession = false
            return super.completions(forPartialWordRange: charRange, indexOfSelectedItem: index)
        }
        hasStreamCompletionSession = !completion.matches.isEmpty
        index.pointee = -1
        return completion.matches.map(\.insertionText)
    }

    override func insertCompletion(_ word: String, forPartialWordRange charRange: NSRange, movement: Int, isFinal flag: Bool) {
        isInsertingStreamCompletion = true
        defer { isInsertingStreamCompletion = false }
        if hasStreamCompletionSession {
            // Keep candidate previews out of the document and its undo history.
            // AppKit's default completion replaces only the prefix before the
            // caret; stream links must also replace an existing closing pair.
            guard flag else { return }
            hasStreamCompletionSession = false
            guard movement != NSTextMovement.cancel.rawValue, !hasMarkedText(),
                  let storage = textStorage as? MarkdownTextStorage,
                  let completion = storage.streamLinkCompletion(at: selectedRange()),
                  completion.matches.contains(where: { $0.insertionText == word }) else { return }
            let source = storage.string
            let selection = selectedRange()
            let dayID = currentDayID
            // AppKit finishes restoring its tracked partial-word selection
            // after this callback. Commit on the following turn so that cleanup
            // cannot roll back the accepted link or its canonical binding.
            DispatchQueue.main.async { [weak self] in
                guard let self, !self.hasMarkedText(), self.currentDayID == dayID,
                      self.string == source, self.selectedRange() == selection,
                      let storage = self.textStorage as? MarkdownTextStorage,
                      let current = storage.streamLinkCompletion(at: selection),
                      current.replacementRange == completion.replacementRange,
                      current.matches.contains(where: { $0.insertionText == word }) else { return }
                self.isInsertingStreamCompletion = true
                defer { self.isInsertingStreamCompletion = false }
                self.breakUndoCoalescing()
                self.setSelectedRange(current.replacementRange)
                self.insertText(word, replacementRange: current.replacementRange)
                self.breakUndoCoalescing()
            }
            return
        }
        super.insertCompletion(word, forPartialWordRange: charRange, movement: movement, isFinal: flag)
    }

    func scheduleStreamCompletion() {
        // AppKit can dismiss its popup when typing without sending a final
        // insertCompletion callback. A previous candidate query must never
        // prevent a new request after the source changes.
        guard !streamCompletionScheduled, !isPresentingStreamCompletions, !isInsertingStreamCompletion,
              !isDraggingSelection, !hasMarkedText(), let storage = textStorage as? MarkdownTextStorage,
              let completion = storage.streamLinkCompletion(at: selectedRange()), !completion.matches.isEmpty else { return }
        streamCompletionScheduled = true
        let dayID = currentDayID
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.streamCompletionScheduled = false
            guard let window = self.window, window.firstResponder === self, window.attachedSheet == nil,
                  !self.hasMarkedText(), self.currentDayID == dayID,
                  let storage = self.textStorage as? MarkdownTextStorage,
                  let completion = storage.streamLinkCompletion(at: self.selectedRange()),
                  !completion.matches.isEmpty else { return }
            self.isPresentingStreamCompletions = true
            self.complete(nil)
            self.isPresentingStreamCompletions = false
        }
    }

    func endStreamCompletion() { hasStreamCompletionSession = false }

    override func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        (textStorage as? MarkdownTextStorage)?.suspendsDecorations = true
        super.setMarkedText(string, selectedRange: selectedRange, replacementRange: replacementRange)
    }

    override func unmarkText() {
        super.unmarkText()
        finishCompositionIfNeeded()
    }

    private func finishCompositionIfNeeded() {
        guard !hasMarkedText(), !isDraggingSelection, let storage = textStorage as? MarkdownTextStorage else { return }
        let revision = storage.decorationRevision
        storage.updateSelectedRange(window?.firstResponder === self ? selectedRange() : nil)
        storage.suspendsDecorations = false
        if storage.decorationRevision != revision { storage.onAsyncLayoutChange?() }
    }

    override func mouseDown(with event: NSEvent) {
        if toggleCheckbox(at: event) { return }
        isDraggingSelection = true
        (textStorage as? MarkdownTextStorage)?.suspendsDecorations = true
        super.mouseDown(with: event)
        isDraggingSelection = false
        finishCompositionIfNeeded()
    }

    private func toggleCheckbox(at event: NSEvent) -> Bool {
        guard event.clickCount == 1, let storage = textStorage as? MarkdownTextStorage,
              !storage.sourceMode, let manager = layoutManager, let container = textContainer else { return false }
        let point = convert(event.locationInWindow, from: nil)
        let local = NSPoint(x: point.x - textContainerOrigin.x, y: point.y - textContainerOrigin.y)
        let glyph = manager.glyphIndex(for: local, in: container)
        guard glyph < manager.numberOfGlyphs else { return false }
        let character = manager.characterIndexForGlyph(at: glyph)
        guard character < storage.length else { return false }
        var marker = NSRange()
        guard storage.attribute(.currentTaskCheckbox, at: character, effectiveRange: &marker) is Bool,
              marker.length == 3 else { return false }
        let rect = manager.boundingRect(forGlyphRange: manager.glyphRange(forCharacterRange: marker, actualCharacterRange: nil), in: container)
        guard rect.insetBy(dx: -3, dy: -2).contains(local) else { return false }
        let checked = (storage.attribute(.currentTaskCheckbox, at: character, effectiveRange: nil) as? Bool) == true
        let range = NSRange(location: marker.location + 1, length: 1)
        let replacement = checked ? " " : "x"
        guard shouldChangeText(in: range, replacementString: replacement) else { return false }
        storage.replaceCharacters(in: range, with: replacement)
        didChangeText()
        return true
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
        defer { finishCompositionIfNeeded() }
        let insertionRange = replacementRange.location == NSNotFound ? selectedRange() : replacementRange
        guard !hasMarkedText(), let insertedText = Self.plainString(from: insertString),
              insertionRange.length == 0,
              !typingMarks.isEmpty,
              !insertedText.isEmpty,
              insertedText.rangeOfCharacter(from: .newlines) == nil else {
            super.insertText(insertString, replacementRange: replacementRange)
            return
        }

        let model = (textStorage as? MarkdownTextStorage)?.renderModel ?? MarkdownEditorRenderModel(text: string)
        if typingMarks.isSatisfied(by: model.inlineMarks(at: insertionRange.location)) {
            super.insertText(insertString, replacementRange: replacementRange)
            return
        }

        let wrapped = typingMarks.wrap(insertedText)
        super.insertText(wrapped.replacement, replacementRange: replacementRange)
        setSelectedRange(NSRange(location: insertionRange.location + wrapped.visibleOffset, length: 0))
    }

    override func selectionRange(
        forProposedRange proposedCharRange: NSRange,
        granularity: NSSelectionGranularity
    ) -> NSRange {
        let proposed = super.selectionRange(forProposedRange: proposedCharRange, granularity: granularity)
        guard let storage = textStorage as? MarkdownTextStorage, !storage.sourceMode, !storage.suspendsDecorations, !hasMarkedText() else { return proposed }
        return storage.renderModel.normalizedVisibleSelection(proposed)
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
        if pasteImage(from: .general) { return }
        if let text = MarkdownPasteConverter.bestString(from: NSPasteboard.general) {
            insertText(text, replacementRange: selectedRange())
            return
        }
        super.paste(sender)
    }

    override func pasteAsPlainText(_ sender: Any?) {
        if let text = NSPasteboard.general.string(forType: .string) {
            insertText(text, replacementRange: selectedRange())
        } else { super.pasteAsPlainText(sender) }
    }

    private static let imageExtensions = Set(["png", "jpg", "jpeg", "gif", "heic", "heif", "tiff", "tif", "webp", "bmp"])

    private func imageFiles(in pasteboard: NSPasteboard) -> [URL] {
        let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        guard !urls.isEmpty, urls.allSatisfy({ Self.imageExtensions.contains($0.pathExtension.lowercased()) }) else { return [] }
        return urls
    }

    private func canImportImage(from pasteboard: NSPasteboard) -> Bool {
        (textStorage as? MarkdownTextStorage)?.documentURL != nil &&
            (!imageFiles(in: pasteboard).isEmpty || pasteboard.availableType(from: [.png, .tiff]) != nil)
    }

    @discardableResult
    func pasteImage(from pasteboard: NSPasteboard) -> Bool {
        guard canImportImage(from: pasteboard), let documentURL = (textStorage as? MarkdownTextStorage)?.documentURL else { return false }
        do {
            let files = imageFiles(in: pasteboard)
            let sources: [String]
            if !files.isEmpty {
                sources = try files.map { try MarkdownRichBlocks.importImage(from: $0, documentURL: documentURL) }
            } else if let type = pasteboard.availableType(from: [.png, .tiff]), let data = pasteboard.data(forType: type) {
                sources = [try MarkdownRichBlocks.importImage(data: data, fileExtension: type == .png ? "png" : "tiff", documentURL: documentURL)]
            } else { return false }
            let selection = selectedRange()
            let source = string as NSString
            let needsLeadingNewline = selection.location > 0 && source.character(at: selection.location - 1) != 10
            let insertion = (needsLeadingNewline ? "\n" : "") + sources.joined(separator: "\n") + "\n"
            breakUndoCoalescing()
            insertText(insertion, replacementRange: selection)
            breakUndoCoalescing()
            return true
        } catch {
            NSApp.presentError(error)
            return true
        }
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        canImportImage(from: sender.draggingPasteboard) ? .copy : super.draggingEntered(sender)
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        canImportImage(from: sender.draggingPasteboard) ? .copy : super.draggingUpdated(sender)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard canImportImage(from: sender.draggingPasteboard) else { return super.performDragOperation(sender) }
        let point = convert(sender.draggingLocation, from: nil)
        setSelectedRange(NSRange(location: characterIndexForInsertion(at: point), length: 0))
        return pasteImage(from: sender.draggingPasteboard)
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

final class MarkdownEditorScrollView: NSScrollView {
    var onWidthChange: (() -> Void)?
    private var widthMeasurementScheduled = false

    override func setFrameSize(_ newSize: NSSize) {
        let oldHeight = frame.height
        let oldWidth = frame.width
        super.setFrameSize(newSize)
        if abs(frame.height - oldHeight) > 0.5 {
            DispatchQueue.main.async { [weak self] in
                guard let editor = self?.documentView as? MarkdownTextView, editor.isGeometrySettled else { return }
                NotificationCenter.default.post(name: Notification.Name("Current.editorLayoutSettled"), object: editor)
            }
        }
        guard abs(frame.width - oldWidth) > 0.5, !widthMeasurementScheduled else { return }
        widthMeasurementScheduled = true
        // Native layout can resize the editor without a SwiftUI update. Measure
        // after tiling so its enclosing row receives the new wrapped height.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.widthMeasurementScheduled = false
            self.onWidthChange?()
        }
    }
}

struct MarkdownEditorView: NSViewRepresentable {
    @Binding var text: String
    @Binding var measuredHeight: CGFloat
    var dayID: String?
    var configuration: CurrentConfiguration = .default
    var sourceMode: Bool = false
    var documentURL: URL? = nil
    var focusOnAppear: Bool
    var minimumHeight: CGFloat = 72
    var onFocus: () -> Void = {}
    var streamLinkTargets: [MarkdownStreamLinkTarget] = []
    var onOpenStream: (UUID) -> Void = { _ in }

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
        let scrollView = MarkdownEditorScrollView()
        scrollView.onWidthChange = { [weak scrollView, weak coordinator = context.coordinator] in
            guard let scrollView else { return }
            coordinator?.remeasure(in: scrollView)
        }
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder

        let reused = MarkdownTextView.reusableEditor(for: dayID)
        let textView: MarkdownTextView
        if let reused {
            textView = reused
            if textView.string != text {
                textView.string = text
                textView.undoManager?.removeAllActions()
            }
            if let storage = textView.textStorage as? MarkdownTextStorage {
                storage.configuration = configuration
                storage.sourceMode = sourceMode
            }
        } else {
            let textStorage = MarkdownTextStorage(string: text, configuration: configuration)
            textStorage.sourceMode = sourceMode
            let layoutManager = MarkdownLayoutManager()
            let textContainer = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
            textStorage.addLayoutManager(layoutManager)
            layoutManager.addTextContainer(textContainer)
            textView = MarkdownTextView(frame: .zero, textContainer: textContainer)
        }
        MarkdownTextView.retainSession(textView, dayID: dayID)
        if let storage = textView.textStorage as? MarkdownTextStorage {
            storage.documentURL = documentURL
            storage.streamLinkTargets = streamLinkTargets
            storage.onAsyncLayoutChange = { [weak scrollView] in
                guard let scrollView else { return }
                context.coordinator.remeasure(in: scrollView)
            }
        }
        textView.configuration = configuration
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.importsGraphics = false
        textView.registerForDraggedTypes(textView.registeredDraggedTypes + [.fileURL, .png, .tiff])
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
            .foregroundColor: CurrentTheme.accentColor,
            .underlineStyle: 0
        ]
        textView.backgroundColor = CurrentTheme.editorBackground
        textView.drawsBackground = true
        textView.insertionPointColor = CurrentTheme.primaryTextColor
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
        textView.settledGeometry = nil
        textView.waitsForInitialGeometry = !focusOnAppear
        context.coordinator.updateTypingAttributes(for: textView)
        scrollView.documentView = textView

        DispatchQueue.main.async {
            context.coordinator.remeasure(in: scrollView)
            if focusOnAppear, !context.coordinator.didFocusInitially,
               textView.currentDayID == dayID, context.coordinator.textView === textView,
               scrollView.documentView === textView, textView.delegate === context.coordinator,
               let window = textView.window, window.isKeyWindow, window.attachedSheet == nil,
               !((window.firstResponder as? NSTextView)?.isFieldEditor ?? false) {
                context.coordinator.didFocusInitially = true
                window.makeFirstResponder(textView)
                if reused == nil { textView.setSelectedRange(NSRange(location: textView.string.utf16.count, length: 0)) }
                (textView.textStorage as? MarkdownTextStorage)?.updateSelectedRange(textView.selectedRange())
                textView.scrollRangeToVisible(textView.selectedRange())
            }
        }

        return scrollView
    }

    static func dismantleNSView(_ scrollView: NSScrollView, coordinator: Coordinator) {
        guard let textView = scrollView.documentView as? MarkdownTextView,
              textView.delegate === coordinator else { return }
        textView.endStreamCompletion()
        textView.delegate = nil
        textView.onFocus = nil
        (textView.textStorage as? MarkdownTextStorage)?.onAsyncLayoutChange = nil
        if textView.window?.firstResponder === textView { textView.window?.makeFirstResponder(nil) }
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let configurationChanged = context.coordinator.highlightedConfiguration != configuration
        context.coordinator.parent = self
        guard let textView = scrollView.documentView as? MarkdownTextView,
              textView.delegate === context.coordinator else { return }
        let textChanged = !context.coordinator.isUpdatingFromTextView && textView.string != text
        let widthChanged = abs(context.coordinator.lastMeasuredWidth - scrollView.contentSize.width) > 1
        let minimumHeightChanged = abs(context.coordinator.lastMeasuredMinimumHeight - minimumHeight) > 0.5
        let sourceModeChanged = (textView.textStorage as? MarkdownTextStorage)?.sourceMode != sourceMode

        textView.currentDayID = dayID
        (textView.textStorage as? MarkdownTextStorage)?.documentURL = documentURL
        (textView.textStorage as? MarkdownTextStorage)?.streamLinkTargets = streamLinkTargets
        textView.onFocus = {
            context.coordinator.parent.onFocus()
        }

        guard textChanged || configurationChanged || widthChanged || sourceModeChanged || minimumHeightChanged else { return }

        textView.backgroundColor = CurrentTheme.editorBackground
        textView.insertionPointColor = CurrentTheme.primaryTextColor
        if sourceModeChanged { (textView.textStorage as? MarkdownTextStorage)?.sourceMode = sourceMode }
        if configurationChanged || sourceModeChanged {
            textView.configuration = configuration
            (textView.textStorage as? MarkdownTextStorage)?.configuration = configuration
            context.coordinator.updateTypingAttributes(for: textView)
        }

        if textChanged {
            context.coordinator.isUpdatingFromSwiftUI = true
            let selection = textView.selectedRange()
            textView.string = text
            let length = (textView.string as NSString).length
            let location = min(selection.location, length)
            textView.setSelectedRange(NSRange(location: location, length: min(selection.length, length - location)))
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
        var lastMeasuredMinimumHeight: CGFloat = -1
        private var lastMeasuredRevision = -1
        private var lastMeasuredSourceRevision = -1
        private var lastNaturalHeight: CGFloat?
        private var publicationScheduled = false
        private var finalMeasurementScheduled = false
        private var pendingHeight: CGFloat?
        private var pendingHeightNotification = false
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
            textView.endStreamCompletion()
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
            if let scrollView = textView.enclosingScrollView { remeasure(in: scrollView) }
            parent.text = textView.string
            isUpdatingFromTextView = false
            textView.scheduleStreamCompletion()
        }

        func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
            guard let url = link as? URL, url.scheme == "inkpad-stream" else { return false }
            if let host = url.host, let id = UUID(uuidString: host),
               parent.streamLinkTargets.contains(where: { $0.id == id }) {
                parent.onOpenStream(id)
            }
            return true
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard !isUpdatingFromSwiftUI, let textView = notification.object as? MarkdownTextView else { return }
            if !isNormalizingSelection {
                let selection = textView.selectedRange()
                let storage = textView.textStorage as? MarkdownTextStorage
                let normalizedSelection = storage?.sourceMode == true || storage?.suspendsDecorations == true || textView.hasMarkedText()
                    ? selection : storage?.renderModel.normalizedVisibleSelection(selection) ?? selection
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
                  textView.delegate === self,
                  let layoutManager = textView.layoutManager,
                  let textContainer = textView.textContainer else { return }

            let storage = textView.textStorage as? MarkdownTextStorage
            // Native selection notifications can arrive before text storage
            // sends its final glyph invalidation. Measuring then caches an old
            // row height even though the following draw has the correct glyphs.
            if storage?.isProcessingEdit == true {
                guard !finalMeasurementScheduled else { return }
                finalMeasurementScheduled = true
                DispatchQueue.main.async { [weak self, weak scrollView] in
                    guard let self else { return }
                    self.finalMeasurementScheduled = false
                    if let scrollView { self.remeasure(in: scrollView) }
                }
                return
            }
            let width = max(1, scrollView.contentSize.width)
            if lastMeasuredRevision == storage?.decorationRevision, lastMeasuredSourceRevision == storage?.sourceRevision,
               abs(lastMeasuredWidth - width) < 0.5,
               abs(lastMeasuredMinimumHeight - parent.minimumHeight) < 0.5 { return }
            storage?.renderWidth = width
            textContainer.containerSize = NSSize(width: width, height: CGFloat.greatestFiniteMagnitude)
            layoutManager.ensureLayout(for: textContainer)
            let used = layoutManager.usedRect(for: textContainer)
            let target = max(parent.minimumHeight, ceil(used.height + textView.textContainerInset.height * 2 + 6))
            lastMeasuredWidth = width
            lastMeasuredMinimumHeight = parent.minimumHeight
            lastMeasuredRevision = storage?.decorationRevision ?? -1
            lastMeasuredSourceRevision = storage?.sourceRevision ?? -1
            MarkdownTextLayoutMeasurer.rememberHeight(ceil(used.height + textView.textContainerInset.height * 2 + 6), text: textView.string, width: width,
                                                       configuration: parent.configuration, sourceMode: parent.sourceMode,
                                                       selectedRange: storage?.selectedRange, documentURL: parent.documentURL)
            let naturalHeight = ceil(used.height + textView.textContainerInset.height * 2 + 6)
            if isUpdatingFromSwiftUI {
                pendingHeight = target
            } else {
                // Representable updates already schedule this measurement after
                // SwiftUI's update. Publish its frame before the collection's
                // next caret restoration uses the native view's coordinates.
                pendingHeight = nil
                if abs(parent.measuredHeight - target) > 1 { parent.measuredHeight = target }
            }
            if let previous = lastNaturalHeight, abs(previous - naturalHeight) > 0.5 { pendingHeightNotification = true }
            lastNaturalHeight = naturalHeight
            publishGeometry(for: textView)
        }

        private func publishGeometry(for textView: MarkdownTextView) {
            guard !publicationScheduled else { return }
            publicationScheduled = true
            // The outer collection updates after the host has received its
            // measured height; coalesce repeated native layout notifications.
            DispatchQueue.main.async { [weak self, weak textView] in
                guard let self else { return }
                self.publicationScheduled = false
                guard let textView, textView.currentDayID == self.parent.dayID,
                      textView.delegate === self else { return }
                if let height = self.pendingHeight {
                    self.pendingHeight = nil
                    if abs(self.parent.measuredHeight - height) > 1 { self.parent.measuredHeight = height }
                }
                textView.settledGeometry = (self.lastMeasuredSourceRevision, self.lastMeasuredRevision, self.lastMeasuredWidth,
                                           max(self.parent.minimumHeight, self.lastNaturalHeight ?? self.parent.minimumHeight))
                if self.pendingHeightNotification, let dayID = self.parent.dayID {
                    NotificationCenter.default.post(name: Notification.Name("Current.editorHeightChanged"), object: textView, userInfo: ["dayID": dayID])
                }
                self.pendingHeightNotification = false
                // Height observers update their collection rows on the next
                // turn. Let them finish before resolving a saved source line.
                DispatchQueue.main.async { [weak self, weak textView] in
                    guard let self, let textView, textView.currentDayID == self.parent.dayID,
                          textView.delegate === self, textView.isGeometrySettled else { return }
                    NotificationCenter.default.post(name: Notification.Name("Current.editorLayoutSettled"), object: textView)
                }
            }
        }

        func updateTypingAttributes(for textView: NSTextView) {
            guard !textView.hasMarkedText() else { return }
            var attributes = MarkdownEditorView.plainTypingAttributes(configuration: parent.configuration)

            let selection = textView.selectedRange()
            let model = (textView.textStorage as? MarkdownTextStorage)?.renderModel ?? MarkdownEditorRenderModel(text: textView.string)
            if parent.sourceMode {
                attributes[.font] = CurrentTheme.editorCodeFont(configuration: parent.configuration)
            } else if selection.length == 0,
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
