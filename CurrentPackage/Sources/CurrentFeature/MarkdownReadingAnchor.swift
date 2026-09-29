import AppKit

/// A position in the source, with enough neighboring text to survive nearby
/// edits. The offset is measured from the visual line, not the entire day row.
public struct MarkdownReadingAnchor: Codable, Equatable, Sendable {
    public var sourceLocation: Int
    public var context: String
    public var contextPrefixLength: Int
    public var lineOffset: Double

    public init(sourceLocation: Int, context: String = "", contextPrefixLength: Int = 0,
                lineOffset: Double = 0) {
        self.sourceLocation = sourceLocation
        self.context = context
        self.contextPrefixLength = contextPrefixLength
        self.lineOffset = lineOffset.isFinite ? lineOffset : 0
    }

    public static func captureSource(in text: String, at location: Int, lineOffset: Double = 0) -> Self {
        let source = text as NSString
        let location = composedBoundary(location, in: source)
        guard source.length > 0 else { return Self(sourceLocation: 0, lineOffset: lineOffset) }
        let start = max(0, min(location - 24, source.length - 64))
        let range = source.rangeOfComposedCharacterSequences(for:
            NSRange(location: start, length: min(64, source.length - start)))
        return Self(sourceLocation: location, context: source.substring(with: range),
                    contextPrefixLength: location - range.location, lineOffset: lineOffset)
    }

    public func resolvedSourceLocation(in text: String) -> Int {
        let source = text as NSString
        let fallback = Self.composedBoundary(sourceLocation, in: source)
        let saved = context as NSString
        let prefix = min(max(0, contextPrefixLength), saved.length)
        guard saved.length > 0 else { return fallback }

        if let start = Self.closestOccurrence(of: context, in: source, near: max(0, fallback - prefix)) {
            return Self.composedBoundary(start + prefix, in: source)
        }
        // An edit immediately before the reading edge may alter the prefix;
        // retain the following source text when there is enough to identify it.
        let suffixRange = saved.rangeOfComposedCharacterSequences(for:
            NSRange(location: prefix, length: min(32, saved.length - prefix)))
        if suffixRange.length >= 8,
           let start = Self.closestOccurrence(of: saved.substring(with: suffixRange), in: source, near: fallback) {
            return Self.composedBoundary(start + prefix - suffixRange.location, in: source)
        }
        let prefixRange = saved.rangeOfComposedCharacterSequences(for:
            NSRange(location: max(0, prefix - 32), length: min(32, prefix)))
        if prefixRange.length >= 8,
           let start = Self.closestOccurrence(of: saved.substring(with: prefixRange), in: source,
                                             near: max(0, fallback - prefixRange.length)) {
            return Self.composedBoundary(start + prefix - prefixRange.location, in: source)
        }
        return fallback
    }

    private static func composedBoundary(_ location: Int, in source: NSString) -> Int {
        let bounded = min(max(0, location), source.length)
        return bounded < source.length ? source.rangeOfComposedCharacterSequence(at: bounded).location : bounded
    }

    private static func closestOccurrence(of needle: String, in source: NSString, near location: Int) -> Int? {
        let length = (needle as NSString).length
        guard length > 0, length <= source.length else { return nil }
        let expected = min(max(0, location), source.length - length)
        if source.substring(with: NSRange(location: expected, length: length)) == needle { return expected }
        var best: Int?
        var start = 0
        while start <= source.length - length {
            let found = source.range(of: needle, options: .literal,
                                     range: NSRange(location: start, length: source.length - start))
            guard found.location != NSNotFound else { break }
            if best == nil || abs(found.location - location) < abs(best! - location) { best = found.location }
            if found.location >= location { break }
            start = found.location + 1
        }
        return best
    }
}

extension MarkdownReadingAnchor {
    /// Requires completed native layout. Call after measurement, never from a
    /// collection layout's prepare() or a text storage editing transaction.
    @MainActor
    static func capture(in textView: MarkdownTextView, readingY: CGFloat) -> Self? {
        guard readingY.isFinite, let geometry = laidOutGeometry(in: textView) else { return nil }
        let (manager, container, source) = geometry
        let origin = textView.textContainerOrigin
        guard readingY >= origin.y else { return nil } // The date header is above the text.
        let extra = manager.extraLineFragmentRect
        if manager.extraLineFragmentTextContainer === container, extra.height > 0,
           readingY >= origin.y + extra.minY {
            return captureSource(in: source as String, at: source.length,
                                 lineOffset: Double(readingY - origin.y - extra.minY))
        }
        guard source.length > 0, manager.numberOfGlyphs > 0 else { return nil }
        let point = NSPoint(x: 0, y: max(0, readingY - origin.y))
        let glyph = manager.glyphIndex(for: point, in: container)
        guard glyph < manager.firstUnlaidGlyphIndex() else { return nil }
        var range = NSRange()
        let line = manager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: &range, withoutAdditionalLayout: true)
        guard line.height > 0, range.location != NSNotFound else { return nil }
        let location = manager.characterIndexForGlyph(at: range.location)
        return captureSource(in: source as String, at: location,
                             lineOffset: Double(readingY - origin.y - line.minY))
    }

    /// Returns text-view coordinates without changing selection, focus, or layout.
    @MainActor
    func lineOrigin(in textView: MarkdownTextView) -> NSPoint? {
        guard let (manager, container, source) = Self.laidOutGeometry(in: textView) else { return nil }
        let location = resolvedSourceLocation(in: source as String)
        let origin = textView.textContainerOrigin
        if location == source.length, manager.extraLineFragmentTextContainer === container,
           manager.extraLineFragmentRect.height > 0 {
            let extra = manager.extraLineFragmentRect
            return NSPoint(x: origin.x + extra.minX, y: origin.y + extra.minY)
        }
        guard source.length > 0 else { return nil }
        let glyph = manager.glyphIndexForCharacter(at: min(location, source.length - 1))
        guard glyph < manager.firstUnlaidGlyphIndex() else { return nil }
        let line = manager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil, withoutAdditionalLayout: true)
        guard line.height > 0 else { return nil }
        return NSPoint(x: origin.x + line.minX, y: origin.y + line.minY)
    }

    @MainActor
    private static func laidOutGeometry(in textView: MarkdownTextView) -> (NSLayoutManager, NSTextContainer, NSString)? {
        guard !textView.hasMarkedText(),
              let storage = textView.textStorage as? MarkdownTextStorage,
              !storage.isProcessingEdit, !storage.suspendsDecorations,
              let manager = textView.layoutManager, let container = textView.textContainer,
              container.containerSize.width > 0,
              manager.firstUnlaidCharacterIndex() >= storage.length else { return nil }
        return (manager, container, storage.string as NSString)
    }
}
