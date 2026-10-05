import AppKit
import SwiftUI
import Testing
@testable import CurrentFeature

@Suite(.serialized)
struct MarkdownReadingAnchorTests {
    @Test func sourceContextRebasesAfterInsertionAndNearbyPrefixEdits() throws {
        let source = String(repeating: "Before the important paragraph. ", count: 5)
            + "The reading edge starts here, followed by a distinctive explanation of the decision."
        let location = (source as NSString).range(of: "The reading edge").location
        let anchor = MarkdownReadingAnchor.captureSource(in: source, at: location, lineOffset: 7.5)
        #expect(anchor.resolvedSourceLocation(in: source) == location)
        let inserted = "An earlier addition 🙂\n" + source
        #expect(anchor.resolvedSourceLocation(in: inserted) == location + "An earlier addition 🙂\n".utf16.count)
        let changed = (source as NSString).replacingCharacters(in: NSRange(location: location - 12, length: 12), with: "Revised. ")
        #expect(anchor.resolvedSourceLocation(in: changed) == location - 12 + "Revised. ".utf16.count)
        let decoded = try JSONDecoder().decode(MarkdownReadingAnchor.self, from: JSONEncoder().encode(anchor))
        #expect(decoded == anchor)
    }

    @Test func repeatedContextChoosesNearestOccurrenceAndDeletedSourceClamps() {
        let paragraph = "Repeated paragraph with enough neighboring context to identify the same source position.\n"
        let source = String(repeating: paragraph, count: 8)
        let location = paragraph.utf16.count * 5 + 12
        let anchor = MarkdownReadingAnchor.captureSource(in: source, at: location)
        #expect(anchor.resolvedSourceLocation(in: source) == location)
        #expect(anchor.resolvedSourceLocation(in: "Small replacement") == "Small replacement".utf16.count)
        #expect(anchor.resolvedSourceLocation(in: "") == 0)
    }

    @Test func utf16ContextNeverSplitsComposedCharacters() {
        let source = "Start " + String(repeating: "👩🏽‍💻 e\u{301} 日本語 ", count: 10) + "Ending"
        let emoji = (source as NSString).range(of: "👩🏽‍💻")
        let anchor = MarkdownReadingAnchor.captureSource(in: source, at: emoji.location + 3)
        #expect(anchor.sourceLocation == emoji.location)
        #expect(anchor.resolvedSourceLocation(in: "Added🙂 " + source) == emoji.location + "Added🙂 ".utf16.count)
        #expect((anchor.context as NSString).substring(from: anchor.contextPrefixLength).hasPrefix("👩🏽‍💻"))
        #expect(MarkdownReadingAnchor.captureSource(in: "", at: 50).sourceLocation == 0)
    }

    @Test @MainActor func readingLineSurvivesWidthAndFontReflowWithoutMovingSelection() throws {
        let source = (0..<24).map { "Paragraph \($0) has enough words to wrap into several visual lines as the available width changes." }.joined(separator: "\n\n")
        let editor = Editor(source: source, width: 640)
        let sourceLocation = (source as NSString).range(of: "Paragraph 12").location + 35
        let reference = MarkdownReadingAnchor.captureSource(in: source, at: sourceLocation)
        let initialOrigin = try #require(reference.lineOrigin(in: editor.view))
        let anchor = try #require(MarkdownReadingAnchor.capture(in: editor.view, readingY: initialOrigin.y + 6))
        let selection = editor.view.selectedRange()
        #expect(abs(anchor.lineOffset - 6) < 0.001)
        editor.container.containerSize.width = 310
        editor.view.setFrameSize(NSSize(width: 310, height: 8000))
        var configuration = CurrentConfiguration.default
        configuration.fontSize = 20
        editor.storage.configuration = configuration
        editor.manager.ensureLayout(for: editor.container)
        let restored = try #require(anchor.lineOrigin(in: editor.view))
        let glyph = editor.manager.glyphIndexForCharacter(at: anchor.resolvedSourceLocation(in: source))
        let expected = editor.manager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
        #expect(abs(restored.y - editor.view.textContainerOrigin.y - expected.minY) < 0.001)
        #expect(restored.y > initialOrigin.y)
        #expect(editor.view.selectedRange() == selection)
        #expect(editor.storage.string == source)
    }

