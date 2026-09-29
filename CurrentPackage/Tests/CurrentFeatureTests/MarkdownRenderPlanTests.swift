import AppKit
import CoreText
import SwiftUI
import Testing
@testable import CurrentFeature

@Suite(.serialized)
@MainActor
struct MarkdownRenderPlanTests {
    @Test func unchangedDecorationReusesPlansWithoutRestylingLines() throws {
        let live = Editor(source: mixedSource)
        try assertFresh(live)
        let builds = live.storage.renderPlanBuildCount
        let styles = live.storage.styledLineCount
        let reuse = live.storage.renderPlanReuseCount
        for _ in 0..<3 { live.storage.applyDecorations() }
        #expect(live.storage.renderPlanBuildCount == builds)
        #expect(live.storage.styledLineCount == styles)
        #expect(live.storage.renderPlanReuseCount > reuse)
        try assertFresh(live)
    }

    @Test func editingOneLineReusesDistantPlansAtTheirShiftedOffsets() throws {
        let live = Editor(source: "Edit here\n\n" + String(repeating: mixedSource, count: 20))
        live.select(NSRange(location: 4, length: 0))
        let builds = live.storage.renderPlanBuildCount
        let reuse = live.storage.renderPlanReuseCount
        let styles = live.storage.styledLineCount
        try live.replace(live.view.selectedRange(), with: " an introduction")
        live.storage.applyDecorations()
        #expect(live.storage.renderPlanReuseCount >= reuse + 20)
        // A local edit may rebuild its neighbors and active block, but must
        // not rebuild or restyle the hundreds of unchanged downstream lines.
        #expect(live.storage.renderPlanBuildCount - builds < 10)
        #expect(live.storage.styledLineCount - styles < 10)
        try assertFresh(live)
    }

    @Test func selectingALongFenceRestylesOnlyItsTwoBoundaryLines() throws {
        let live = Editor(source: "Before\n\n~~~swift\n" + String(repeating: "let value = 42\n", count: 1000) + "~~~\n\nAfter\n")
        live.storage.updateSelectedRange(nil)
        live.manager.ensureLayout(for: live.container)
        let parsed = live.storage.parseCount
        var styled = live.storage.styledLineCount
        live.storage.updateSelectedRange(NSRange(location: live.range("let value").location, length: 0))
        try assertFresh(live, after: "enter a 1000-line fence")
        #expect(live.storage.styledLineCount - styled == 2)
        #expect(live.storage.parseCount == parsed)
        styled = live.storage.styledLineCount
        live.storage.updateSelectedRange(NSRange(location: live.range("After").location, length: 0))
        try assertFresh(live, after: "leave a 1000-line fence")
        #expect(live.storage.styledLineCount - styled == 2)
        #expect(live.storage.parseCount == parsed)
    }

    @Test func plainTypingAdvancesGeometryEvenWhenLineAttributesAreUnchanged() throws {
        let live = Editor(source: "A short paragraph", width: 320)
        live.manager.ensureLayout(for: live.container)
        let oldHeight = live.manager.usedRect(for: live.container).height
        let sourceRevision = live.storage.sourceRevision
        let decorationRevision = live.storage.decorationRevision
        try live.replace(live.view.selectedRange(), with: String(repeating: " with more ordinary words", count: 15))
        #expect(live.storage.sourceRevision > sourceRevision)
        #expect(live.storage.decorationRevision > decorationRevision)
        try assertFresh(live)
        #expect(live.manager.usedRect(for: live.container).height > oldHeight)
    }

    @Test func committingPlainCompositionPublishesItsChangedGeometry() throws {
        let live = Editor(source: "Plain text", width: 320)
        live.manager.ensureLayout(for: live.container)
        let oldHeight = live.manager.usedRect(for: live.container).height
        let revision = live.storage.decorationRevision
        live.storage.suspendsDecorations = true
        live.storage.replaceCharacters(in: NSRange(location: live.storage.length, length: 0),
                                       with: String(repeating: " more plain words", count: 20))
        live.select(NSRange(location: live.storage.length, length: 0))
        #expect(live.storage.decorationRevision == revision)
        live.storage.suspendsDecorations = false
        #expect(live.storage.decorationRevision > revision)
        try assertFresh(live)
        #expect(live.manager.usedRect(for: live.container).height > oldHeight)
    }

