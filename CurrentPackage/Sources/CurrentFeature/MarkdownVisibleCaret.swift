import AppKit

struct MarkdownVisibleCaret: Equatable {
    var rawLocation: Int
    var visibleLocation: Int
    var lineRange: NSRange

    static func visibleLocation(in text: String, at location: Int) -> Int {
        MarkdownEditorRenderModel(text: text).visibleInsertionLocation(for: location)
    }

    static func caret(in text: String, at location: Int) -> MarkdownVisibleCaret? {
        let model = MarkdownEditorRenderModel(text: text)
        let visibleLocation = model.visibleInsertionLocation(for: location)
        let nsText = text as NSString
        guard visibleLocation >= 0, visibleLocation <= nsText.length else { return nil }
        let lineRange = nsText.length > 0
            ? nsText.lineRange(for: NSRange(location: min(visibleLocation, max(0, nsText.length - 1)), length: 0))
            : NSRange(location: 0, length: 0)
        return MarkdownVisibleCaret(rawLocation: location, visibleLocation: visibleLocation, lineRange: lineRange)
    }

    @MainActor
    static func insertionRect(in textView: NSTextView, at location: Int? = nil) -> NSRect? {
        guard let textContainer = textView.textContainer,
              let layoutManager = textView.layoutManager else {
            return nil
        }

        let selectedLocation = location ?? textView.selectedRange().location
        let model = MarkdownEditorRenderModel(text: textView.string)
        let visibleLocation = model.visibleInsertionLocation(for: selectedLocation)
        guard let heading = model.heading(at: visibleLocation),
              visibleLocation >= heading.prefixRange.location,
              visibleLocation <= heading.contentRange.location,
              heading.prefixRange.length > 0 else {
            return nil
        }
        if let storage = textView.textStorage as? MarkdownTextStorage,
           storage.syntaxRangeIsRevealed(heading.prefixRange) {
            return nil
        }

        layoutManager.ensureLayout(for: textContainer)
        let markerGlyphRange = layoutManager.glyphRange(
            forCharacterRange: heading.prefixRange,
            actualCharacterRange: nil
        )
        guard markerGlyphRange.location != NSNotFound,
              markerGlyphRange.length > 0,
              layoutManager.numberOfGlyphs > markerGlyphRange.location else {
            return nil
        }

        let lineRect = layoutManager.lineFragmentRect(forGlyphAt: markerGlyphRange.location, effectiveRange: nil)
        let origin = textView.textContainerOrigin
        return NSRect(
            x: origin.x + lineRect.minX,
            y: origin.y + lineRect.minY,
            width: 1,
            height: lineRect.height
        )
    }

    @MainActor
    static func firstRect(in textView: NSTextView, for range: NSRange) -> NSRect? {
        guard range.length == 0,
              let window = textView.window,
              let insertionRect = insertionRect(in: textView, at: range.location) else {
            return nil
        }

        let windowRect = textView.convert(insertionRect, to: nil)
        return window.convertToScreen(windowRect)
    }

    @MainActor
    static func caretY(in collectionView: NSCollectionView, for textView: MarkdownTextView) -> CGFloat? {
        let selection = textView.selectedRange()
        let screenRect = firstRect(in: textView, for: NSRange(location: selection.location, length: 0))
            ?? textView.firstRect(
                forCharacterRange: NSRange(location: min(max(0, selection.location), textView.string.utf16.count), length: 0),
                actualRange: nil
            )
        guard !screenRect.isNull,
              screenRect.origin.x.isFinite,
              screenRect.origin.y.isFinite,
              let window = textView.window else {
            return nil
        }

        let windowRect = window.convertFromScreen(screenRect)
        let collectionRect = collectionView.convert(windowRect, from: nil)
        return collectionRect.minY
    }
}
