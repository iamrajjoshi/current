import Foundation

public enum MarkdownBlockRendering {
    public struct HeadingLine: Equatable {
        public var level: Int
        public var lineRange: NSRange
        public var markerRange: NSRange
        public var prefixRange: NSRange
        public var contentRange: NSRange

        public var hasContent: Bool {
            contentRange.length > 0
        }
    }

    public struct HorizontalRuleLine: Equatable {
        public var lineRange: NSRange
        public var markerRange: NSRange
    }

    public enum HorizontalRuleDisplayState: Equatable {
        case editingMarker(HorizontalRuleLine)
        case committedDivider(HorizontalRuleLine)

        public var horizontalRule: HorizontalRuleLine {
            switch self {
            case .editingMarker(let horizontalRule), .committedDivider(let horizontalRule):
                return horizontalRule
            }
        }
    }

    public struct ListLine: Equatable {
        public var lineRange: NSRange
        public var prefixRange: NSRange
        public var contentRange: NSRange
    }

    struct Parsed {
        var headings: [HeadingLine] = []
        var lists: [ListLine] = []
        var horizontalRules: [HorizontalRuleDisplayState] = []
        var fences: [CodeFence] = []
        var quotes: [QuoteLine] = []
    }

    struct CodeFence: Equatable {
        var range: NSRange
        var openingRange: NSRange
        var closingRange: NSRange?
        var contentRange: NSRange
    }

    struct QuoteLine: Equatable {
        var lineRange: NSRange
        var prefixRange: NSRange
    }

    /// Walk source lines once. The fence state is shared by every block kind,
    /// including unfinished fences while a user is still typing.
    static func parse(in text: String) -> Parsed {
        let source = text as NSString
        var result = Parsed()
        var open: (start: Int, marker: UInt16, count: Int, opening: NSRange)?
        var location = 0
        while location < source.length {
            let lineRange = source.lineRange(for: NSRange(location: location, length: 0))
            let bodyRange = lineBodyRange(from: lineRange, in: source)
            let line = source.substring(with: bodyRange)
            if let active = open {
                if let candidate = fenceMarker(in: line), candidate.marker == active.marker,
                   candidate.count >= active.count, candidate.suffix.trimmingCharacters(in: .whitespaces).isEmpty {
                    result.fences.append(CodeFence(
                        range: NSRange(location: active.start, length: NSMaxRange(lineRange) - active.start),
                        openingRange: active.opening,
                        closingRange: lineRange,
                        contentRange: NSRange(location: NSMaxRange(active.opening), length: max(0, bodyRange.location - NSMaxRange(active.opening)))
                    ))
                    open = nil
                }
            } else if let marker = fenceMarker(in: line),
                      marker.marker != 96 || !marker.suffix.contains("`") {
                open = (lineRange.location, marker.marker, marker.count, lineRange)
            } else {
                if let heading = headingLine(inLine: line, lineBodyRange: bodyRange, lineRange: lineRange) {
                    result.headings.append(heading)
                } else if let rule = horizontalRuleLine(inLine: line, lineBodyRange: bodyRange, lineRange: lineRange) {
                    result.horizontalRules.append(horizontalRuleDisplayState(for: rule))
                } else if let list = listLine(inLine: line, lineBodyRange: bodyRange, lineRange: lineRange) {
                    result.lists.append(list)
                }
                if let match = quoteRegex.firstMatch(in: line, range: NSRange(location: 0, length: (line as NSString).length)) {
                    result.quotes.append(QuoteLine(lineRange: lineRange, prefixRange: absoluteRange(match.range(at: 1), offset: location)))
                }
            }
            location = NSMaxRange(lineRange)
        }
        if let active = open {
            result.fences.append(CodeFence(
                range: NSRange(location: active.start, length: source.length - active.start),
                openingRange: active.opening,
                closingRange: nil,
                contentRange: NSRange(location: NSMaxRange(active.opening), length: source.length - NSMaxRange(active.opening))
            ))
        }
        return result
    }

    private static func fenceMarker(in line: String) -> (marker: UInt16, count: Int, suffix: String)? {
        let line = line as NSString
        var index = 0
        while index < line.length, line.character(at: index) == 32 { index += 1 }
        guard index <= 3, index < line.length else { return nil }
        let marker = line.character(at: index)
        guard marker == 96 || marker == 126 else { return nil }
        let start = index
        while index < line.length, line.character(at: index) == marker { index += 1 }
        guard index - start >= 3 else { return nil }
        return (marker, index - start, line.substring(from: index))
    }

    public static func headingLine(in text: String, at location: Int) -> HeadingLine? {
        parse(in: text).headings.first { contains($0.lineRange, location: location, length: (text as NSString).length) }
    }

    static func headingLines(in text: String) -> [HeadingLine] { parse(in: text).headings }

    public static func horizontalRuleLine(in text: String, at location: Int) -> HorizontalRuleLine? {
        parse(in: text).horizontalRules.first { contains($0.horizontalRule.lineRange, location: location, length: (text as NSString).length) }?.horizontalRule
    }

    public static func horizontalRuleLines(in text: String) -> [HorizontalRuleLine] {
        parse(in: text).horizontalRules.map(\.horizontalRule)
    }

    public static func horizontalRuleDisplayState(in text: String, at location: Int) -> HorizontalRuleDisplayState? {
        parse(in: text).horizontalRules.first { contains($0.horizontalRule.lineRange, location: location, length: (text as NSString).length) }
    }

    public static func horizontalRuleDisplayStates(in text: String) -> [HorizontalRuleDisplayState] { parse(in: text).horizontalRules }

