import Foundation

/// Search presentation keeps a source offset for each visible UTF-16 unit, so
/// syntax removal and whitespace normalization never change the editor target.
enum MarkdownSearchExcerpt {
    struct Excerpt {
        var text: String
        var matchRange: NSRange
    }

    static func make(source: String, matchRange: NSRange) -> Excerpt {
        let (plain, sourceOffsets) = visibleText(source: source, preserving: matchRange)
        guard let first = sourceOffsets.firstIndex(where: { NSLocationInRange($0, matchRange) }),
              let last = sourceOffsets.lastIndex(where: { NSLocationInRange($0, matchRange) }) else {
            return Excerpt(text: (source as NSString).substring(with: matchRange),
                           matchRange: NSRange(location: 0, length: matchRange.length))
        }
        let lower = max(0, first - 65)
        let upper = min(plain.length, last + 1 + 115)
        let context = plain.rangeOfComposedCharacterSequences(for: NSRange(location: lower, length: upper - lower))
        let prefix = context.location > 0 ? "… " : ""
        let suffix = NSMaxRange(context) < plain.length ? " …" : ""
        return Excerpt(text: prefix + plain.substring(with: context) + suffix,
                       matchRange: NSRange(location: prefix.utf16.count + first - context.location,
                                           length: last - first + 1))
    }

    static func preview(source: String, limit: Int = 120) -> String {
        guard limit > 0 else { return "" }
        // A collapsed row only needs the opening context, including enough
        // source to close common inline constructs without parsing a huge day.
        let end = source.index(source.startIndex, offsetBy: max(2_048, limit * 4), limitedBy: source.endIndex) ?? source.endIndex
        let prefix = String(source[..<end])
        let (plain, _) = visibleText(source: prefix, preserving: nil)
        guard plain.length > 0 else { return "" }
        let range = plain.rangeOfComposedCharacterSequences(for: NSRange(location: 0, length: min(limit, plain.length)))
        return plain.substring(with: range) + (NSMaxRange(range) < plain.length || end != source.endIndex ? "…" : "")
    }

    private static func visibleText(source: String, preserving matchRange: NSRange?) -> (NSString, [Int]) {
        let model = MarkdownEditorRenderModel(text: source)
        let original = source as NSString
        var hidden = IndexSet()
        var separators = IndexSet()
        func hide(_ range: NSRange) {
            guard range.location != NSNotFound, range.length > 0,
                  NSMaxRange(range) <= original.length else { return }
            hidden.insert(integersIn: range.location..<NSMaxRange(range))
        }
        for range in model.hiddenSyntaxRanges + model.lists.map(\.prefixRange) + model.quotes.map(\.prefixRange) {
            hide(range)
        }
        for fence in model.fences {
            hide(fence.openingRange)
            if let closing = fence.closingRange { hide(closing) }
        }
        for rule in model.horizontalRules { hide(rule.horizontalRule.markerRange) }
        for block in model.richBlocks {
            switch block.kind {
            case .image:
                if let match = image.firstMatch(in: source, range: block.range) {
                    hide(match.range(at: 1))
                    hide(match.range(at: 3))
                }
            case .table:
                let header = original.lineRange(for: NSRange(location: block.range.location, length: 0))
                if NSMaxRange(header) < NSMaxRange(block.range) {
                    hide(original.lineRange(for: NSRange(location: NSMaxRange(header), length: 0)))
                }
                for offset in block.range.location..<NSMaxRange(block.range) where original.character(at: offset) == 124 {
                    separators.insert(offset)
                }
            }
        }
        // Queries may themselves target code punctuation or a link destination.
        // Keep the actual matched source visible even when it is normally syntax.
        if let matchRange {
            let matchedOffsets = matchRange.location..<NSMaxRange(matchRange)
            hidden.remove(integersIn: matchedOffsets)
            separators.remove(integersIn: matchedOffsets)
        }
        var visible: [UInt16] = []
        var sourceOffsets: [Int] = []
        for (offset, unit) in source.utf16.enumerated() where !hidden.contains(offset) {
            let whitespace = separators.contains(offset)
                || UnicodeScalar(unit).map(CharacterSet.whitespacesAndNewlines.contains) == true
            if whitespace {
                guard !visible.isEmpty, visible.last != 32 else { continue }
                visible.append(32)
            } else { visible.append(unit) }
            sourceOffsets.append(offset)
        }
        if visible.last == 32 { visible.removeLast(); sourceOffsets.removeLast() }
        return (String(decoding: visible, as: UTF16.self) as NSString, sourceOffsets)
    }

    private static let image = try! NSRegularExpression(pattern: #"(!\[)([^\]\n]*)(\]\([^\n]*\))"#)
}
