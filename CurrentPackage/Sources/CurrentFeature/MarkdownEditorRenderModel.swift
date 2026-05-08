import Foundation

enum MarkdownInlineMark: Hashable, Sendable {
    case bold
    case italic
    case underline
    case strikethrough
    case inlineCode
}

enum MarkdownBlockNode: Equatable {
    case heading(MarkdownBlockRendering.HeadingLine)
    case list(MarkdownBlockRendering.ListLine)
    case horizontalRule(MarkdownBlockRendering.HorizontalRuleDisplayState)
    case fencedCodeBlock(NSRange)

    var lineRange: NSRange {
        switch self {
        case .heading(let heading):
            return heading.lineRange
        case .list(let list):
            return list.lineRange
        case .horizontalRule(let state):
            return state.horizontalRule.lineRange
        case .fencedCodeBlock(let range):
            return range
        }
    }
}

enum MarkdownLiveBlockKind: Equatable {
    case paragraph
    case heading
    case list
    case horizontalRule
    case fencedCodeBlock
}

struct MarkdownLiveBlock: Equatable {
    var kind: MarkdownLiveBlockKind
    var lineRange: NSRange
    var visibleContentRange: NSRange
    var hideableSyntaxRanges: [NSRange]
}

struct MarkdownVisibleRange: Equatable {
    var rawRange: NSRange
}

struct MarkdownEditorRenderModel {
    var text: String
    var protectedRanges: [NSRange]
    var headings: [MarkdownBlockRendering.HeadingLine]
    var lists: [MarkdownBlockRendering.ListLine]
    var horizontalRules: [MarkdownBlockRendering.HorizontalRuleDisplayState]
    var inlineSpans: [MarkdownInlineRendering.Span]

    init(text: String) {
        self.text = text
        self.protectedRanges = MarkdownBlockRendering.fencedCodeBlockRanges(in: text)
        self.headings = MarkdownBlockRendering.headingLines(in: text)
        self.lists = MarkdownBlockRendering.listLines(in: text)
        self.horizontalRules = MarkdownBlockRendering.horizontalRuleDisplayStates(in: text)
        self.inlineSpans = MarkdownInlineRendering.spans(in: text, protectedRanges: protectedRanges)
    }

    var blockNodes: [MarkdownBlockNode] {
        (
            protectedRanges.map(MarkdownBlockNode.fencedCodeBlock)
            + headings.map(MarkdownBlockNode.heading)
            + lists.map(MarkdownBlockNode.list)
            + horizontalRules.map(MarkdownBlockNode.horizontalRule)
        ).sorted { lhs, rhs in
            if lhs.lineRange.location == rhs.lineRange.location {
                return lhs.lineRange.length > rhs.lineRange.length
            }
            return lhs.lineRange.location < rhs.lineRange.location
        }
    }

    var hiddenSyntaxRanges: [NSRange] {
        let headingPrefixes = headings.map(\.prefixRange)
        let inlineSyntax = inlineSpans.flatMap(\.syntaxRanges)
        return headingPrefixes + inlineSyntax
    }

    var visibleContentRanges: [MarkdownVisibleRange] {
        let nsText = text as NSString
        guard nsText.length > 0 else { return [] }

        var ranges: [MarkdownVisibleRange] = []
        var location = 0
        while location < nsText.length {
            let lineRange = nsText.lineRange(for: NSRange(location: location, length: 0))
            let lineBodyRange = Self.lineBodyRange(from: lineRange, in: nsText)
            if let contentRange = structuralContentRange(at: lineBodyRange.location) {
                ranges.append(MarkdownVisibleRange(rawRange: contentRange))
            } else {
                ranges.append(MarkdownVisibleRange(rawRange: lineBodyRange))
            }

            let next = NSMaxRange(lineRange)
            guard next > location else { break }
            location = next
        }
        return ranges
    }

    func heading(at location: Int) -> MarkdownBlockRendering.HeadingLine? {
        headings.first { containsOrTouches($0.lineRange, location: location) }
    }

    func list(at location: Int) -> MarkdownBlockRendering.ListLine? {
        lists.first { containsOrTouches($0.lineRange, location: location) }
    }

