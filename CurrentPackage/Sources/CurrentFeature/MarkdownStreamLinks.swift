import Foundation

public struct MarkdownStreamLinkTarget: Equatable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var qualifiedName: String?
    public var linkName: String { qualifiedName ?? name }
    public var insertionText: String { "[[\(linkName)]]" }

    public init(id: UUID, name: String, qualifiedName: String? = nil) {
        self.id = id
        self.name = name
        self.qualifiedName = qualifiedName
    }
}

public enum MarkdownStreamLinks {
    public struct Link: Equatable, Sendable {
        public var sourceRange: NSRange
        public var labelRange: NSRange
        public var target: MarkdownStreamLinkTarget
    }

    public struct Completion: Equatable, Sendable {
        public var replacementRange: NSRange
        public var query: String
        public var matches: [MarkdownStreamLinkTarget]
    }

    public static func resolve(_ label: String, targets: [MarkdownStreamLinkTarget]) -> MarkdownStreamLinkTarget? {
        let label = label.trimmingCharacters(in: .whitespaces)
        let matches = targets.filter { equal($0.name, label) || $0.qualifiedName.map { equal($0, label) } == true }
        return Set(matches.map(\.id)).count == 1 ? matches.first : nil
    }

    public static func resolvedLinks(in text: String, targets: [MarkdownStreamLinkTarget],
                                     protectedRanges: [NSRange]? = nil) -> [Link] {
        let source = text as NSString
        let protected = protectedRanges ?? Self.protectedRanges(in: text)
        return closed.matches(in: text, range: NSRange(location: 0, length: source.length)).compactMap { match in
            guard !escaped(match.range.location, source: source),
                  !protected.contains(where: { NSIntersectionRange($0, match.range).length > 0 }),
                  let target = resolve(source.substring(with: match.range(at: 1)), targets: targets) else { return nil }
            return Link(sourceRange: match.range, labelRange: match.range(at: 1), target: target)
        }
    }

    public static func completion(in text: String, selection: NSRange,
                                  targets: [MarkdownStreamLinkTarget], protectedRanges: [NSRange]? = nil) -> Completion? {
        let source = text as NSString
        guard selection.length == 0, selection.location >= 0, selection.location <= source.length else { return nil }
        let line = source.lineRange(for: NSRange(location: selection.location, length: 0))
        let prefix = NSRange(location: line.location, length: selection.location - line.location)
        let opening = source.range(of: "[[", options: .backwards, range: prefix)
        guard opening.location != NSNotFound, !escaped(opening.location, source: source),
              opening.location == 0 || source.character(at: opening.location - 1) != 91 else { return nil }
        let queryRange = NSRange(location: NSMaxRange(opening), length: selection.location - NSMaxRange(opening))
        let query = source.substring(with: queryRange)
        guard !query.contains(where: { "[]\r\n".contains($0) }) else { return nil }
        let edited = NSRange(location: opening.location, length: selection.location - opening.location)
        guard !(protectedRanges ?? Self.protectedRanges(in: text)).contains(where: { NSIntersectionRange($0, edited).length > 0 }) else { return nil }
        let remainder = NSRange(location: selection.location, length: NSMaxRange(line) - selection.location)
        let closing = source.range(of: "]]", range: remainder)
        var end = selection.location
        if closing.location != NSNotFound {
            let tail = source.substring(with: NSRange(location: selection.location, length: closing.location - selection.location))
            guard !tail.contains(where: { "[]\r\n".contains($0) }),
                  NSMaxRange(closing) == source.length || source.character(at: NSMaxRange(closing)) != 93 else { return nil }
            end = NSMaxRange(closing)
        }
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        let matches = targets.filter {
            !$0.linkName.contains(where: { "[]\r\n".contains($0) })
                && resolve($0.linkName, targets: targets)?.id == $0.id
                && (trimmed.isEmpty || $0.name.localizedStandardContains(trimmed) || $0.linkName.localizedStandardContains(trimmed))
        }.sorted { $0.linkName.localizedStandardCompare($1.linkName) == .orderedAscending }
        return Completion(replacementRange: NSRange(location: opening.location, length: end - opening.location),
                          query: query, matches: matches)
    }

    private static func protectedRanges(in text: String) -> [NSRange] {
        let fences = MarkdownBlockRendering.parse(in: text).fences.map(\.range)
        return fences + MarkdownInlineRendering.spans(in: text, protectedRanges: fences)
            .filter { $0.kind == .inlineCode }.map(\.fullRange)
    }

    private static func escaped(_ location: Int, source: NSString) -> Bool {
        var index = location
        while index > 0, source.character(at: index - 1) == 92 { index -= 1 }
        return !(location - index).isMultiple(of: 2)
    }

    private static func equal(_ lhs: String, _ rhs: String) -> Bool {
        lhs.compare(rhs, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
    }

    private static let closed = try! NSRegularExpression(pattern: #"(?<!\[)\[\[([^\[\]\r\n]+)\]\](?!\])"#)
}
