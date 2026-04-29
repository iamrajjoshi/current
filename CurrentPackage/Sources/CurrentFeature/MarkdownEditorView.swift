import AppKit
import SwiftUI

extension Notification.Name {
    static let currentInsertTimestamp = Notification.Name("CurrentInsertTimestamp")
}

final class MarkdownTextView: NSTextView {
    weak static var activeEditor: MarkdownTextView?

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
}

struct MarkdownEditorView: NSViewRepresentable {
    @Binding var text: String
    @Binding var measuredHeight: CGFloat
    var focusOnAppear: Bool
    var minimumHeight: CGFloat = 72

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder

        let textView = MarkdownTextView()
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.usesFindPanel = true
        textView.usesFontPanel = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.backgroundColor = CurrentTheme.editorBackground
        textView.drawsBackground = true
        textView.insertionPointColor = .labelColor
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
        textView.string = text

        context.coordinator.textView = textView
        context.coordinator.highlighter.highlight(textView.textStorage!)
        scrollView.documentView = textView

        DispatchQueue.main.async {
            context.coordinator.remeasure(in: scrollView)
            if focusOnAppear, !context.coordinator.didFocusInitially {
                context.coordinator.didFocusInitially = true
                textView.window?.makeFirstResponder(textView)
                textView.setSelectedRange(NSRange(location: textView.string.utf16.count, length: 0))
                textView.scrollRangeToVisible(textView.selectedRange())
            }
        }

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = scrollView.documentView as? MarkdownTextView else { return }
        textView.insertionPointColor = .labelColor

        if !context.coordinator.isUpdatingFromTextView, textView.string != text {
            context.coordinator.isUpdatingFromSwiftUI = true
            let selection = textView.selectedRange()
            textView.string = text
            textView.setSelectedRange(selection.location <= textView.string.utf16.count ? selection : NSRange(location: textView.string.utf16.count, length: 0))
            context.coordinator.highlighter.highlight(textView.textStorage!)
            context.coordinator.isUpdatingFromSwiftUI = false
        }

        DispatchQueue.main.async {
            context.coordinator.remeasure(in: scrollView)
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MarkdownEditorView
        let highlighter = MarkdownSyntaxHighlighter()
        weak var textView: MarkdownTextView?
        var isUpdatingFromSwiftUI = false
        var isUpdatingFromTextView = false
        var didFocusInitially = false

        init(_ parent: MarkdownEditorView) {
            self.parent = parent
        }

        func textDidBeginEditing(_ notification: Notification) {
            MarkdownTextView.activeEditor = notification.object as? MarkdownTextView
        }

        func textDidChange(_ notification: Notification) {
            guard !isUpdatingFromSwiftUI,
                  let textView = notification.object as? MarkdownTextView else { return }
            isUpdatingFromTextView = true
            highlighter.highlight(textView.textStorage!)
            parent.text = textView.string
            isUpdatingFromTextView = false
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
            if abs(parent.measuredHeight - target) > 1 {
                parent.measuredHeight = target
            }
        }
    }
}