    func horizontalRule(at location: Int) -> MarkdownBlockRendering.HorizontalRuleDisplayState? {
        horizontalRules.first { containsOrTouches($0.horizontalRule.lineRange, location: location) }
    }

    func structuralContentRange(at location: Int) -> NSRange? {
        if let list = list(at: location) {
            return list.contentRange
        }
        if let heading = heading(at: location) {
            return heading.contentRange
        }
        return nil
    }

    func liveBlock(at location: Int) -> MarkdownLiveBlock? {
        let nsText = text as NSString
        guard location >= 0, location <= nsText.length else { return nil }
        let lineRange = Self.caretLineRange(at: location, in: nsText)

        if let fencedRange = protectedRanges.first(where: { NSIntersectionRange($0, lineRange).length > 0 }) {
            return MarkdownLiveBlock(
                kind: .fencedCodeBlock,
                lineRange: fencedRange,
                visibleContentRange: fencedRange,
                hideableSyntaxRanges: []
            )
        }

        if let heading = headings.first(where: { $0.lineRange.location == lineRange.location }) {
            return MarkdownLiveBlock(
                kind: .heading,
                lineRange: heading.lineRange,
                visibleContentRange: heading.contentRange,
                hideableSyntaxRanges: [heading.prefixRange] + inlineSyntaxRanges(intersecting: heading.lineRange)
            )
        }

        if let list = lists.first(where: { $0.lineRange.location == lineRange.location }) {
            return MarkdownLiveBlock(
                kind: .list,
                lineRange: list.lineRange,
                visibleContentRange: list.contentRange,
                hideableSyntaxRanges: inlineSyntaxRanges(intersecting: list.lineRange)
            )
        }

        if let horizontalRule = horizontalRules.first(where: { $0.horizontalRule.lineRange.location == lineRange.location }) {
            return MarkdownLiveBlock(
                kind: .horizontalRule,
                lineRange: horizontalRule.horizontalRule.lineRange,
                visibleContentRange: horizontalRule.horizontalRule.markerRange,
                hideableSyntaxRanges: [horizontalRule.horizontalRule.markerRange]
            )
        }

        guard nsText.length > 0 else { return nil }
        return MarkdownLiveBlock(
            kind: .paragraph,
            lineRange: lineRange,
            visibleContentRange: Self.lineBodyRange(from: lineRange, in: nsText),
            hideableSyntaxRanges: inlineSyntaxRanges(intersecting: lineRange)
        )
    }

    func liveBlocks(intersecting selectedRange: NSRange?) -> [MarkdownLiveBlock] {
        guard let selectedRange else { return [] }
        let nsText = text as NSString
        guard isValid(selectedRange, in: nsText), nsText.length > 0 else { return [] }

        if selectedRange.length == 0 {
            return liveBlock(at: selectedRange.location).map { [$0] } ?? []
        }

        var blocks: [MarkdownLiveBlock] = []
        var seenLineLocations = Set<Int>()
        let endLocation = max(selectedRange.location, NSMaxRange(selectedRange) - 1)
        var location = selectedRange.location
        while location <= endLocation {
            guard let block = liveBlock(at: location) else { break }
            if seenLineLocations.insert(block.lineRange.location).inserted {
                blocks.append(block)
            }
            let nextLocation = NSMaxRange(block.lineRange)
            guard nextLocation > location else { break }
            location = nextLocation
        }
        return blocks
    }

    func normalizedVisibleSelection(_ selectedRange: NSRange) -> NSRange {
        let nsText = text as NSString
        guard isValid(selectedRange, in: nsText) else { return selectedRange }

        if selectedRange.length == 0 {
            return selectedRange
        }

        let startLine = nsText.lineRange(for: NSRange(location: selectedRange.location, length: 0))
        let endLocation = max(selectedRange.location, NSMaxRange(selectedRange) - 1)
        let endLine = nsText.lineRange(for: NSRange(location: min(endLocation, max(0, nsText.length - 1)), length: 0))
        guard startLine == endLine else { return selectedRange }

        guard let contentRange = structuralContentRange(at: selectedRange.location) else {
            return selectedRange
        }

        let selectedEnd = NSMaxRange(selectedRange)
        guard selectedRange.location < contentRange.location,
              selectedEnd > contentRange.location else {
            return selectedRange
        }

        let normalizedEnd = min(selectedEnd, NSMaxRange(contentRange))
        guard normalizedEnd >= contentRange.location else { return selectedRange }
        return NSRange(location: contentRange.location, length: normalizedEnd - contentRange.location)
    }