    @Test @MainActor func emptyAndTrailingNewlineUseTheExtraFragmentAndCompositionWaits() throws {
        for source in ["", "One line\n"] {
            let editor = Editor(source: source, width: 400)
            let origin = editor.view.textContainerOrigin
            let extra = editor.manager.extraLineFragmentRect
            let anchor = try #require(MarkdownReadingAnchor.capture(in: editor.view, readingY: origin.y + extra.minY + 4))
            #expect(anchor.sourceLocation == source.utf16.count)
            let restored = try #require(anchor.lineOrigin(in: editor.view))
            #expect(abs(restored.y - origin.y - extra.minY) < 0.001)
            editor.storage.suspendsDecorations = true
            #expect(anchor.lineOrigin(in: editor.view) == nil)
            #expect(MarkdownReadingAnchor.capture(in: editor.view, readingY: restored.y) == nil)
        }
    }

    @Test @MainActor func settledGeometryPublishesForFirstMeasurementAndEqualHeightEdits() async throws {
        let editor = Editor(source: "Short paragraph", width: 400)
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 400, height: 600))
        scroll.documentView = editor.view
        let coordinator = MarkdownEditorView.Coordinator(MarkdownEditorView(text: .constant(editor.storage.string),
            measuredHeight: Binding(get: { scroll.frame.height }, set: {
                scroll.setFrameSize(NSSize(width: 400, height: $0))
            }), dayID: "reading-anchor-test", configuration: .default, focusOnAppear: false))
        coordinator.textView = editor.view
        editor.view.delegate = coordinator
        editor.view.currentDayID = "reading-anchor-test"
        let observer = LayoutObserver()
        NotificationCenter.default.addObserver(observer, selector: #selector(LayoutObserver.received),
            name: Notification.Name("Current.editorLayoutSettled"), object: editor.view)
        defer {
            NotificationCenter.default.removeObserver(observer)
            editor.view.delegate = nil
        }
        #expect(!editor.view.isGeometrySettled)
        coordinator.remeasure(in: scroll)
        try await waitForLayoutNotifications(1, from: observer)
        #expect(editor.view.isGeometrySettled)
        #expect(observer.count == 1)
        let height = editor.manager.usedRect(for: editor.container).height
        editor.storage.replaceCharacters(in: NSRange(location: editor.storage.length, length: 0), with: " words")
        #expect(!editor.view.isGeometrySettled)
        coordinator.remeasure(in: scroll)
        try await waitForLayoutNotifications(2, from: observer)
        #expect(editor.view.isGeometrySettled)
        #expect(observer.count == 2)
        #expect(editor.manager.usedRect(for: editor.container).height == height)
        editor.container.containerSize.width = 300
        #expect(!editor.view.isGeometrySettled)
    }

    @MainActor private func waitForLayoutNotifications(_ expectedCount: Int, from observer: LayoutObserver) async throws {
        for _ in 0..<100 {
            if observer.count >= expectedCount { return }
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    @MainActor private final class LayoutObserver: NSObject {
        var count = 0
        @objc func received() { count += 1 }
    }

    @MainActor private final class Editor {
        let storage: MarkdownTextStorage
        let manager = MarkdownLayoutManager()
        let container: NSTextContainer
        let view: MarkdownTextView

        init(source: String, width: CGFloat) {
            storage = MarkdownTextStorage(string: source)
            container = NSTextContainer(size: NSSize(width: width, height: CGFloat.greatestFiniteMagnitude))
            container.lineFragmentPadding = 0
            container.widthTracksTextView = false
            storage.addLayoutManager(manager)
            manager.addTextContainer(container)
            view = MarkdownTextView(frame: NSRect(x: 0, y: 0, width: width, height: 8000), textContainer: container)
            view.textContainerInset = NSSize(width: 10, height: 10)
            view.setSelectedRange(NSRange(location: min(3, source.utf16.count), length: 0))
            manager.ensureLayout(for: container)
        }
    }
}
