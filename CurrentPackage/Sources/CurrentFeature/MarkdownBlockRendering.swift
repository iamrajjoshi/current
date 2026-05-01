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
    private static let fenceRegex = try! NSRegularExpression(pattern: #"(?m)^```"#)

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
