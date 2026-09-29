import AppKit
import CoreText
import SwiftUI
import Testing
@testable import CurrentFeature

@Suite(.serialized)
@MainActor
struct MarkdownRendererTests {
    @Test func fencesProtectUnfinishedAndTildeSource() {
        for source in ["```swift\n**literal**\n", "~~~swift\n# literal\n**literal**\n~~~\n", "````swift\n```\n**literal**\n````\n"] {
            let model = MarkdownEditorRenderModel(text: source)
            #expect(model.protectedRanges.count == 1)
            #expect(model.inlineSpans.isEmpty)
            #expect(model.headings.isEmpty)
        }
        let source = "~~~\ncode\n~~~suffix\n**literal**\n~~~\n**bold**"
        let model = MarkdownEditorRenderModel(text: source)
        #expect(model.inlineSpans.count == 1)
        #expect((source as NSString).substring(with: model.inlineSpans[0].contentRange) == "bold")
    }

    @Test func oldFenceExtentIsInvalidatedWhenOpeningIsDeleted() {
        let source = "```swift\nlet x = 1\nlet y = 2\nlet z = 3\n**now bold**\n```\n"
        let storage = MarkdownTextStorage(string: source)
        storage.replaceCharacters(in: NSRange(location: 0, length: 3), with: "")
        let expected = MarkdownTextStorage(string: storage.string)
        let matches = sameRendering(storage, expected)
        #expect(matches)
        let bold = (storage.string as NSString).range(of: "**now bold**")
        #expect(storage.attribute(.currentHiddenMarkdownSyntax, at: bold.location, effectiveRange: nil) as? Bool == true)
    }

    @Test func inactiveBlocksHideMarkersAndActiveBlocksRevealTheirSource() {
        let source = "# Title\n> quote\n- [ ] task\n~~~swift\nlet value = 1\n~~~\n"
        let storage = MarkdownTextStorage(string: source)
        let text = source as NSString
        for token in ["# ", "> ", "- ", "~~~swift"] {
            let index = text.range(of: token).location
            #expect(storage.attribute(.foregroundColor, at: index, effectiveRange: nil) as? NSColor == NSColor.clear)
        }
        #expect((storage.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)?.pointSize == 0.01)
        let codeLocation = text.range(of: "let value").location
        storage.updateSelectedRange(NSRange(location: codeLocation, length: 0))
        let fence = text.range(of: "~~~swift").location
        #expect((storage.attribute(.foregroundColor, at: fence, effectiveRange: nil) as? NSColor)?.alphaComponent != 0)
        #expect(storage.string == source)
    }

