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

    public static func headingLine(in text: String, at location: Int) -> HeadingLine? {
        let nsText = text as NSString
        guard nsText.length > 0 else { return nil }

        let boundedLocation = min(max(0, location), nsText.length)
        guard !isInsideFencedCodeBlock(nsText, location: boundedLocation) else { return nil }

        let lineRange = nsText.lineRange(for: NSRange(location: boundedLocation, length: 0))
        let lineBodyRange = lineBodyRange(from: lineRange, in: nsText)
        let line = nsText.substring(with: lineBodyRange)

        return headingLine(inLine: line, lineBodyRange: lineBodyRange, lineRange: lineRange)
    }

    static func headingLines(in text: String) -> [HeadingLine] {
        let nsText = text as NSString
        guard nsText.length > 0 else { return [] }

        var lines: [HeadingLine] = []
        var location = 0

        while location < nsText.length {
            let lineRange = nsText.lineRange(for: NSRange(location: location, length: 0))
            let lineBodyRange = lineBodyRange(from: lineRange, in: nsText)
            let line = nsText.substring(with: lineBodyRange)

            if !isInsideFencedCodeBlock(nsText, location: lineBodyRange.location),
               let heading = headingLine(inLine: line, lineBodyRange: lineBodyRange, lineRange: lineRange) {
                lines.append(heading)
            }

            let nextLocation = NSMaxRange(lineRange)
            guard nextLocation > location else { break }
            location = nextLocation
        }

        return lines
    }

    public static func horizontalRuleLine(in text: String, at location: Int) -> HorizontalRuleLine? {
        let nsText = text as NSString
        guard nsText.length > 0 else { return nil }

        let boundedLocation = min(max(0, location), nsText.length)
        guard !isInsideFencedCodeBlock(nsText, location: boundedLocation) else { return nil }

        let lineRange = nsText.lineRange(for: NSRange(location: boundedLocation, length: 0))
        let lineBodyRange = lineBodyRange(from: lineRange, in: nsText)
        let line = nsText.substring(with: lineBodyRange)

        return horizontalRuleLine(inLine: line, lineBodyRange: lineBodyRange, lineRange: lineRange)
    }

    public static func horizontalRuleLines(in text: String) -> [HorizontalRuleLine] {
        let nsText = text as NSString
        guard nsText.length > 0 else { return [] }

        var lines: [HorizontalRuleLine] = []
        var location = 0

        while location < nsText.length {
            let lineRange = nsText.lineRange(for: NSRange(location: location, length: 0))
            let lineBodyRange = lineBodyRange(from: lineRange, in: nsText)
            let line = nsText.substring(with: lineBodyRange)

            if !isInsideFencedCodeBlock(nsText, location: lineBodyRange.location),
               let horizontalRule = horizontalRuleLine(inLine: line, lineBodyRange: lineBodyRange, lineRange: lineRange) {
                lines.append(horizontalRule)
            }

            let nextLocation = NSMaxRange(lineRange)
            guard nextLocation > location else { break }
            location = nextLocation
        }

        return lines
    }

    public static func horizontalRuleDisplayState(in text: String, at location: Int) -> HorizontalRuleDisplayState? {
        guard let horizontalRule = horizontalRuleLine(in: text, at: location) else { return nil }
        return horizontalRuleDisplayState(for: horizontalRule)
    }

    public static func horizontalRuleDisplayStates(in text: String) -> [HorizontalRuleDisplayState] {
        horizontalRuleLines(in: text).map(horizontalRuleDisplayState(for:))
    }

    public static func listLine(in text: String, at location: Int) -> ListLine? {
        let nsText = text as NSString
        guard nsText.length > 0 else { return nil }

        let boundedLocation = min(max(0, location), nsText.length)
        guard !isInsideFencedCodeBlock(nsText, location: boundedLocation) else { return nil }

        let lineRange = nsText.lineRange(for: NSRange(location: boundedLocation, length: 0))
        let lineBodyRange = lineBodyRange(from: lineRange, in: nsText)
        let line = nsText.substring(with: lineBodyRange)

        return listLine(inLine: line, lineBodyRange: lineBodyRange, lineRange: lineRange)
    }

    public static func listLines(in text: String) -> [ListLine] {
        let nsText = text as NSString
        guard nsText.length > 0 else { return [] }

        var lines: [ListLine] = []
        var location = 0

        while location < nsText.length {
            let lineRange = nsText.lineRange(for: NSRange(location: location, length: 0))
            let lineBodyRange = lineBodyRange(from: lineRange, in: nsText)
            let line = nsText.substring(with: lineBodyRange)

            if !isInsideFencedCodeBlock(nsText, location: lineBodyRange.location),
               let list = listLine(inLine: line, lineBodyRange: lineBodyRange, lineRange: lineRange) {
                lines.append(list)
            }

            let nextLocation = NSMaxRange(lineRange)
            guard nextLocation > location else { break }
            location = nextLocation
        }

        return lines
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
        guard let regex = try? NSRegularExpression(pattern: #"(?ms)^```.*?^```"#) else { return [] }
        let nsText = text as NSString
        let range = NSRange(location: 0, length: nsText.length)
        return regex.matches(in: text, range: range).map(\.range)
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
        guard location > 0 else { return false }
        let prefix = text.substring(with: NSRange(location: 0, length: min(location, text.length)))
        let matches = fenceRegex.numberOfMatches(
            in: prefix,
            range: NSRange(location: 0, length: (prefix as NSString).length)
        )
        return !matches.isMultiple(of: 2)
    }

    private static let headingRegex = try! NSRegularExpression(pattern: #"^(#{1,6})([ \t]+)(.*)$"#)
    private static let horizontalRuleRegex = try! NSRegularExpression(pattern: #"^[ \t]{0,3}([-*_])(?:[ \t]*\1){2,}[ \t]*$"#)
    private static let listLineRegex = try! NSRegularExpression(pattern: #"^([ \t]*(?:\d+\.|[-*+])(?:[ \t]+\[[ xX]\])?[ \t]+)(.*)$"#)
    private static let fenceRegex = try! NSRegularExpression(pattern: #"(?m)^```"#)

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
            return NSRange(location: lineRange.location, length: lineRange.length - 1)
        }
        return lineRange
    }

    private static func absoluteRange(_ range: NSRange, offset: Int) -> NSRange {
        guard range.location != NSNotFound else { return range }
        return NSRange(location: range.location + offset, length: range.length)
    }

}