    @Test func committingAnEmptyCompositionPublishesItsChangedGeometry() throws {
        let live = Editor(source: String(repeating: "Plain text on a line.\n", count: 20), width: 320)
        live.manager.ensureLayout(for: live.container)
        let revision = live.storage.decorationRevision
        live.storage.suspendsDecorations = true
        live.storage.replaceCharacters(in: NSRange(location: 0, length: live.storage.length), with: "")
        live.select(NSRange(location: 0, length: 0))
        #expect(live.storage.decorationRevision == revision)
        live.storage.suspendsDecorations = false
        #expect(live.storage.decorationRevision > revision)
        #expect(live.storage.string.isEmpty)
        try assertFresh(live)
    }

    @Test func unchangedBlocksRebaseAfterEditsBeforeTheirSourceRanges() throws {
        let live = Editor(source: mixedSource)
        try assertFresh(live, after: "initial source")
        try live.replace(NSRange(location: 0, length: 0), with: "🙂 New introduction\n\n")
        try assertFresh(live, after: "insert introduction before heading")
        try live.replace(live.range("New introduction"), with: "A much longer introduction with **emphasis**")
        try assertFresh(live, after: "expand introduction")
        let prefix = (live.storage.string as NSString).range(of: "## Repeated")
        try live.replace(NSRange(location: 0, length: prefix.location), with: "")
        try assertFresh(live, after: "delete introduction")
        try live.replace(live.range("~~~swift"), with: "ordinary text")
        try assertFresh(live, after: "remove opening fence")
        try live.replace(live.range("ordinary text"), with: "~~~swift")
        try assertFresh(live, after: "restore opening fence")
    }

    @Test func identicalBlankLinesKeepTheirOwnHeadingAndFenceContext() throws {
        let live = Editor(source: "## Same\n\nBody\n\n## Same\n\nBody\n\n~~~\n## Same\n\nBody\n~~~\n")
        live.select(NSRange(location: live.storage.length, length: 0))
        try assertFresh(live)
        #expect(live.lineHeight(at: "## Same\n".utf16.count) == 6)
        let second = live.range("## Same", after: 1)
        #expect(live.lineHeight(at: NSMaxRange(second) + 1) == 6)
        let protected = live.range("## Same", after: NSMaxRange(second))
        #expect(live.lineHeight(at: NSMaxRange(protected) + 1) == CurrentTheme.editorLineHeight)
        try live.replace(NSRange(location: 0, length: 3), with: "")
        live.select(NSRange(location: live.storage.length, length: 0))
        try assertFresh(live)
        #expect(live.lineHeight(at: "Same\n".utf16.count) == CurrentTheme.editorLineHeight)
        let remaining = live.range("## Same")
        #expect(live.lineHeight(at: NSMaxRange(remaining) + 1) == 6)
        try live.replace(NSRange(location: NSMaxRange(remaining) + 1, length: 0), with: "\n")
        live.select(NSRange(location: live.storage.length, length: 0))
        try assertFresh(live)
        #expect(live.lineHeight(at: NSMaxRange(remaining) + 1) == CurrentTheme.editorLineHeight)
    }

    @Test func selectionAcrossFenceAndTableRestoresEveryDepartedBlock() throws {
        let live = Editor(source: mixedSource)
        let start = live.range("Before").location
        let end = NSMaxRange(live.range("Ready"))
        let selections = [NSRange(location: start, length: end - start),
                          NSRange(location: live.range("let value").location, length: 0),
                          NSRange(location: live.range("Ready").location, length: 0),
                          NSRange(location: live.range("After").location, length: 0)]
        let parseCount = live.storage.parseCount
        for selection in selections {
            live.select(selection)
            try assertFresh(live)
            #expect(live.storage.parseCount == parseCount)
        }
        let table = live.range("| Owner |")
        #expect(live.storage.attribute(.currentRichBlockHeight, at: table.location, effectiveRange: nil) != nil)
        for width: CGFloat in [320, 760, 420, 640] {
            live.resize(width)
            try assertFresh(live)
        }
        live.storage.sourceMode = true
        try assertFresh(live)
        live.storage.sourceMode = false
        try assertFresh(live)
        live.storage.configuration = CurrentConfiguration(fontSize: 19, lineHeight: 30)
        live.coordinator.parent.configuration = live.storage.configuration
        live.coordinator.updateTypingAttributes(for: live.view)
        try assertFresh(live, after: "change font size and line height")
        #expect(live.storage.string == mixedSource)
    }

    @Test func quoteWhitespaceEditsDoNotLeakAttributesAcrossBlankLines() throws {
        let live = Editor(source: "## Heading\n\n> First quote\n \t\n> Second **quote**\n\nPlain text\n")
        try assertFresh(live)
        for (find, replacement) in [(" \t\n", "\n\n"), ("> First quote", "Plain paragraph"),
                                    ("Plain paragraph", "> First quote"), ("\n\nPlain text", "\r\n \t\r\nPlain text")] {
            try live.replace(live.range(find), with: replacement)
            live.select(NSRange(location: live.storage.length, length: 0))
            try assertFresh(live)
        }
    }

