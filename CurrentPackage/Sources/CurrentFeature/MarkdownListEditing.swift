import Foundation

public enum MarkdownListEditing {
    public struct TextEdit: Equatable {
        public var range: NSRange
        public var replacement: String
        public var selectedRangeAfterEdit: NSRange
    }

    private static let listLineRegex = try! NSRegularExpression(
        pattern: #"^([ \t]*)(?:(\d+)\.|([-*+]))[ \t]+(?:(\[[ xX]\])[ \t]+)?(.*)$"#
    )

    public static func continuationEdit(in text: String, selectedRange: NSRange) -> TextEdit? {
        guard selectedRange.length == 0 else { return nil }
        let nsText = text as NSString
        guard selectedRange.location <= nsText.length else { return nil }
        guard !isInsideFencedCodeBlock(nsText, location: selectedRange.location) else { return nil }

        let lineRange = nsText.lineRange(for: NSRange(location: selectedRange.location, length: 0))
        let lineBodyRange = lineBodyRange(from: lineRange, in: nsText)
        let line = nsText.substring(with: lineBodyRange)
        guard let marker = marker(in: line) else { return nil }

        if marker.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return TextEdit(
                range: lineBodyRange,
                replacement: "",
                selectedRangeAfterEdit: NSRange(location: lineRange.location, length: 0)
            )
        }

        let continuation = "\n\(marker.indent)\(marker.nextMarker)"
        let locationAfterEdit = selectedRange.location + continuation.utf16.count
        return TextEdit(
            range: selectedRange,
            replacement: continuation,
            selectedRangeAfterEdit: NSRange(location: locationAfterEdit, length: 0)
        )
    }

    public static func indentationEdit(in text: String, selectedRange: NSRange, outdent: Bool) -> TextEdit? {
        let nsText = text as NSString
        guard selectedRange.location <= nsText.length else { return nil }

        if selectedRange.length == 0, !outdent {
            return TextEdit(
                range: selectedRange,
                replacement: "    ",
                selectedRangeAfterEdit: NSRange(location: selectedRange.location + 4, length: 0)
            )
        }

        let affectedRange = lineRangeCoveringSelection(selectedRange, in: nsText)
        let block = nsText.substring(with: affectedRange)
        let lines = block.components(separatedBy: "\n")
        var changed = false

        let rewritten = lines.map { line -> String in
            guard !line.isEmpty else { return line }
            if outdent {
                if line.hasPrefix("    ") {
                    changed = true
                    return String(line.dropFirst(4))
                }
                if line.hasPrefix("  ") {
                    changed = true
                    return String(line.dropFirst(2))
                }
                if line.hasPrefix("\t") {
                    changed = true
                    return String(line.dropFirst())
                }
                return line
            }
            changed = true
            return "  \(line)"
        }
        .joined(separator: "\n")

        guard changed else { return nil }
        let delta = rewritten.utf16.count - block.utf16.count
        let selectionLocation = max(affectedRange.location, selectedRange.location + (outdent ? min(0, delta) : 2))
        return TextEdit(
            range: affectedRange,
            replacement: rewritten,
            selectedRangeAfterEdit: NSRange(location: selectionLocation, length: max(0, selectedRange.length + delta))
        )
    }

    private struct Marker {
        var indent: String
        var nextMarker: String
        var content: String
    }

    private static func marker(in line: String) -> Marker? {
        let nsLine = line as NSString
        let range = NSRange(location: 0, length: nsLine.length)
        guard let match = listLineRegex.firstMatch(in: line, range: range) else { return nil }

        let indent = substring(in: nsLine, match: match, group: 1)
        let orderedNumber = substring(in: nsLine, match: match, group: 2)
        let bullet = substring(in: nsLine, match: match, group: 3)
        let task = substring(in: nsLine, match: match, group: 4)
        let content = substring(in: nsLine, match: match, group: 5)

        if !orderedNumber.isEmpty, let number = Int(orderedNumber) {
            return Marker(indent: indent, nextMarker: "\(number + 1). ", content: content)
        }

        let marker = bullet.isEmpty ? "-" : bullet
        if !task.isEmpty {
            return Marker(indent: indent, nextMarker: "\(marker) [ ] ", content: content)
        }
        return Marker(indent: indent, nextMarker: "\(marker) ", content: content)
    }

    private static func substring(in string: NSString, match: NSTextCheckingResult, group: Int) -> String {
        guard group < match.numberOfRanges else { return "" }
        let range = match.range(at: group)
        guard range.location != NSNotFound else { return "" }
        return string.substring(with: range)
    }

    private static func lineBodyRange(from lineRange: NSRange, in text: NSString) -> NSRange {
        guard lineRange.length > 0 else { return lineRange }
        let lastLocation = lineRange.location + lineRange.length - 1
        let lastCharacter = text.substring(with: NSRange(location: lastLocation, length: 1))
        if lastCharacter == "\n" {
            return NSRange(location: lineRange.location, length: lineRange.length - 1)
        }
        return lineRange
    }

    private static func lineRangeCoveringSelection(_ selection: NSRange, in text: NSString) -> NSRange {
        let start = min(selection.location, text.length)
        let effectiveEnd = selection.length == 0
            ? start
            : min(text.length, max(start, selection.location + selection.length - 1))
        let range = NSRange(location: start, length: max(0, effectiveEnd - start))
        return text.lineRange(for: range)
    }

    private static func isInsideFencedCodeBlock(_ text: NSString, location: Int) -> Bool {
        guard location > 0 else { return false }
        let prefix = text.substring(with: NSRange(location: 0, length: min(location, text.length)))
        let fenceRegex = try? NSRegularExpression(pattern: #"(?m)^```"#)
        let matches = fenceRegex?.numberOfMatches(
            in: prefix,
            range: NSRange(location: 0, length: (prefix as NSString).length)
        ) ?? 0
        return !matches.isMultiple(of: 2)
    }
}
