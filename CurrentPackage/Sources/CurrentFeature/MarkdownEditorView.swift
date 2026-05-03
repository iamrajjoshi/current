import AppKit
import SwiftUI

final class MarkdownTextView: NSTextView {
    weak static var activeEditor: MarkdownTextView?
    private static var editorsByDayID: [String: WeakMarkdownTextView] = [:]
    var onFocus: (() -> Void)?
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
        if let edit = inlineFormattingEdit(for: event, modifiers: modifiers),
           apply(edit) {
            return
        }

        switch event.keyCode {
        case 51 where modifiers.isEmpty:
            if apply(MarkdownBlockEditing.headingBackspaceEdit(in: string, selectedRange: selectedRange())) {
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

    private func inlineFormattingEdit(
        for event: NSEvent,
        modifiers: NSEvent.ModifierFlags
    ) -> MarkdownListEditing.TextEdit? {
        guard let key = event.charactersIgnoringModifiers?.lowercased() else { return nil }
        let selection = selectedRange()

        switch (key, modifiers) {
        case ("b", .command):
            return MarkdownInlineFormatting.formattingEdit(kind: .bold, in: string, selectedRange: selection)
        case ("i", .command):
            return MarkdownInlineFormatting.formattingEdit(kind: .italic, in: string, selectedRange: selection)
        case ("u", .command):
            return MarkdownInlineFormatting.formattingEdit(kind: .underline, in: string, selectedRange: selection)
        case ("s", [.command, .shift]):
            return MarkdownInlineFormatting.formattingEdit(kind: .strikethrough, in: string, selectedRange: selection)
        case ("e", .command):
            return MarkdownInlineFormatting.formattingEdit(kind: .inlineCode, in: string, selectedRange: selection)
        case ("k", .command):
            return MarkdownInlineFormatting.linkEdit(
                in: string,
                selectedRange: selection,
                urlString: NSPasteboard.general.string(forType: .string) ?? ""
            )
        default:
            return nil
        }
    }

    private func apply(_ edit: MarkdownListEditing.TextEdit?) -> Bool {
        guard let edit else { return false }
        insertText(edit.replacement, replacementRange: edit.range)
        setSelectedRange(edit.selectedRangeAfterEdit)
        return true
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

        let textView = MarkdownTextView()
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
        textView.string = text
        textView.currentDayID = dayID

        context.coordinator.textView = textView
        context.coordinator.updateTypingAttributes(for: textView)
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
        let configurationChanged = context.coordinator.highlightedConfiguration != configuration
        context.coordinator.parent = self
        context.coordinator.highlighter.update(configuration: configuration)
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
            context.coordinator.updateTypingAttributes(for: textView)
        }

        if textChanged {
            context.coordinator.isUpdatingFromSwiftUI = true
            let selection = textView.selectedRange()
            textView.string = text
            textView.setSelectedRange(selection.location <= textView.string.utf16.count ? selection : NSRange(location: textView.string.utf16.count, length: 0))
            context.coordinator.highlighter.highlight(textView.textStorage!)
            context.coordinator.highlightedConfiguration = configuration
            context.coordinator.isUpdatingFromSwiftUI = false
        } else if configurationChanged {
            context.coordinator.highlighter.highlight(textView.textStorage!)
            context.coordinator.highlightedConfiguration = configuration
        }

        DispatchQueue.main.async {
            context.coordinator.remeasure(in: scrollView)
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MarkdownEditorView
        let highlighter: MarkdownSyntaxHighlighter
        weak var textView: MarkdownTextView?
        var isUpdatingFromSwiftUI = false
        var isUpdatingFromTextView = false
        var didFocusInitially = false
        var highlightedConfiguration: CurrentConfiguration
        var lastMeasuredWidth: CGFloat = 0

        init(_ parent: MarkdownEditorView) {
            self.parent = parent
            self.highlighter = MarkdownSyntaxHighlighter(configuration: parent.configuration)
            self.highlightedConfiguration = parent.configuration
        }

        func textDidBeginEditing(_ notification: Notification) {
            guard let textView = notification.object as? MarkdownTextView else { return }
            MarkdownTextView.activeEditor = textView
            parent.onFocus()
            clearTemporaryDecorations(for: textView)
            updateTypingAttributes(for: textView)
        }

        func textDidChange(_ notification: Notification) {
            guard !isUpdatingFromSwiftUI,
                  let textView = notification.object as? MarkdownTextView else { return }
            isUpdatingFromTextView = true
            highlighter.highlight(textView.textStorage!)
            highlightedConfiguration = parent.configuration
            updateTypingAttributes(for: textView)
            parent.text = textView.string
            isUpdatingFromTextView = false
            if let scrollView = textView.enclosingScrollView {
                remeasure(in: scrollView)
            }
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? MarkdownTextView else { return }
            updateTypingAttributes(for: textView)
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
            let paragraph = NSMutableParagraphStyle()
            paragraph.minimumLineHeight = CurrentTheme.editorLineHeight(configuration: parent.configuration)
            paragraph.maximumLineHeight = CurrentTheme.editorLineHeight(configuration: parent.configuration)
            paragraph.lineBreakMode = .byWordWrapping

            var attributes: [NSAttributedString.Key: Any] = [
                .font: CurrentTheme.editorFont(configuration: parent.configuration),
                .foregroundColor: CurrentTheme.primaryTextColor,
                .paragraphStyle: paragraph,
                .baselineOffset: CurrentTheme.editorBaselineOffset,
                .underlineStyle: 0,
                .strikethroughStyle: 0,
                .backgroundColor: NSColor.clear
            ]

            let selection = textView.selectedRange()
            if selection.length == 0,
               let heading = MarkdownBlockRendering.headingLine(in: textView.string, at: selection.location),
               selection.location >= heading.contentRange.location {
                paragraph.minimumLineHeight = CurrentTheme.editorHeadingLineHeight(level: heading.level, configuration: parent.configuration)
                paragraph.maximumLineHeight = CurrentTheme.editorHeadingLineHeight(level: heading.level, configuration: parent.configuration)
                paragraph.paragraphSpacingBefore = CurrentTheme.editorHeadingSpacingBefore(level: heading.level)
                paragraph.paragraphSpacing = CurrentTheme.editorHeadingSpacingAfter(level: heading.level)
                attributes[.font] = CurrentTheme.editorHeadingFont(level: heading.level, configuration: parent.configuration)
                attributes[.paragraphStyle] = paragraph
            }

            textView.typingAttributes = attributes
        }

        private func clearTemporaryDecorations(for textView: NSTextView) {
            guard let textStorage = textView.textStorage else { return }
            highlighter.clearTemporaryDecorations(textStorage)
            if textStorage.length > 0 {
                textView.layoutManager?.invalidateDisplay(
                    forCharacterRange: NSRange(location: 0, length: textStorage.length)
                )
            }
        }
    }
}