    @Test func reusedPlansPreserveNativeUnicodeGlyphsThroughTypingUndoAndResize() throws {
        let live = Editor(source: mixedSource, mounted: true)
        defer { live.window?.close() }
        live.view.undoManager?.removeAllActions()
        let original = live.storage.string
        let heading = live.range("Repeated")
        live.view.breakUndoCoalescing()
        try live.replace(heading, with: "Repeated 👩🏽‍💻 日本語 e\u{301} العربية")
        live.view.breakUndoCoalescing()
        let edited = live.storage.string
        try assertFresh(live)
        try #require(live.view.undoManager?.canUndo == true)
        live.view.undoManager?.undo()
        #expect(live.storage.string == original)
        try assertFresh(live)
        live.view.undoManager?.redo()
        #expect(live.storage.string == edited)
        try assertFresh(live)
        for token in ["👩🏽‍💻", "日本語", "e\u{301}", "العربية"] {
            live.select(live.range(token))
            try assertFresh(live)
        }
        live.resize(320)
        try assertFresh(live)
        live.resize(640)
        try assertFresh(live)
    }

    @Test func longRepeatedBlocksMatchFreshAfterTopAndMiddleEdits() throws {
        let repeated = "## Repeated\n\nA **bold** paragraph with `code` and 🙂.\n- [ ] Compare result\n> Check this paragraph.\n\n"
        let live = Editor(source: String(repeating: repeated, count: 170) + mixedSource)
        try live.replace(NSRange(location: 0, length: 0), with: "# Opening\n\n")
        try autoreleasepool { try assertFresh(live) }
        let middle = live.range("## Repeated", after: live.storage.length / 2)
        try live.replace(middle, with: "Ordinary paragraph")
        try autoreleasepool { try assertFresh(live) }
        live.select(NSRange(location: live.range("After").location, length: 0))
        try autoreleasepool { try assertFresh(live) }
    }

    private var mixedSource: String {
        "## Repeated\n\nBefore **bold** text.\n\n~~~swift\nlet value = \"🙂\"\n~~~\n\n| Owner | Status |\n| --- | --- |\n| Maya | Ready to review the revised contract and its outstanding terms |\n\nAfter _italic_ text.\n"
    }