    @Test func nativeSessionReuseKeepsDocumentIdentityAndUndoOwnership() {
        let id = "renderer-test-" + UUID().uuidString
        let storage = MarkdownTextStorage(string: "first")
        let manager = MarkdownLayoutManager()
        let container = NSTextContainer(size: NSSize(width: 500, height: CGFloat.greatestFiniteMagnitude))
        storage.addLayoutManager(manager); manager.addTextContainer(container)
        let view = MarkdownTextView(frame: .zero, textContainer: container)
        view.currentDayID = id
        let oldScroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 500, height: 300))
        oldScroll.documentView = view
        view.setSelectedRange(NSRange(location: 2, length: 0))
        MarkdownTextView.retainSession(view, dayID: id)
        let undo = view.undoManager
        let reused = MarkdownTextView.reusableEditor(for: id)
        #expect(reused === view)
        #expect(oldScroll.documentView == nil)
        #expect(reused?.undoManager === undo)
        #expect(reused?.selectedRange().location == 2)
        view.currentDayID = id + "-other"
        #expect(MarkdownTextView.reusableEditor(for: id) == nil)
    }

    @Test func hiddenWindowAttachedSessionTransfersWithoutLosingUndo() {
        let id = "hidden-session-test-" + UUID().uuidString
        let storage = MarkdownTextStorage(string: "source")
        let manager = MarkdownLayoutManager()
        let container = NSTextContainer(size: NSSize(width: 500, height: CGFloat.greatestFiniteMagnitude))
        storage.addLayoutManager(manager)
        manager.addTextContainer(container)
        let view = MarkdownTextView(frame: NSRect(x: 0, y: 0, width: 500, height: 100), textContainer: container)
        view.currentDayID = id
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 300), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let oldScroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 500, height: 300))
        oldScroll.documentView = view
        window.contentView = oldScroll
        MarkdownTextView.retainSession(view, dayID: id)
        #expect(view.window === window)
        #expect(MarkdownTextView.reusableEditor(for: id) == nil)
        let undo = view.undoManager!
        undo.registerUndo(withTarget: view) { _ in }
        oldScroll.isHidden = true
        let transferred = MarkdownTextView.reusableEditor(for: id)
        #expect(transferred === view)
        #expect(oldScroll.documentView == nil)
        #expect(transferred?.undoManager === undo)
        #expect(transferred?.undoManager?.canUndo == true)
        let nextScroll = NSScrollView(frame: oldScroll.frame)
        nextScroll.documentView = transferred
        #expect(nextScroll.documentView === view)
    }

    @Test func sourceRevisionIsParsedOnceAndSelectionReusesIt() {
        let source = "**first** and _second_\n# Heading\n- [ ] task\n"
        let storage = MarkdownTextStorage(string: source)
        let initial = storage.parseCount
        storage.updateSelectedRange(NSRange(location: 3, length: 0))
        let decorated = storage.decorationRevision
        for offset in 4...8 { storage.updateSelectedRange(NSRange(location: offset, length: 0)) }
        #expect(storage.parseCount == initial)
        #expect(storage.decorationRevision == decorated)
        storage.updateSelectedRange(NSRange(location: 24, length: 0))
        #expect(storage.parseCount == initial)
        storage.replaceCharacters(in: NSRange(location: 4, length: 0), with: "🙂")
        #expect(storage.parseCount == initial + 1)
        _ = storage.renderModel
        #expect(storage.parseCount == initial + 1)
    }

    @Test func scopedEditsMatchFreshFullDecoration() {
        let storage = MarkdownTextStorage(string: "# Heading\n\n**bold** and _italic_\n\n~~~swift\n# literal\n~~~\n- [ ] task\n---\n")
        let edits: [(String, String)] = [("~~~swift", "plain"), ("# Heading", "Heading"), ("**bold**", "ordinary"), ("plain", "```"), ("~~~", "```"), ("[ ]", "[x]"), ("---", "paragraph")]
        for (find, replace) in edits {
            let range = (storage.string as NSString).range(of: find)
            #expect(range.location != NSNotFound)
            storage.replaceCharacters(in: range, with: replace)
            let expected = MarkdownTextStorage(string: storage.string)
            let matches = sameRendering(storage, expected)
            #expect(matches, "Scoped styling differs after replacing \(find)")
        }
        storage.beginEditing()
        storage.replaceCharacters(in: NSRange(location: 0, length: 0), with: "```\n")
        storage.replaceCharacters(in: NSRange(location: storage.length, length: 0), with: "\n```\n")
        storage.endEditing()
        let matches = sameRendering(storage, MarkdownTextStorage(string: storage.string))
        #expect(matches)
    }

    @Test func sourceModeAndCompositionDoNotMutateSource() {
        let source = "# Heading\n**bold** and `code`\n"
        let storage = MarkdownTextStorage(string: source)
        let parsed = storage.parseCount
        storage.sourceMode = true
        #expect(storage.string == source)
        let marker = (source as NSString).range(of: "**")
        #expect(storage.attribute(.currentHiddenMarkdownSyntax, at: marker.location, effectiveRange: nil) as? Bool == false)
        storage.sourceMode = false
        #expect(storage.string == source)
        #expect(storage.parseCount == parsed)
        storage.suspendsDecorations = true
        let revision = storage.decorationRevision
        storage.replaceCharacters(in: NSRange(location: storage.length, length: 0), with: "に")
        storage.replaceCharacters(in: NSRange(location: storage.length - 1, length: 1), with: "日本語")
        storage.updateSelectedRange(NSRange(location: storage.length, length: 0))
        #expect(storage.decorationRevision == revision)
        #expect(storage.parseCount == parsed)
        storage.suspendsDecorations = false
        #expect(storage.parseCount == parsed + 1)
        #expect(storage.string == source + "日本語")
    }

    @Test func inlineCodeEscapesAndIdentifiersRemainLiteral() {
        let source = "`**literal**` \\*literal\\* some_identifier_name ***both***"
        let model = MarkdownEditorRenderModel(text: source)
        #expect(model.inlineSpans.filter { $0.kind == .inlineCode }.count == 1)
        let content = model.inlineSpans.filter { $0.kind != .inlineCode }.map { (source as NSString).substring(with: $0.contentRange) }
        #expect(content == ["both", "both"])
    }

    @Test func longerInlineCodeDelimitersProtectShortBackticksAndStreamSyntax() {
        let source = "``literal ` [[Daily]] **not bold**`` and `code`"
        let storage = MarkdownTextStorage(string: source)
        storage.streamLinkTargets = [MarkdownStreamLinkTarget(id: UUID(), name: "Daily")]
        let spans = storage.renderModel.inlineSpans
        #expect(spans.count == 2)
        #expect(spans.allSatisfy { $0.kind == .inlineCode })
        #expect((source as NSString).substring(with: spans[0].contentRange) == "literal ` [[Daily]] **not bold**")
        #expect(storage.resolvedStreamLinks.isEmpty)
        let cursor = (source as NSString).range(of: "Daily").location + 2
        #expect(storage.streamLinkCompletion(at: NSRange(location: cursor, length: 0)) == nil)
        let backslash = MarkdownTextStorage(string: #"`[[Daily]]\`"#)
        backslash.streamLinkTargets = storage.streamLinkTargets
        #expect(backslash.renderModel.inlineSpans.count == 1)
        #expect(backslash.resolvedStreamLinks.isEmpty)
    }

    @Test func drawAndLayoutReuseTheCachedModel() {
        let storage = MarkdownTextStorage(string: "# Heading\n" + String(repeating: "A **bold** sentence.\n", count: 200) + "---\n")
        let manager = MarkdownLayoutManager()
        let container = NSTextContainer(size: NSSize(width: 680, height: CGFloat.greatestFiniteMagnitude))
        storage.addLayoutManager(manager)
        manager.addTextContainer(container)
        let before = storage.parseCount
        manager.ensureLayout(for: container)
        #expect(manager.usedRect(for: container).height > 0)
        #expect(storage.parseCount == before)
    }

    @Test func trailingNewlineCaretUsesTheExtraLineFragment() {
        let storage = MarkdownTextStorage(string: String(repeating: "A paragraph.\n", count: 50))
        let manager = MarkdownLayoutManager()
        let container = NSTextContainer(size: NSSize(width: 680, height: CGFloat.greatestFiniteMagnitude))
        storage.addLayoutManager(manager)
        manager.addTextContainer(container)
        let view = MarkdownTextView(frame: NSRect(x: 0, y: 0, width: 680, height: 1600), textContainer: container)
        view.setSelectedRange(NSRange(location: storage.length, length: 0))
        for sourceMode in [false, true] {
            storage.sourceMode = sourceMode
            let caret = MarkdownVisibleCaret.insertionRect(in: view)
            #expect(caret != nil)
            #expect(caret?.height == manager.extraLineFragmentRect.height)
            #expect(caret?.minY == manager.extraLineFragmentRect.minY + view.textContainerOrigin.y)
        }
    }

    @Test func collapsedBoldMarkersHaveTheSameGeometryAsBoldContent() {
        let source = MarkdownTextStorage(string: "**xxxxxxxxxx**")
        let rendered = NSTextStorage(attributedString: source.attributedSubstring(from: NSRange(location: 2, length: 10)))
        var heights: [CGFloat] = []
        for storage in [source as NSTextStorage, rendered] {
            let manager = MarkdownLayoutManager()
            let container = NSTextContainer(size: NSSize(width: 80, height: CGFloat.greatestFiniteMagnitude))
            container.lineFragmentPadding = 0
            storage.addLayoutManager(manager)
            manager.addTextContainer(container)
            manager.ensureLayout(for: container)
            heights.append(manager.usedRect(for: container).height)
        }
        #expect(heights[0] == heights[1])
    }

    @Test func taskStatesAndBulletsKeepAnEqualMarkerGutter() {
        let storage = MarkdownTextStorage(string: "- [ ] unchecked\n- [x] checked\n- [X] checked\n- bullet\n")
        let manager = MarkdownLayoutManager()
        let container = NSTextContainer(size: NSSize(width: 680, height: CGFloat.greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        storage.addLayoutManager(manager)
        manager.addTextContainer(container)
        manager.ensureLayout(for: container)
        let starts = storage.renderModel.lists.map { list in
            let glyph = manager.glyphIndexForCharacter(at: NSMaxRange(list.prefixRange))
            return manager.location(forGlyphAt: glyph).x
        }
        #expect(starts.count == 4)
        #expect(starts.allSatisfy { abs($0 - starts[0]) < 0.5 }, "Rendered list content starts: \(starts)")
    }

    @Test func minimumHeightChangeRemeasuresAnUnchangedNote() {
        var measuredHeight: CGFloat = 0
        let editor = MarkdownEditorView(text: .constant("short"),
            measuredHeight: Binding(get: { measuredHeight }, set: { measuredHeight = $0 }),
            dayID: nil, focusOnAppear: false, minimumHeight: 128)
        let coordinator = MarkdownEditorView.Coordinator(editor)
        let storage = MarkdownTextStorage(string: "short")
        let manager = MarkdownLayoutManager()
        let container = NSTextContainer(size: NSSize(width: 500, height: CGFloat.greatestFiniteMagnitude))
        storage.addLayoutManager(manager)
        manager.addTextContainer(container)
        let view = MarkdownTextView(frame: NSRect(x: 0, y: 0, width: 500, height: 300), textContainer: container)
        let scroll = NSScrollView(frame: view.frame)
        scroll.documentView = view
        view.delegate = coordinator
        coordinator.textView = view
        coordinator.remeasure(in: scroll)
        #expect(measuredHeight == 128)
        coordinator.parent.minimumHeight = 64
        coordinator.remeasure(in: scroll)
        #expect(measuredHeight == 64)
    }
    @Test func nativePasteAndRapidEditsMatchFreshGlyphsAndLineFragments() throws {
        let live = NativeEditorFixture(mounted: true)
        defer { live.window?.close() }
        let source = """
        # Release plan
        A paragraph with **bold**, _italic_, and `literal code`.

        ## Implementation
        ```swift
        let greeting = "Hello world"
        print(greeting)
        ```

        ### Verification
        - [ ] Paste, type, delete, and undo
        > Keep the source exact.

        """
        try insert(source, into: live)
        try assertMatchesFresh(live, after: "multiline paste")
        for token in ["Release plan", "Implementation", "greeting", "print(greeting)", "Verification"] {
            let range = (live.storage.string as NSString).range(of: token)
            live.view.setSelectedRange(NSRange(location: NSMaxRange(range), length: 0))
            try assertMatchesFresh(live, after: "select \(token)")
            for character in " added🙂" {
                try insert(String(character), into: live)
                try assertMatchesFresh(live, after: "type \(character) in \(token)")
            }
            for _ in 0..<3 {
                let selection = live.view.selectedRange()
                let deleted = (live.storage.string as NSString).rangeOfComposedCharacterSequence(at: selection.location - 1)
                let expected = (live.storage.string as NSString).replacingCharacters(in: deleted, with: "")
                live.view.deleteBackward(nil)
                try #require(live.storage.string == expected)
                try #require(live.view.selectedRange() == NSRange(location: deleted.location, length: 0))
                try assertMatchesFresh(live, after: "delete in \(token)")
            }
        }
        for (find, replacement) in [("```swift", "plain"), ("plain", "~~~swift"), ("```", "~~~"), ("# Release", "Release"), ("Release", "# Release")] {
            let range = (live.storage.string as NSString).range(of: find)
            try #require(range.location != NSNotFound)
            try insert(replacement, into: live, replacing: range)
            try assertMatchesFresh(live, after: "replace \(find) with \(replacement)")
        }
        live.view.breakUndoCoalescing()
        live.view.undoManager?.removeAllActions()
        let beforeUndo = live.storage.string
        let heading = (beforeUndo as NSString).range(of: "## Implementation")
        try insert("### Changed heading", into: live, replacing: heading)
        live.view.breakUndoCoalescing()
        let afterUndo = live.storage.string
        try #require(live.view.undoManager?.canUndo == true)
        live.view.undoManager?.undo()
        #expect(live.storage.string == beforeUndo)
        try assertMatchesFresh(live, after: "native undo")
        live.view.undoManager?.redo()
        #expect(live.storage.string == afterUndo)
        try assertMatchesFresh(live, after: "native redo")

        for width: CGFloat in [380, 760, 640] {
            live.scroll.setFrameSize(NSSize(width: width, height: 1600))
            live.coordinator.remeasure(in: live.scroll)
            for sourceMode in [true, false] {
                live.coordinator.parent.sourceMode = sourceMode
                live.storage.sourceMode = sourceMode
                live.coordinator.updateTypingAttributes(for: live.view)
                live.coordinator.remeasure(in: live.scroll)
                try assertMatchesFresh(live, after: "width \(width), source mode \(sourceMode)")
            }
        }
        for appearance in [NSAppearance.Name.darkAqua, .aqua] {
            live.view.appearance = NSAppearance(named: appearance)
            live.storage.configuration = CurrentConfiguration(fontSize: 16, lineHeight: 25.6)
            live.coordinator.parent.configuration = live.storage.configuration
            live.coordinator.updateTypingAttributes(for: live.view)
            live.coordinator.remeasure(in: live.scroll)
            try assertMatchesFresh(live, after: "appearance \(appearance)")
        }
        live.view.setSelectedRange(NSRange(location: live.storage.length, length: 0))
        live.view.setMarkedText("に", selectedRange: NSRange(location: 1, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        live.view.setMarkedText("日本", selectedRange: NSRange(location: 2, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        live.view.insertText("日本語", replacementRange: NSRange(location: NSNotFound, length: 0))
        #expect(!live.view.hasMarkedText())
        #expect(live.storage.string.hasSuffix("日本語"))
        try assertMatchesFresh(live, after: "native IME commit")
        live.view.breakUndoCoalescing()
        live.view.undoManager?.removeAllActions()
        let beforeClear = live.storage.string
        live.view.selectAll(nil)
        live.view.deleteBackward(nil)
        #expect(live.storage.string.isEmpty)
        #expect(live.view.selectedRange() == NSRange(location: 0, length: 0))
        try assertMatchesFresh(live, after: "clear document")
        live.view.breakUndoCoalescing()
        live.view.undoManager?.undo()
        #expect(live.storage.string == beforeClear)
        try assertMatchesFresh(live, after: "undo document clear")
    }

    private func insert(_ text: String, into live: NativeEditorFixture, replacing range: NSRange? = nil) throws {
        if let range { live.view.setSelectedRange(range) }
        let range = range ?? live.view.selectedRange()
        let expected = (live.storage.string as NSString).replacingCharacters(in: range, with: text)
        live.view.insertText(text, replacementRange: range)
        try #require(live.storage.string == expected)
        try #require(live.view.selectedRange() == NSRange(location: range.location + text.utf16.count, length: 0),
                     "Native insertion \(text) at \(range) moved the caret away from the inserted source")
    }

    @Test func streamLinksResolveRenderOpenAndRefreshWithoutChangingSource() throws {
        let target = MarkdownStreamLinkTarget(id: UUID(), name: "Payments")
        let source = "[[Payments]] [[Missing]]\n`[[Payments]]`\n~~~\n[[Payments]]\n~~~\n"
        let live = NativeEditorFixture(source: source)
        let sourceGeometry = live.glyphSnapshot()
        live.storage.streamLinkTargets = [target]
        #expect(live.glyphSnapshot() == sourceGeometry)
        live.coordinator.parent.streamLinkTargets = [target]
        var opened: UUID?
        live.coordinator.parent.onOpenStream = { opened = $0 }
        let link = try #require(live.storage.attribute(.link, at: 2, effectiveRange: nil) as? URL)
        #expect(live.storage.attribute(.currentCollapsedMarkdownSyntax, at: 0, effectiveRange: nil) as? Bool == false)
        #expect(live.storage.resolvedStreamLinks.count == 1)
        let parsed = live.storage.parseCount
        for _ in 0..<10 {
            _ = live.storage.resolvedStreamLinks
            _ = live.storage.streamLinkCompletion(at: NSRange(location: 6, length: 0))
        }
        #expect(live.storage.parseCount == parsed)
        #expect(live.coordinator.textView(live.view, clickedOnLink: link, at: 2))
        #expect(opened == target.id)
        live.storage.updateSelectedRange(NSRange(location: 4, length: 0))
        #expect(live.storage.attribute(.currentCollapsedMarkdownSyntax, at: 0, effectiveRange: nil) as? Bool == false)
        live.storage.sourceMode = true
        #expect(live.storage.attribute(.link, at: 2, effectiveRange: nil) == nil)
        live.storage.sourceMode = false
        live.storage.streamLinkTargets = []
        live.coordinator.parent.streamLinkTargets = []
        opened = nil
        #expect(live.storage.attribute(.link, at: 2, effectiveRange: nil) == nil)
        #expect(live.coordinator.textView(live.view, clickedOnLink: link, at: 2))
        #expect(opened == nil)
        #expect(live.storage.string == source)
    }

    @Test func nativeStreamCompletionRecoversWhenTypingDismissesThePopupWithoutAFinalCallback() async throws {
        let live = NativeEditorFixture(source: "[[", mounted: true)
        defer { live.window?.close() }
        let target = MarkdownStreamLinkTarget(id: UUID(), name: "Daily")
        live.storage.streamLinkTargets = [target]
        live.view.setSelectedRange(NSRange(location: 2, length: 0))
        var index = -1
        #expect(live.view.completions(forPartialWordRange: live.view.rangeForUserCompletion,
                                     indexOfSelectedItem: &index) == ["[[Daily]]"])

        // The actual AppKit popup dismisses on this input without calling
        // insertCompletion(isFinal:). The next native change must request it
        // again, even while the previous candidate session remains recorded.
        live.view.insertText("D", replacementRange: live.view.selectedRange())
        #expect(live.view.streamCompletionScheduled)
        live.view.insertText("a", replacementRange: live.view.selectedRange())
        #expect(live.view.streamCompletionScheduled)
        #expect(live.storage.string == "[[Da")
        live.window?.makeFirstResponder(nil)
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
        #expect(!live.view.streamCompletionScheduled)

        // A later select-all/delete/new-link attempt also recovers without
        // relying on AppKit to send a cancellation callback for the old popup.
        live.window?.makeFirstResponder(live.view)
        _ = live.view.completions(forPartialWordRange: live.view.rangeForUserCompletion,
                                 indexOfSelectedItem: &index)
        live.view.setSelectedRange(NSRange(location: 0, length: live.storage.length))
        live.view.insertText("[[", replacementRange: live.view.selectedRange())
        #expect(live.view.streamCompletionScheduled)
        #expect(live.storage.string == "[[")
    }

    @Test func nativeStreamCompletionPreservesUndoAndDoesNotDuplicateClosingBrackets() async throws {
        let target = MarkdownStreamLinkTarget(id: UUID(), name: "Payments Team")
        for source in ["See [[Pay", "See [[Pay]]"] {
            let live = NativeEditorFixture(source: source)
            live.storage.streamLinkTargets = [target]
            live.view.setSelectedRange(NSRange(location: 9, length: 0))
            let range = live.view.rangeForUserCompletion
            var index = 0
            let words = live.view.completions(forPartialWordRange: range, indexOfSelectedItem: &index)
            #expect(words == ["[[Payments Team]]"])
            #expect(index == -1)
            live.view.insertCompletion(target.insertionText, forPartialWordRange: range,
                                       movement: NSTextMovement.down.rawValue, isFinal: false)
            #expect(live.storage.string == source)
            live.view.insertCompletion(source, forPartialWordRange: range,
                                       movement: NSTextMovement.cancel.rawValue, isFinal: true)
            #expect(live.storage.string == source)
            _ = live.view.completions(forPartialWordRange: range, indexOfSelectedItem: &index)
            live.view.insertCompletion(target.insertionText, forPartialWordRange: range,
                                       movement: NSTextMovement.return.rawValue, isFinal: true)
            await withCheckedContinuation { continuation in
                DispatchQueue.main.async { continuation.resume() }
            }
            #expect(live.storage.string == "See [[Payments Team]]")
            #expect(live.view.selectedRange().location == live.storage.length)
            live.view.breakUndoCoalescing()
            try #require(live.view.undoManager?.canUndo == true)
            live.view.undoManager?.undo()
            #expect(live.storage.string == source)
            live.view.undoManager?.redo()
            #expect(live.storage.string == "See [[Payments Team]]")
            live.view.setSelectedRange(NSRange(location: live.storage.length, length: 0))
            try insert("\n[[Pa", into: live)
            #expect(live.storage.streamLinkCompletion(at: live.view.selectedRange()) != nil)
            live.view.setMarkedText("に", selectedRange: NSRange(location: 1, length: 0),
                                    replacementRange: NSRange(location: NSNotFound, length: 0))
            #expect(live.storage.streamLinkCompletion(at: live.view.selectedRange()) == nil)
            live.view.unmarkText()
        }
    }

    @Test func deferredStreamCompletionDoesNotReplaceNewerInputOrAnotherDocument() async {
        let target = MarkdownStreamLinkTarget(id: UUID(), name: "Daily")
        for switchesDocument in [false, true] {
            let live = NativeEditorFixture(source: "[[Da")
            live.storage.streamLinkTargets = [target]
            live.view.currentDayID = "completion-source"
            live.view.setSelectedRange(NSRange(location: 4, length: 0))
            var index = -1
            let range = live.view.rangeForUserCompletion
            _ = live.view.completions(forPartialWordRange: range, indexOfSelectedItem: &index)
            live.view.insertCompletion(target.insertionText, forPartialWordRange: range,
                                       movement: NSTextMovement.return.rawValue, isFinal: true)
            if switchesDocument {
                live.view.currentDayID = "completion-destination"
            } else {
                live.view.insertText("x", replacementRange: live.view.selectedRange())
            }
            await withCheckedContinuation { continuation in
                DispatchQueue.main.async { continuation.resume() }
            }
            #expect(live.storage.string == (switchesDocument ? "[[Da" : "[[Dax"))
        }
    }

    @Test func nativeUndoRedoActionsRouteToTheEditorHistoryAndValidateMenus() throws {
        let live = NativeEditorFixture(source: "Before")
        live.view.setSelectedRange(NSRange(location: live.storage.length, length: 0))
        let undo = NSMenuItem(title: "Undo", action: #selector(MarkdownTextView.undo(_:)), keyEquivalent: "z")
        let redo = NSMenuItem(title: "Redo", action: #selector(MarkdownTextView.redo(_:)), keyEquivalent: "Z")
        #expect(!live.view.validateMenuItem(undo))
        #expect(!live.view.validateMenuItem(redo))
        live.view.insertText(" after", replacementRange: live.view.selectedRange())
        live.view.breakUndoCoalescing()
        #expect(live.view.validateMenuItem(undo))
        #expect(live.view.validateUserInterfaceItem(undo))
        let app = NSApplication.shared
        let undoTarget = try #require(app.target(forAction: undo.action!, to: live.view, from: undo) as? MarkdownTextView)
        #expect(undoTarget === live.view)
        #expect(app.sendAction(undo.action!, to: undoTarget, from: undo))
        #expect(live.storage.string == "Before")
        #expect(live.view.validateMenuItem(redo))
        #expect(live.view.validateUserInterfaceItem(redo))
        let redoTarget = try #require(app.target(forAction: redo.action!, to: live.view, from: redo) as? MarkdownTextView)
        #expect(redoTarget === live.view)
        #expect(app.sendAction(redo.action!, to: redoTarget, from: redo))
        #expect(live.storage.string == "Before after")
        live.view.setMarkedText("に", selectedRange: NSRange(location: 1, length: 0),
                                replacementRange: NSRange(location: NSNotFound, length: 0))
        #expect(!live.view.validateMenuItem(undo))
        #expect(!live.view.validateMenuItem(redo))
        live.view.unmarkText()
    }

    private func assertMatchesFresh(_ live: NativeEditorFixture, after operation: String) throws {
        let fresh = NativeEditorFixture(source: live.storage.string, width: live.container.containerSize.width,
                                        configuration: live.storage.configuration)
        fresh.storage.sourceMode = live.storage.sourceMode
        fresh.storage.updateSelectedRange(live.storage.selectedRange)
        let matches = sameRendering(live.storage, fresh.storage)
        try #require(matches, "Native attributes differ after \(operation)")
        let actual = live.glyphSnapshot()
        let expected = fresh.glyphSnapshot()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.001))
        let expectedHeight = max(live.coordinator.parent.minimumHeight, ceil(live.manager.usedRect(for: live.container).height + 6))
        try #require(abs(live.measurement.height - expectedHeight) <= 1,
                     "Published editor height differs after \(operation): \(live.measurement.height) vs \(expectedHeight)")
        try #require(actual.count == expected.count, "Glyph counts differ after \(operation): \(actual.count) vs \(expected.count)")
        if let mismatch = actual.indices.first(where: { actual[$0] != expected[$0] }) {
            Issue.record("Glyph \(mismatch) differs after \(operation): live \(actual[mismatch]), fresh \(expected[mismatch])")
            throw NativeEditorMismatch()
        }
    }

    private struct NativeEditorMismatch: Error {}
    private final class Measurement { var height: CGFloat = 0 }

    @MainActor private final class NativeEditorFixture {
        let storage: MarkdownTextStorage
        let manager = MarkdownLayoutManager()
        let container = NSTextContainer(size: NSSize(width: 640, height: CGFloat.greatestFiniteMagnitude))
        let view: MarkdownTextView
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 640, height: 1600))
        let coordinator: MarkdownEditorView.Coordinator
        let measurement = Measurement()
        let window: NSWindow?

        init(source: String = "", width: CGFloat = 640, configuration: CurrentConfiguration = .default, mounted: Bool = false) {
            window = mounted ? NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: 1600), styleMask: [.borderless], backing: .buffered, defer: false) : nil
            window?.isReleasedWhenClosed = false
            storage = MarkdownTextStorage(string: source, configuration: configuration)
            storage.addLayoutManager(manager)
            manager.addTextContainer(container)
            view = MarkdownTextView(frame: scroll.frame, textContainer: container)
            view.isRichText = false
            view.allowsUndo = true
            view.isAutomaticQuoteSubstitutionEnabled = false
            view.isAutomaticDashSubstitutionEnabled = false
            view.isAutomaticTextReplacementEnabled = false
            view.isAutomaticSpellingCorrectionEnabled = false
            view.isContinuousSpellCheckingEnabled = false
            container.lineFragmentPadding = 0
            container.widthTracksTextView = false
            view.textContainerInset = .zero
            scroll.documentView = view
            scroll.setFrameSize(NSSize(width: width, height: 1600))
            container.containerSize = NSSize(width: width, height: CGFloat.greatestFiniteMagnitude)
            let measurement = measurement
            let parent = MarkdownEditorView(text: .constant(source), measuredHeight: Binding(get: { measurement.height }, set: { measurement.height = $0 }), dayID: nil, configuration: configuration, focusOnAppear: false)
            coordinator = MarkdownEditorView.Coordinator(parent)
            coordinator.textView = view
            view.delegate = coordinator
            coordinator.updateTypingAttributes(for: view)
            storage.onAsyncLayoutChange = { [weak coordinator, weak scroll] in
                if let scroll { coordinator?.remeasure(in: scroll) }
            }
            window?.contentView = scroll
            window?.makeFirstResponder(view)
        }

        func glyphSnapshot() -> [String] {
            manager.ensureLayout(for: container)
            let source = storage.string as NSString
            return (0..<manager.numberOfGlyphs).compactMap { glyph in
                let properties = manager.propertyForGlyph(at: glyph)
                let character = manager.characterIndexForGlyph(at: glyph)
                // Null slots around surrogate pairs may occur before or after
                // their visible glyph; null Markdown markers have no geometry.
                // Compare the glyphs that draw, mapped to source graphemes.
                if properties.contains(.null) { return nil }
                let grapheme = source.rangeOfComposedCharacterSequence(at: character).location
                let location = manager.location(forGlyphAt: glyph)
                let line = manager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
                // Incremental and fresh layout can sum the same fractional
                // line heights in a different order. Compare millipoints,
                // retaining exact glyph identity, properties, and source index.
                let geometry = [location.x, location.y, line.minX, line.minY, line.width, line.height]
                    .map { Int(($0 * 1_000).rounded()) }
                return "\(manager.glyph(at: glyph)) \(properties.rawValue) char:\(grapheme) geometry:\(geometry)"
            }
        }
    }

    private func sameRendering(_ lhs: NSAttributedString, _ rhs: NSAttributedString) -> Bool {
        guard lhs.string == rhs.string else { return false }
        for index in 0..<lhs.length {
            let left = lhs.attributes(at: index, effectiveRange: nil)
            let right = rhs.attributes(at: index, effectiveRange: nil)
            guard Set(left.keys) == Set(right.keys) else {
                print("Render keys differ at", index, Set(left.keys).symmetricDifference(Set(right.keys)))
                return false
            }
            for key in left.keys {
                if let a = left[key] as? NSFont, let b = right[key] as? NSFont, !a.isEqual(b) {
                    // Native font fixing may store an emoji fallback explicitly
                    // in one editor while glyph generation resolves it in the
                    // other. Compare the font that actually draws this grapheme.
                    let text = lhs.string as NSString
                    let grapheme = text.substring(with: text.rangeOfComposedCharacterSequence(at: index))
                    let range = CFRange(location: 0, length: grapheme.utf16.count)
                    let first = CTFontCreateForString(a as CTFont, grapheme as CFString, range)
                    let second = CTFontCreateForString(b as CTFont, grapheme as CFString, range)
                    if !CFEqual(first, second) {
                        print("Render font differs at", index, a, b)
                        return false
                    }
                } else if let a = left[key] as? NSColor, let b = right[key] as? NSColor {
                    if a.usingColorSpace(.deviceRGB) != b.usingColorSpace(.deviceRGB) {
                        print("Render color differs at", index, key)
                        return false
                    }
                } else if let a = left[key] as? NSObject, let b = right[key] as? NSObject, !a.isEqual(b) {
                    print("Render attribute differs at", index, key, a, b)
                    return false
                }
            }
        }
        return true
    }

}
