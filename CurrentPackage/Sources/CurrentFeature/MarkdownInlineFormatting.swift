import Foundation

public enum MarkdownInlineFormatting {
    public typealias TextEdit = MarkdownListEditing.TextEdit

    public enum Kind {
        case bold
        case italic
        case underline
        case strikethrough
        case inlineCode
    }

    public static func formattingEdit(kind: Kind, in text: String, selectedRange: NSRange) -> TextEdit? {
        let nsText = text as NSString
        guard isValid(selectedRange, in: nsText) else { return nil }

        let markers = markers(for: kind)
        if selectedRange.length == 0 {
            return TextEdit(
                range: selectedRange,
                replacement: markers.open + markers.close,
                selectedRangeAfterEdit: NSRange(location: selectedRange.location + markers.open.utf16.count, length: 0)
            )
        }

        let selectedText = nsText.substring(with: selectedRange)
        return TextEdit(
            range: selectedRange,
            replacement: markers.open + selectedText + markers.close,
            selectedRangeAfterEdit: NSRange(location: selectedRange.location + markers.open.utf16.count, length: selectedRange.length)
        )
    }

    public static func linkEdit(in text: String, selectedRange: NSRange, urlString: String) -> TextEdit? {
        let nsText = text as NSString
        guard isValid(selectedRange, in: nsText), selectedRange.length > 0 else { return nil }
        guard let url = validLinkURLString(from: urlString) else { return nil }

        let selectedText = nsText.substring(with: selectedRange)
        let replacement = "[\(escapeLinkText(selectedText))](\(escapeLinkDestination(url)))"
        return TextEdit(
            range: selectedRange,
            replacement: replacement,
            selectedRangeAfterEdit: NSRange(location: selectedRange.location + replacement.utf16.count, length: 0)
        )
    }

    public static func validLinkURLString(from string: String?) -> String? {
        guard let string else { return nil }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(),
              ["http", "https", "mailto"].contains(scheme) else {
            return nil
        }

        switch scheme {
        case "http", "https":
            guard components.host?.isEmpty == false else { return nil }
        case "mailto":
            guard !components.path.isEmpty else { return nil }
        default:
            return nil
        }

        return trimmed
    }

    private static func markers(for kind: Kind) -> (open: String, close: String) {
        switch kind {
        case .bold:
            return ("**", "**")
        case .italic:
            return ("*", "*")
        case .underline:
            return ("<u>", "</u>")
        case .strikethrough:
            return ("~~", "~~")
        case .inlineCode:
            return ("`", "`")
        }
    }

    private static func isValid(_ range: NSRange, in text: NSString) -> Bool {
        range.location >= 0 && range.length >= 0 && NSMaxRange(range) <= text.length
    }

    private static func escapeLinkText(_ text: String) -> String {
        text
            .replacingOccurrences(of: #"\"#, with: #"\\"#)
            .replacingOccurrences(of: "]", with: #"\]"#)
    }

    private static func escapeLinkDestination(_ text: String) -> String {
        text.replacingOccurrences(of: ")", with: "%29")
    }
}