    private func assertFresh(_ live: Editor, after operation: String = "edit") throws {
        let fresh = Editor(source: live.storage.string, width: live.width, configuration: live.storage.configuration)
        fresh.storage.sourceMode = live.storage.sourceMode
        fresh.view.setSelectedRange(live.view.selectedRange())
        // An unfocused editor intentionally renders with no active block even
        // though NSTextView still remembers its selection for the next focus.
        fresh.storage.updateSelectedRange(live.storage.selectedRange)
        let actual = live.glyphs()
        let expected = fresh.glyphs()
        let source = live.storage.string as NSString
        var index = 0
        while index < source.length {
            var aRange = NSRange(), bRange = NSRange()
            let a = live.storage.attributes(at: index, effectiveRange: &aRange)
            let b = fresh.storage.attributes(at: index, effectiveRange: &bRange)
            try #require(Set(a.keys) == Set(b.keys), "Attribute keys differ at source offset \(index) after \(operation)")
            for key in a.keys {
                // Rich widgets are distinct drawing objects; presence, their
                // height attributes and the actual native geometry are compared.
                if key == .currentRichBlock { continue }
                if let left = a[key] as? NSFont, let right = b[key] as? NSFont, !left.isEqual(right) {
                    let grapheme = source.substring(with: source.rangeOfComposedCharacterSequence(at: index))
                    let range = CFRange(location: 0, length: grapheme.utf16.count)
                    try #require(CFEqual(CTFontCreateForString(left as CTFont, grapheme as CFString, range),
                                        CTFontCreateForString(right as CTFont, grapheme as CFString, range)),
                                 "Font differs at source offset \(index) after \(operation)")
                } else if let left = a[key] as? NSColor, let right = b[key] as? NSColor {
                    try #require(left.usingColorSpace(.deviceRGB) == right.usingColorSpace(.deviceRGB),
                                 "Color differs at source offset \(index) after \(operation)")
                } else if let left = a[key] as? NSObject, let right = b[key] as? NSObject {
                    try #require(left.isEqual(right), "Attribute \(key) differs at source offset \(index) after \(operation)")
                }
            }
            index = max(index + 1, min(NSMaxRange(aRange), NSMaxRange(bRange)))
        }
        try #require(actual.count == expected.count, "Incremental glyph count differs after \(operation)")
        if let mismatch = actual.indices.first(where: { actual[$0] != expected[$0] }) {
            Issue.record("After \(operation), glyph \(mismatch): live \(actual[mismatch]); fresh \(expected[mismatch]); native selection \(live.view.selectedRange()); render selection \(String(describing: live.storage.selectedRange))")
            throw RenderMismatch()
        }
        #expect(abs(live.manager.usedRect(for: live.container).height - fresh.manager.usedRect(for: fresh.container).height) < 0.001)
    }

    private struct RenderMismatch: Error {}

    @MainActor private final class Editor {
        let storage: MarkdownTextStorage
        let manager = MarkdownLayoutManager()
        let container: NSTextContainer
        let view: MarkdownTextView
        let scroll: NSScrollView
        let coordinator: MarkdownEditorView.Coordinator
        let window: NSWindow?
        var width: CGFloat { container.containerSize.width }

        init(source: String, width: CGFloat = 640, configuration: CurrentConfiguration = .default, mounted: Bool = false) {
            storage = MarkdownTextStorage(string: source, configuration: configuration)
            storage.renderWidth = width
            container = NSTextContainer(size: NSSize(width: width, height: CGFloat.greatestFiniteMagnitude))
            container.lineFragmentPadding = 0
            container.widthTracksTextView = false
            storage.addLayoutManager(manager)
            manager.addTextContainer(container)
            view = MarkdownTextView(frame: NSRect(x: 0, y: 0, width: width, height: 1200), textContainer: container)
            view.isRichText = false
            view.allowsUndo = true
            view.isAutomaticQuoteSubstitutionEnabled = false
            view.isAutomaticDashSubstitutionEnabled = false
            view.isAutomaticTextReplacementEnabled = false
            view.isAutomaticSpellingCorrectionEnabled = false
            view.isContinuousSpellCheckingEnabled = false
            view.textContainerInset = .zero
            scroll = NSScrollView(frame: view.frame)
            scroll.documentView = view
            coordinator = MarkdownEditorView.Coordinator(MarkdownEditorView(text: .constant(source),
                measuredHeight: .constant(1200), dayID: nil, configuration: configuration, focusOnAppear: false))
            coordinator.textView = view
            view.delegate = coordinator
            coordinator.updateTypingAttributes(for: view)
            if mounted {
                window = NSWindow(contentRect: scroll.frame, styleMask: [.borderless], backing: .buffered, defer: false)
                window?.isReleasedWhenClosed = false
                window?.contentView = scroll
                window?.makeFirstResponder(view)
            } else { window = nil }
            select(NSRange(location: source.utf16.count, length: 0))
        }

        func range(_ text: String, after location: Int = 0) -> NSRange {
            (storage.string as NSString).range(of: text, range: NSRange(location: location, length: storage.length - location))
        }

        func select(_ range: NSRange) {
            view.setSelectedRange(range)
            storage.updateSelectedRange(range)
        }

        func replace(_ range: NSRange, with text: String) throws {
            try #require(range.location != NSNotFound)
            let expected = (storage.string as NSString).replacingCharacters(in: range, with: text)
            select(range)
            view.insertText(text, replacementRange: range)
            try #require(storage.string == expected)
            try #require(view.selectedRange() == NSRange(location: range.location + text.utf16.count, length: 0))
        }

        func resize(_ width: CGFloat) {
            scroll.setFrameSize(NSSize(width: width, height: 1200))
            coordinator.remeasure(in: scroll)
            storage.renderWidth = width
        }

        func lineHeight(at index: Int) -> CGFloat {
            manager.ensureLayout(for: container)
            return manager.lineFragmentRect(forGlyphAt: manager.glyphIndexForCharacter(at: index), effectiveRange: nil).height
        }

        func glyphs() -> [String] {
            manager.ensureLayout(for: container)
            let source = storage.string as NSString
            return (0..<manager.numberOfGlyphs).compactMap { glyph in
                let properties = manager.propertyForGlyph(at: glyph)
                guard !properties.contains(.null) else { return nil }
                let character = manager.characterIndexForGlyph(at: glyph)
                let grapheme = source.rangeOfComposedCharacterSequence(at: character).location
                let point = manager.location(forGlyphAt: glyph)
                let line = manager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
                let geometry = [point.x, point.y, line.minX, line.minY, line.width, line.height].map { Int(($0 * 1000).rounded()) }
                return "\(manager.glyph(at: glyph)) \(properties.rawValue) \(grapheme) \(geometry)"
            }
        }
    }
}
