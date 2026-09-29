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
        // Inline syntax cannot cross a source line. Limit overlap checks to that
        // line instead of comparing each new match with the whole document.
        var location = 0
        var protectedIndex = 0
        while location < nsText.length {
            let lineRange = nsText.lineRange(for: NSRange(location: location, length: 0))
            while protectedIndex < protectedRanges.count, NSMaxRange(protectedRanges[protectedIndex]) <= location { protectedIndex += 1 }
            if protectedIndex < protectedRanges.count, NSIntersectionRange(protectedRanges[protectedIndex], lineRange).length > 0 {
                location = NSMaxRange(lineRange)
                continue
            }
            var lineSpans = codeSpans(in: nsText, lineRange: lineRange)
            for pattern in patterns {
                let previous = lineSpans.sorted { $0.fullRange.location < $1.fullRange.location }
                var maxEnd = 0
                let ends = previous.map { span in maxEnd = max(maxEnd, NSMaxRange(span.fullRange)); return maxEnd }
                pattern.regex.enumerateMatches(in: text, range: lineRange) { match, _, _ in
                    guard let match, match.numberOfRanges >= 4, !isEscaped(match.range.location, in: nsText) else { return }
                    var lower = 0, upper = previous.count
                    while lower < upper {
                        let middle = (lower + upper) / 2
                        if ends[middle] <= match.range.location { lower = middle + 1 } else { upper = middle }
                    }
                    var index = lower
                    while index < previous.count, previous[index].fullRange.location < NSMaxRange(match.range) {
                        let span = previous[index]
                        if NSIntersectionRange(span.fullRange, match.range).length > 0,
                           span.kind == .inlineCode || (!contains(span.fullRange, match.range) && !contains(match.range, span.fullRange)) { return }
                        index += 1
                    }
                    let openRange = match.range(at: 1)
                    let contentRange = match.range(at: 2)
                    let closeRange = match.range(at: 3)
                    guard openRange.location != NSNotFound, contentRange.location != NSNotFound,
                          contentRange.length > 0, closeRange.location != NSNotFound,
                          !isEscaped(closeRange.location, in: nsText) else { return }
                    lineSpans.append(Span(kind: pattern.kind, fullRange: match.range,
                                          contentRange: contentRange, syntaxRanges: [openRange, closeRange]))
                }
            }
            spans.append(contentsOf: lineSpans)
            location = NSMaxRange(lineRange)
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

    private static func codeSpans(in text: NSString, lineRange: NSRange) -> [Span] {
        var runs: [NSRange] = []
        var location = lineRange.location
        while location < NSMaxRange(lineRange) {
            guard text.character(at: location) == 96 else { location += 1; continue }
            let start = location
            while location < NSMaxRange(lineRange), text.character(at: location) == 96 { location += 1 }
            runs.append(NSRange(location: start, length: location - start))
        }
        // Match complete runs of the same length. Shorter backtick runs inside
        // code are literal, including Markdown links and formatting between them.
        var nextRunByLength: [Int: Int] = [:]
        var nextMatchingRun = [Int?](repeating: nil, count: runs.count)
        for index in runs.indices.reversed() {
            nextMatchingRun[index] = nextRunByLength[runs[index].length]
            nextRunByLength[runs[index].length] = index
        }
        var result: [Span] = []
        var index = 0
        while index < runs.count {
            let opening = runs[index]
            guard !isEscaped(opening.location, in: text), let closingIndex = nextMatchingRun[index] else {
                index += 1
                continue
            }
            let closing = runs[closingIndex]
            result.append(Span(kind: .inlineCode, fullRange: NSUnionRange(opening, closing),
                               contentRange: NSRange(location: NSMaxRange(opening), length: closing.location - NSMaxRange(opening)),
                               syntaxRanges: [opening, closing]))
            index = closingIndex + 1
        }
        return result
    }

    private static let patterns: [Pattern] = [
            Pattern(kind: .link, pattern: #"(?<!!)(\[)([^\]\n]+)(\]\((?:[^()\n]|\([^()\n]*\))+\))"#),
            Pattern(kind: .underline, pattern: #"((?:<u>)+)([^<\n]+)((?:</u>)+)"#, options: [.caseInsensitive]),
            Pattern(kind: .strikethrough, pattern: #"(?<!~)((?:~~)+)([^~\n]+)(\1)(?!~)"#),
            Pattern(kind: .bold, pattern: #"(?<!\*)(\*\*\*)([^*\n]+)(\*\*\*)(?!\*)"#),
            Pattern(kind: .italic, pattern: #"(?<!\*)(\*\*\*)([^*\n]+)(\*\*\*)(?!\*)"#),
            Pattern(kind: .bold, pattern: #"(?<!\*)((?:\*\*)+)([^*\n]+)(\1)(?!\*)"#),
            Pattern(kind: .bold, pattern: #"(?<!_)((?:__)+)([^_\n]+)(\1)(?!_)"#),
            Pattern(kind: .italic, pattern: #"(?<!\*)(\*)([^*\n]+)(\*)(?!\*)"#),
            Pattern(kind: .italic, pattern: #"(?<![\p{L}\p{N}_])(_)([^_\n]+)(_)(?![\p{L}\p{N}_])"#)
        ]

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

    private static func isEscaped(_ location: Int, in text: NSString) -> Bool {
        var index = location
        while index > 0, text.character(at: index - 1) == 92 { index -= 1 }
        return !(location - index).isMultiple(of: 2)
    }

    private static func contains(_ outerRange: NSRange, _ innerRange: NSRange) -> Bool {
        innerRange.location >= outerRange.location
            && NSMaxRange(innerRange) <= NSMaxRange(outerRange)
    }
}
