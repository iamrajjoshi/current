import Foundation

public enum MarkdownBlockEditing {
    public typealias TextEdit = MarkdownListEditing.TextEdit

    public static func headingBackspaceEdit(in text: String, selectedRange: NSRange) -> TextEdit? {
        let model = MarkdownEditorRenderModel(text: text)
        guard selectedRange.length == 0,
              let heading = model.heading(at: selectedRange.location) else {
            return nil
        }

        let cursor = selectedRange.location
        if heading.hasContent {
            guard cursor == heading.contentRange.location || cursor == heading.lineRange.location else { return nil }
        } else {
            guard cursor == NSMaxRange(heading.prefixRange) || cursor == heading.lineRange.location else { return nil }
        }

        return TextEdit(
            range: heading.prefixRange,
            replacement: "",
            selectedRangeAfterEdit: NSRange(location: heading.lineRange.location, length: 0)
        )
    }

    public static func horizontalRuleBackspaceEdit(in text: String, selectedRange: NSRange) -> TextEdit? {
        let model = MarkdownEditorRenderModel(text: text)
        guard selectedRange.length == 0,
              let displayState = model.horizontalRule(at: selectedRange.location),
              case .committedDivider(let horizontalRule) = displayState else {
            return nil
        }

        let cursor = selectedRange.location
        let cursorInsideHiddenRule = cursor > horizontalRule.markerRange.location
            && cursor <= NSMaxRange(horizontalRule.markerRange)
        let cursorAtVisibleRuleStart = cursor == horizontalRule.lineRange.location
        guard cursorInsideHiddenRule || cursorAtVisibleRuleStart else {
            return nil
        }

        return TextEdit(
            range: horizontalRule.markerRange,
            replacement: "",
            selectedRangeAfterEdit: NSRange(location: horizontalRule.lineRange.location, length: 0)
        )
    }
}
