import Foundation

public enum MarkdownInlineRendering {
    public enum Kind: Equatable, Sendable {
        case bold
        case italic
        case underline
        case strikethrough
        case inlineCode
        case link
    }

    public struct Span: Equatable, Sendable {
        public var kind: Kind
        public var fullRange: NSRange
        public var contentRange: NSRange
        public var syntaxRanges: [NSRange]
    }

    private struct Pattern {
        var kind: Kind
        var regex: NSRegularExpression

        init(
            kind: Kind,
            pattern: String,
            options: NSRegularExpression.Options = []
        ) {
            self.kind = kind
            self.regex = try! NSRegularExpression(pattern: pattern, options: options)
        }
    }

    public static func spans(in text: String, protectedRanges: [NSRange] = []) -> [Span] {
        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)
        guard fullRange.length > 0 else { return [] }

        var spans: [Span] = []
        for pattern in patterns {
            pattern.regex.enumerateMatches(in: text, range: fullRange) { match, _, _ in
                guard let match,
                      match.numberOfRanges >= 4,
                      !intersects(match.range, protectedRanges),
                      !hasCrossingOverlap(match.range, spans.map(\.fullRange)) else {
                    return
                }

                let openRange = match.range(at: 1)
                let contentRange = match.range(at: 2)
                let closeRange = match.range(at: 3)
                guard openRange.location != NSNotFound,
                      contentRange.location != NSNotFound,
                      contentRange.length > 0,
                      closeRange.location != NSNotFound else {
                    return
                }

                spans.append(Span(
                    kind: pattern.kind,
                    fullRange: match.range,
                    contentRange: contentRange,
                    syntaxRanges: [openRange, closeRange]
                ))
            }
        }

        return spans.sorted { lhs, rhs in
            if lhs.fullRange.location == rhs.fullRange.location {
                return lhs.fullRange.length > rhs.fullRange.length
            }
            return lhs.fullRange.location < rhs.fullRange.location
        }
    }

    static func emptyFormattingSpan(in text: String, at cursor: Int) -> Span? {
        let nsText = text as NSString
        guard cursor >= 0, cursor <= nsText.length else { return nil }

        for marker in emptyMarkers {
            let openLength = marker.open.utf16.count
            let closeLength = marker.close.utf16.count
            let start = cursor - openLength
            let end = cursor + closeLength
            guard start >= 0, end <= nsText.length else { continue }

            let openRange = NSRange(location: start, length: openLength)
            let closeRange = NSRange(location: cursor, length: closeLength)
            if nsText.substring(with: openRange).lowercased() == marker.open.lowercased(),
               nsText.substring(with: closeRange).lowercased() == marker.close.lowercased() {
                return Span(
                    kind: marker.kind,
                    fullRange: NSRange(location: start, length: openLength + closeLength),
                    contentRange: NSRange(location: cursor, length: 0),
                    syntaxRanges: [openRange, closeRange]
                )
            }
        }

        return nil
    }

    private static var patterns: [Pattern] {
        [
            Pattern(kind: .inlineCode, pattern: #"(`+)([^`\n]+)(\1)"#),
            Pattern(kind: .link, pattern: #"(!?\[)([^\]\n]+)(\]\([^)]+\))"#),
            Pattern(kind: .underline, pattern: #"((?:<u>)+)([^<\n]+)((?:</u>)+)"#, options: [.caseInsensitive]),
            Pattern(kind: .strikethrough, pattern: #"(?<!~)((?:~~)+)([^~\n]+)(\1)(?!~)"#),
            Pattern(kind: .bold, pattern: #"(?<!\*)((?:\*\*)+)([^*\n]+)(\1)(?!\*)"#),
            Pattern(kind: .bold, pattern: #"(?<!_)((?:__)+)([^_\n]+)(\1)(?!_)"#),
            Pattern(kind: .italic, pattern: #"(?<!\*)(\*)([^*\n]+)(\*)(?!\*)"#),
            Pattern(kind: .italic, pattern: #"(?<!_)(_)([^_\n]+)(_)(?!_)"#)
        ]
    }

    private static var emptyMarkers: [(kind: Kind, open: String, close: String)] {
        [
            (.underline, "<u>", "</u>"),
            (.bold, "**", "**"),
            (.bold, "__", "__"),
            (.strikethrough, "~~", "~~"),
            (.inlineCode, "`", "`"),
            (.italic, "*", "*"),
            (.italic, "_", "_")
        ]
    }

    private static func intersects(_ range: NSRange, _ ranges: [NSRange]) -> Bool {
        ranges.contains { NSIntersectionRange(range, $0).length > 0 }
    }

    private static func hasCrossingOverlap(_ range: NSRange, _ ranges: [NSRange]) -> Bool {
        ranges.contains { existingRange in
            guard NSIntersectionRange(range, existingRange).length > 0 else { return false }
            return !contains(range, existingRange) && !contains(existingRange, range)
        }
    }

    private static func contains(_ outerRange: NSRange, _ innerRange: NSRange) -> Bool {
        innerRange.location >= outerRange.location
            && NSMaxRange(innerRange) <= NSMaxRange(outerRange)
    }
}
