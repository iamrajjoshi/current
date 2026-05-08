import Foundation

public enum MarkdownSelectionNormalization {
    public static func normalizedVisibleSelection(in text: String, selectedRange: NSRange) -> NSRange {
        MarkdownEditorRenderModel(text: text).normalizedVisibleSelection(selectedRange)
    }

    public static func structuralContentRange(in text: String, at location: Int) -> NSRange? {
        MarkdownEditorRenderModel(text: text).structuralContentRange(at: location)
    }
}