    func visibleInsertionLocation(for location: Int) -> Int {
        return location
    }

    func inlineMarks(at location: Int) -> Set<MarkdownInlineMark> {
        let activeSpans = inlineSpans.filter { span in
            location >= span.contentRange.location && location <= NSMaxRange(span.contentRange)
        }
        if activeSpans.contains(where: { $0.kind == .inlineCode }) {
            return [.inlineCode]
        }

        return Set(activeSpans.compactMap(Self.inlineMark(for:)))
    }

    func inlineSpan(at location: Int) -> MarkdownInlineRendering.Span? {
        inlineSpans.first { span in
            location >= span.fullRange.location && location <= NSMaxRange(span.fullRange)
        }
    }

    func hiddenSyntaxRange(containingOrTouching location: Int) -> NSRange? {
        hiddenSyntaxRanges.first { range in
            location >= range.location && location <= NSMaxRange(range)
        }
    }

    static func decorationRange(around range: NSRange, in text: String) -> NSRange {
        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)
        guard fullRange.length > 0 else { return fullRange }

        var clampedLocation = min(max(0, range.location), nsText.length)
        var clampedLength = min(max(0, range.length), nsText.length - clampedLocation)
        if clampedLength == 0 {
            if clampedLocation == nsText.length, clampedLocation > 0 {
                clampedLocation -= 1
            }
            clampedLength = 1
        }

        let editedLineRange = nsText.lineRange(for: NSRange(location: clampedLocation, length: clampedLength))
        var expandedRange = editedLineRange

        if expandedRange.location > 0 {
            let previousLineRange = nsText.lineRange(for: NSRange(location: expandedRange.location - 1, length: 0))
            expandedRange = NSUnionRange(expandedRange, previousLineRange)
        }

        let nextLocation = NSMaxRange(expandedRange)
        if nextLocation < nsText.length {
            let nextLineRange = nsText.lineRange(for: NSRange(location: nextLocation, length: 0))
            expandedRange = NSUnionRange(expandedRange, nextLineRange)
        }

        for fencedRange in MarkdownBlockRendering.fencedCodeBlockRanges(in: text)
            where NSIntersectionRange(fencedRange, expandedRange).length > 0 {
            expandedRange = NSUnionRange(expandedRange, fencedRange)
        }

        return NSIntersectionRange(expandedRange, fullRange)
    }

    private static func inlineMark(for span: MarkdownInlineRendering.Span) -> MarkdownInlineMark? {
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
    }

    private func inlineSyntaxRanges(intersecting range: NSRange) -> [NSRange] {
        inlineSpans
            .filter { NSIntersectionRange($0.fullRange, range).length > 0 }
            .flatMap(\.syntaxRanges)
    }

    private func containsOrTouches(_ range: NSRange, location: Int) -> Bool {
        if location == NSMaxRange(range) {
            return location == (text as NSString).length
        }
        return location >= range.location && location < NSMaxRange(range)
    }

    private func isValid(_ range: NSRange, in text: NSString) -> Bool {
        range.location >= 0 && range.length >= 0 && NSMaxRange(range) <= text.length
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

    private static func caretLineRange(at location: Int, in text: NSString) -> NSRange {
        let boundedLocation = min(max(0, location), text.length)
        if boundedLocation == text.length, text.length > 0 {
            let previousCharacter = text.substring(with: NSRange(location: text.length - 1, length: 1))
            if previousCharacter == "\n" {
                return NSRange(location: text.length, length: 0)
            }
            return text.lineRange(for: NSRange(location: text.length - 1, length: 0))
        }
        return text.lineRange(for: NSRange(location: boundedLocation, length: 0))
    }
}
