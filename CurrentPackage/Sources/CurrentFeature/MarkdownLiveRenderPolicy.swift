import Foundation

struct MarkdownLiveRenderPolicy {
    enum SyntaxVisibility: Equatable {
        case hidden
        case revealed
    }

    var model: MarkdownEditorRenderModel
    var selectedRange: NSRange?

    private var activeBlocks: [MarkdownLiveBlock] {
        model.liveBlocks(intersecting: selectedRange)
    }

    var activeBlockRanges: [NSRange] {
        activeBlocks.map(\.lineRange)
    }

    func activeBlock(at location: Int) -> MarkdownLiveBlock? {
        activeBlocks.first { NSLocationInRange(location, $0.lineRange) || location == NSMaxRange($0.lineRange) }
    }

    func isActive(_ range: NSRange) -> Bool {
        activeBlockRanges.contains { NSIntersectionRange($0, range).length > 0 }
    }

    func syntaxVisibility(for range: NSRange) -> SyntaxVisibility {
        isActive(range) ? .revealed : .hidden
    }

    func horizontalRuleIsActive(_ horizontalRule: MarkdownBlockRendering.HorizontalRuleLine) -> Bool {
        isActive(horizontalRule.markerRange)
    }

    static func decorationRangeForSelectionChange(
        in text: String,
        oldSelectedRange: NSRange?,
        newSelectedRange: NSRange?
    ) -> NSRange? {
        let model = MarkdownEditorRenderModel(text: text)
        let ranges = (
            model.liveBlocks(intersecting: oldSelectedRange)
            + model.liveBlocks(intersecting: newSelectedRange)
        ).map(\.lineRange)

        guard var union = ranges.first else { return nil }
        for range in ranges.dropFirst() {
            union = NSUnionRange(union, range)
        }
        return union
    }
}
