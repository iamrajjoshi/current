import Foundation

public enum MarkdownBlockEditing {
    public typealias TextEdit = MarkdownListEditing.TextEdit

    public static func headingBackspaceEdit(in text: String, selectedRange: NSRange) -> TextEdit? {
        guard selectedRange.length == 0,
              let heading = MarkdownBlockRendering.headingLine(in: text, at: selectedRange.location) else {
            return nil
        }

        let cursor = selectedRange.location
        if heading.hasContent {
            guard cursor == heading.contentRange.location else { return nil }
        } else {
            guard cursor == NSMaxRange(heading.prefixRange) else { return nil }
        }

        return TextEdit(
            range: heading.prefixRange,
            replacement: "",
            selectedRangeAfterEdit: NSRange(location: heading.lineRange.location, length: 0)
        )
    }
}
