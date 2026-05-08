import Foundation

public enum MarkdownInlineFormatting {
    public typealias TextEdit = MarkdownListEditing.TextEdit

    public enum Kind: Hashable {
        case bold
        case italic
        case underline
        case strikethrough
        case inlineCode
    }

    public static func formattingEdit(kind: Kind, in text: String, selectedRange: NSRange) -> TextEdit? {
        let nsText = text as NSString
        guard isValid(selectedRange, in: nsText) else { return nil }

        guard selectedRange.length > 0 else { return nil }

        return canonicalFormattingEdit(kind: kind, in: text, selectedRange: selectedRange)
    }

    public static func linkEdit(in text: String, selectedRange: NSRange, urlString: String) -> TextEdit? {
        let nsText = text as NSString
        let normalizedSelection = MarkdownSelectionNormalization.normalizedVisibleSelection(
            in: text,
            selectedRange: selectedRange
        )
        guard isValid(normalizedSelection, in: nsText), normalizedSelection.length > 0 else { return nil }
        guard let url = validLinkURLString(from: urlString) else { return nil }

        let selectedText = nsText.substring(with: normalizedSelection)
        let replacement = "[\(escapeLinkText(selectedText))](\(escapeLinkDestination(url)))"
        return TextEdit(
            range: normalizedSelection,
            replacement: replacement,
            selectedRangeAfterEdit: NSRange(location: normalizedSelection.location + replacement.utf16.count, length: 0)
        )
    }