    public static func listLine(in text: String, at location: Int) -> ListLine? {
        parse(in: text).lists.first { contains($0.lineRange, location: location, length: (text as NSString).length) }
    }

    public static func listLines(in text: String) -> [ListLine] { parse(in: text).lists }

    private static func contains(_ range: NSRange, location: Int, length: Int) -> Bool {
        NSLocationInRange(location, range) || (location == length && NSMaxRange(range) == length)
    }

    public static func hasRenderedContent(in text: String) -> Bool {
        let nsText = text as NSString
        guard nsText.length > 0 else { return false }

        var location = 0
        while location < nsText.length {
            let lineRange = nsText.lineRange(for: NSRange(location: location, length: 0))
            let lineBodyRange = lineBodyRange(from: lineRange, in: nsText)
            let line = nsText.substring(with: lineBodyRange)
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)

            if !trimmedLine.isEmpty {
                if isInsideFencedCodeBlock(nsText, location: lineBodyRange.location) {
                    return true
                }

                if horizontalRuleLine(inLine: line, lineBodyRange: lineBodyRange, lineRange: lineRange) != nil {
                    return true
                }

                if let heading = headingLine(inLine: line, lineBodyRange: lineBodyRange, lineRange: lineRange) {
                    let content = nsText.substring(with: heading.contentRange)
                    if !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        return true
                    }
                } else {
                    return true
                }
            }

            let nextLocation = NSMaxRange(lineRange)
            guard nextLocation > location else { break }
            location = nextLocation
        }

        return false
    }

    public static func fencedCodeBlockRanges(in text: String) -> [NSRange] {
        parse(in: text).fences.map(\.range)
    }

    static func headingLine(inLine line: String, lineBodyRange: NSRange, lineRange: NSRange) -> HeadingLine? {
        let nsLine = line as NSString
        let range = NSRange(location: 0, length: nsLine.length)
        guard let match = headingRegex.firstMatch(in: line, range: range) else { return nil }

        let markerRange = absoluteRange(match.range(at: 1), offset: lineBodyRange.location)
        let whitespaceRange = absoluteRange(match.range(at: 2), offset: lineBodyRange.location)
        let contentRange = absoluteRange(match.range(at: 3), offset: lineBodyRange.location)
        return HeadingLine(
            level: markerRange.length,
            lineRange: lineRange,
            markerRange: markerRange,
            prefixRange: NSRange(location: markerRange.location, length: markerRange.length + whitespaceRange.length),
            contentRange: contentRange
        )
    }

    static func isInsideFencedCodeBlock(_ text: NSString, location: Int) -> Bool {
        parse(in: text as String).fences.contains {
            NSLocationInRange(location, $0.range) || ($0.closingRange == nil && location == text.length)
        }
    }

    private static let headingRegex = try! NSRegularExpression(pattern: #"^(#{1,6})([ \t]+)(.*)$"#)
    private static let horizontalRuleRegex = try! NSRegularExpression(pattern: #"^[ \t]{0,3}([-*_])(?:[ \t]*\1){2,}[ \t]*$"#)
    private static let listLineRegex = try! NSRegularExpression(pattern: #"^([ \t]*(?:\d+\.|[-*+])(?:[ \t]+\[[ xX]\])?[ \t]+)(.*)$"#)
    private static let quoteRegex = try! NSRegularExpression(pattern: #"^([ \t]{0,3}(?:>[ \t]?)+)"#)

    private static func horizontalRuleLine(inLine line: String, lineBodyRange: NSRange, lineRange: NSRange) -> HorizontalRuleLine? {
        let nsLine = line as NSString
        let range = NSRange(location: 0, length: nsLine.length)
        guard horizontalRuleRegex.firstMatch(in: line, range: range) != nil else { return nil }

        return HorizontalRuleLine(
            lineRange: lineRange,
            markerRange: lineBodyRange
        )
    }

    private static func horizontalRuleDisplayState(for horizontalRule: HorizontalRuleLine) -> HorizontalRuleDisplayState {
        if horizontalRule.lineRange.length > horizontalRule.markerRange.length {
            return .committedDivider(horizontalRule)
        }
        return .editingMarker(horizontalRule)
    }

    private static func listLine(inLine line: String, lineBodyRange: NSRange, lineRange: NSRange) -> ListLine? {
        let nsLine = line as NSString
        let range = NSRange(location: 0, length: nsLine.length)
        guard let match = listLineRegex.firstMatch(in: line, range: range) else { return nil }

        let prefixRange = absoluteRange(match.range(at: 1), offset: lineBodyRange.location)
        let contentRange = absoluteRange(match.range(at: 2), offset: lineBodyRange.location)
        guard prefixRange.location != NSNotFound,
              contentRange.location != NSNotFound else {
            return nil
        }

        return ListLine(
            lineRange: lineRange,
            prefixRange: prefixRange,
            contentRange: contentRange
        )
    }

    private static func lineBodyRange(from lineRange: NSRange, in text: NSString) -> NSRange {
        guard lineRange.length > 0 else { return lineRange }
        let lastLocation = lineRange.location + lineRange.length - 1
        let lastCharacter = text.substring(with: NSRange(location: lastLocation, length: 1))
        if lastCharacter == "\n" {
            let count = lineRange.length > 1 && text.character(at: lastLocation - 1) == 13 ? 2 : 1
            return NSRange(location: lineRange.location, length: lineRange.length - count)
        }
        if lastCharacter == "\r" { return NSRange(location: lineRange.location, length: lineRange.length - 1) }
        return lineRange
    }

    private static func absoluteRange(_ range: NSRange, offset: Int) -> NSRange {
        guard range.location != NSNotFound else { return range }
        return NSRange(location: range.location + offset, length: range.length)
    }

}
