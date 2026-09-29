import AppKit
import SwiftUI
import Testing
@testable import CurrentFeature

@Suite(.serialized)
@MainActor
struct MarkdownEditorResizeTests {
    @Test func nativeWidthChangesPublishWrappedHeightWithoutChangingTheDocument() async throws {
        let source = String(repeating: "A paragraph with enough words to wrap differently when the native editor becomes narrower.\n", count: 80)
        let host = NSHostingView(rootView: Fixture(source: source))
        host.sizingOptions = []
        host.frame = NSRect(x: 0, y: 0, width: 420, height: 300)
        let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 420, height: 300),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderFront(nil)
        defer { window.close() }
        try await settle(host)
        let editor = try #require(findEditor(in: host))
        let scrollView = try #require(editor.enclosingScrollView)
        let originalHeight = scrollView.frame.height
        try #require(originalHeight > 300)
        let selection = NSRange(location: source.utf16.count - 1, length: 0)
        editor.setSelectedRange(selection)

        window.setContentSize(NSSize(width: 760, height: 300))
        try await settle(host)
        #expect(scrollView.frame.height < originalHeight - 200)
        window.setContentSize(NSSize(width: 420, height: 300))
        try await settle(host)

        #expect(abs(scrollView.frame.height - originalHeight) <= 1)
        #expect(abs(editor.frame.height - scrollView.frame.height) <= 1)
        #expect(findEditor(in: host) === editor)
        #expect(editor.string == source)
        #expect(editor.selectedRange() == selection)
    }

    private func settle(_ view: NSView) async throws {
        for _ in 0..<12 {
            view.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(5))
        }
    }

    private func findEditor(in view: NSView) -> NSTextView? {
        if let editor = view as? NSTextView { return editor }
        return view.subviews.lazy.compactMap { findEditor(in: $0) }.first
    }

    private struct Fixture: View {
        let source: String
        @State private var height: CGFloat = 48

        var body: some View {
            MarkdownEditorView(text: .constant(source), measuredHeight: $height,
                               focusOnAppear: false, minimumHeight: 48)
                .frame(height: height)
        }
    }
}