    public static func backspaceEdit(in text: String, selectedRange: NSRange) -> TextEdit? {
        let nsText = text as NSString
        guard selectedRange.length == 0,
              isValid(selectedRange, in: nsText) else {
            return nil
        }

        let cursor = selectedRange.location
        if let emptySpan = MarkdownInlineRendering.emptyFormattingSpan(in: text, at: cursor) {
            return TextEdit(
                range: emptySpan.fullRange,
                replacement: "",
                selectedRangeAfterEdit: NSRange(location: emptySpan.fullRange.location, length: 0)
            )
        }

        let model = MarkdownEditorRenderModel(text: text)
        for span in model.inlineSpans {
            guard NSLocationInRange(cursor, NSRange(location: span.fullRange.location, length: span.fullRange.length + 1)) else {
                continue
            }

            let openRange = span.syntaxRanges.first ?? NSRange(location: NSNotFound, length: 0)
            let closeRange = span.syntaxRanges.last ?? NSRange(location: NSNotFound, length: 0)
            if cursor == span.contentRange.location ||
                isCursorInsideOrAfterHiddenSyntax(cursor, syntaxRange: openRange) {
                return unwrapEdit(span: span, in: nsText)
            }

            if isCursorInsideOrAfterHiddenSyntax(cursor, syntaxRange: closeRange) ||
                cursor == NSMaxRange(span.fullRange) {
                if span.contentRange.length <= 1 {
                    return TextEdit(
                        range: span.fullRange,
                        replacement: "",
                        selectedRangeAfterEdit: NSRange(location: span.fullRange.location, length: 0)
                    )
                }

                return TextEdit(
                    range: NSRange(location: NSMaxRange(span.contentRange) - 1, length: 1),
                    replacement: "",
                    selectedRangeAfterEdit: NSRange(location: NSMaxRange(span.contentRange) - 1, length: 0)
                )
            }
        }

        return nil
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

    private struct InlineCharacter {
        var text: String
        var utf16Length: Int
        var marks: Set<Kind>
        var linkDestination: String?
        var linkOpening: String?
        var isSelected: Bool
    }

    private struct SerializationState {
        var text = ""
        var location = 0
        var selectedStart: Int?
        var selectedEnd: Int?

        mutating func appendSyntax(_ string: String) {
            text += string
            location += string.utf16.count
        }

        mutating func appendVisible(_ character: InlineCharacter) {
            if character.isSelected {
                if selectedStart == nil {
                    selectedStart = location
                }
                selectedEnd = location + character.utf16Length
            }
            text += character.text
            location += character.utf16Length
        }
    }

    private static func canonicalFormattingEdit(kind: Kind, in text: String, selectedRange: NSRange) -> TextEdit? {
        let nsText = text as NSString
        let model = MarkdownEditorRenderModel(text: text)
        let editRange = lineRangeCoveringSelection(selectedRange, in: nsText)
        guard editRange.length > 0 else { return nil }

        var lines: [(prefix: String, characters: [InlineCharacter], suffix: String)] = []
        var selectedCharacters: [InlineCharacter] = []
        var location = editRange.location
        let editEnd = NSMaxRange(editRange)

        while location < editEnd {
            let lineRange = nsText.lineRange(for: NSRange(location: location, length: 0))
            let lineBodyRange = lineBodyRange(from: lineRange, in: nsText)
            let contentRange = inlineContentRange(in: text, lineBodyRange: lineBodyRange, model: model)
            let prefixRange = NSRange(location: lineRange.location, length: max(0, contentRange.location - lineRange.location))
            let suffixRange = NSRange(
                location: NSMaxRange(contentRange),
                length: max(0, NSMaxRange(lineRange) - NSMaxRange(contentRange))
            )
            let content = nsText.substring(with: contentRange)
            let characters = inlineCharacters(
                in: content,
                model: MarkdownEditorRenderModel(text: content),
                baseLocation: contentRange.location,
                selectedRange: selectedRange
            )
            selectedCharacters.append(contentsOf: characters.filter(\.isSelected))
            lines.append((
                prefix: nsText.substring(with: prefixRange),
                characters: characters,
                suffix: nsText.substring(with: suffixRange)
            ))

            let nextLocation = NSMaxRange(lineRange)
            guard nextLocation > location else { break }
            location = nextLocation
        }

        guard !selectedCharacters.isEmpty else { return nil }
        if kind != .inlineCode, selectedCharacters.contains(where: { $0.marks.contains(.inlineCode) }) {
            return nil
        }

        let shouldRemove = selectedCharacters.allSatisfy { $0.marks.contains(kind) }
        for lineIndex in lines.indices {
            for characterIndex in lines[lineIndex].characters.indices where lines[lineIndex].characters[characterIndex].isSelected {
                if kind == .inlineCode {
                    if shouldRemove {
                        lines[lineIndex].characters[characterIndex].marks.remove(.inlineCode)
                    } else {
                        lines[lineIndex].characters[characterIndex].marks = [.inlineCode]
                    }
                    continue
                }

                if shouldRemove {
                    lines[lineIndex].characters[characterIndex].marks.remove(kind)
                } else {
                    lines[lineIndex].characters[characterIndex].marks.insert(kind)
                }
            }
        }

        var state = SerializationState()
        for line in lines {
            state.appendSyntax(line.prefix)
            serializeLinkedRuns(line.characters, into: &state)
            state.appendSyntax(line.suffix)
        }

        guard let selectedStart = state.selectedStart,
              let selectedEnd = state.selectedEnd else {
            return nil
        }

        return TextEdit(
            range: editRange,
            replacement: state.text,
            selectedRangeAfterEdit: NSRange(
                location: editRange.location + selectedStart,
                length: selectedEnd - selectedStart
            )
        )
    }

    private static func inlineCharacters(
        in text: String,
        model: MarkdownEditorRenderModel,
        baseLocation: Int,
        selectedRange: NSRange
    ) -> [InlineCharacter] {
        let nsText = text as NSString
        guard nsText.length > 0 else { return [] }

        let spans = model.inlineSpans
        let hiddenRanges = spans.flatMap(\.syntaxRanges)
        var characters: [InlineCharacter] = []

        var location = 0
        while location < nsText.length {
            let characterRange = nsText.rangeOfComposedCharacterSequence(at: location)
            defer { location = NSMaxRange(characterRange) }
            guard !rangesIntersect(characterRange, hiddenRanges) else { continue }

            let absoluteRange = NSRange(location: baseLocation + characterRange.location, length: characterRange.length)
            let activeSpans = spans.filter { NSIntersectionRange(characterRange, $0.contentRange).length > 0 }
            let hasCode = activeSpans.contains { $0.kind == .inlineCode }
            let marks = marks(from: activeSpans, hasCode: hasCode)
            let linkSpans = activeSpans.filter { $0.kind == MarkdownInlineRendering.Kind.link }
            let linkSpan = linkSpans.isEmpty ? nil : linkSpans[linkSpans.count - 1]
            let linkDestination = linkSpans.isEmpty
                ? nil
                : linkDestination(for: linkSpans[linkSpans.count - 1], in: nsText)
            let linkOpeningValue: String?
            if let linkSpan {
                linkOpeningValue = markdownLinkOpening(for: linkSpan, in: nsText)
            } else {
                linkOpeningValue = nil
            }

            characters.append(InlineCharacter(
                text: nsText.substring(with: characterRange),
                utf16Length: characterRange.length,
                marks: marks,
                linkDestination: linkDestination,
                linkOpening: linkOpeningValue,
                isSelected: NSIntersectionRange(absoluteRange, selectedRange).length > 0
            ))
        }

        return characters
    }

    private static func marks(
        from spans: [MarkdownInlineRendering.Span],
        hasCode: Bool
    ) -> Set<Kind> {
        if hasCode {
            return [.inlineCode]
        }

        return Set(spans.compactMap { span -> Kind? in
            switch span.kind {
            case .bold:
                return .bold
            case .italic:
                return .italic
            case .underline:
                return .underline
            case .strikethrough:
                return .strikethrough
            case .inlineCode:
                return .inlineCode
            case .link:
                return nil
            }
        })
    }

    private static func serializeLinkedRuns(
        _ characters: [InlineCharacter],
        into state: inout SerializationState
    ) {
        var location = 0
        while location < characters.count {
            let destination = characters[location].linkDestination
            let opening = characters[location].linkOpening
            var end = location + 1
            while end < characters.count,
                  characters[end].linkDestination == destination,
                  characters[end].linkOpening == opening {
                end += 1
            }

            let run = Array(characters[location..<end])
            if let destination {
                state.appendSyntax(opening ?? "[")
                serializeMarkedRuns(run, into: &state)
                state.appendSyntax("](\(destination))")
            } else {
                serializeMarkedRuns(run, into: &state)
            }
            location = end
        }
    }

    private static func serializeMarkedRuns(
        _ characters: [InlineCharacter],
        into state: inout SerializationState
    ) {
        var location = 0
        while location < characters.count {
            let marks = characters[location].marks
            var end = location + 1
            while end < characters.count, characters[end].marks == marks {
                end += 1
            }

            let orderedMarks = canonicalMarks(from: marks)
            orderedMarks.forEach { state.appendSyntax(canonicalMarkers(for: $0).open) }
            for character in characters[location..<end] {
                state.appendVisible(character)
            }
            orderedMarks.reversed().forEach { state.appendSyntax(canonicalMarkers(for: $0).close) }
            location = end
        }
    }

    private static func canonicalMarks(from marks: Set<Kind>) -> [Kind] {
        if marks.contains(.inlineCode) {
            return [.inlineCode]
        }
        return [.bold, .italic, .underline, .strikethrough].filter { marks.contains($0) }
    }

    private static func canonicalMarkers(for kind: Kind) -> (open: String, close: String) {
        switch kind {
        case .bold:
            return ("**", "**")
        case .italic:
            return ("_", "_")
        case .underline:
            return ("<u>", "</u>")
        case .strikethrough:
            return ("~~", "~~")
        case .inlineCode:
            return ("`", "`")
        }
    }

    private static func inlineContentRange(in text: String, lineBodyRange: NSRange, model: MarkdownEditorRenderModel) -> NSRange {
        if let list = model.list(at: lineBodyRange.location),
           list.lineRange.location == lineBodyRange.location || NSLocationInRange(lineBodyRange.location, list.lineRange) {
            return list.contentRange
        }

        if let heading = model.heading(at: lineBodyRange.location),
           heading.lineRange.location == lineBodyRange.location || NSLocationInRange(lineBodyRange.location, heading.lineRange) {
            return heading.contentRange
        }

        return lineBodyRange
    }

    private static func linkDestination(for span: MarkdownInlineRendering.Span, in text: NSString) -> String? {
        guard span.kind == .link,
              let closeRange = span.syntaxRanges.last,
              closeRange.location != NSNotFound,
              closeRange.length >= 3 else {
            return nil
        }

        let closeSyntax = text.substring(with: closeRange)
        guard closeSyntax.hasPrefix("]("), closeSyntax.hasSuffix(")") else { return nil }
        let start = closeSyntax.index(closeSyntax.startIndex, offsetBy: 2)
        let end = closeSyntax.index(before: closeSyntax.endIndex)
        return String(closeSyntax[start..<end])
    }

    private static func markdownLinkOpening(for span: MarkdownInlineRendering.Span, in text: NSString) -> String? {
        guard span.kind == .link,
              let openRange = span.syntaxRanges.first,
              openRange.location != NSNotFound else {
            return nil
        }
        return text.substring(with: openRange)
    }

    private static func lineRangeCoveringSelection(_ selection: NSRange, in text: NSString) -> NSRange {
        let start = min(selection.location, text.length)
        let effectiveEnd = selection.length == 0
            ? start
            : min(text.length, max(start, NSMaxRange(selection) - 1))
        let range = NSRange(location: start, length: max(0, effectiveEnd - start))
        return text.lineRange(for: range)
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

    private static func rangesIntersect(_ range: NSRange, _ ranges: [NSRange]) -> Bool {
        ranges.contains { NSIntersectionRange(range, $0).length > 0 }
    }

    private static func isValid(_ range: NSRange, in text: NSString) -> Bool {
        range.location >= 0 && range.length >= 0 && NSMaxRange(range) <= text.length
    }

    private static func unwrapEdit(span: MarkdownInlineRendering.Span, in text: NSString) -> TextEdit {
        let content = text.substring(with: span.contentRange)
        return TextEdit(
            range: span.fullRange,
            replacement: content,
            selectedRangeAfterEdit: NSRange(location: span.fullRange.location, length: 0)
        )
    }

    private static func isCursorInsideOrAfterHiddenSyntax(_ cursor: Int, syntaxRange: NSRange) -> Bool {
        guard syntaxRange.location != NSNotFound else { return false }
        return cursor > syntaxRange.location && cursor <= NSMaxRange(syntaxRange)
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
