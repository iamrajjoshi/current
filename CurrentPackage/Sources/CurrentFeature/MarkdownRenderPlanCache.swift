import AppKit

/// A detached attributed source is the render plan. It has no layout manager;
/// only differing source lines are committed to the editor's native storage.
final class MarkdownRenderPlanCache {
    private struct Block: Equatable {
        enum Kind { case line, fence, table, image }
        var range: NSRange
        var kind: Kind
        var compactHeadingSeparator: Bool
    }

    private struct Entry: Equatable {
        var block: Block
        var active: Bool
    }

    private var plan: NSTextStorage?
    private var entries: [Int: Entry] = [:]
    private var blocks: [Block] = []
    private var modelRevision: Int?
    private(set) var buildCount = 0
    private(set) var reuseCount = 0
    private(set) var styledLineCount = 0

    func invalidate() {
        entries.removeAll(keepingCapacity: true)
    }

    func replaceCharacters(in range: NSRange, with text: String) {
        guard let plan else { return }
        let delta = (text as NSString).length - range.length
        var shifted: [Int: Entry] = [:]
        shifted.reserveCapacity(entries.count)
        for var entry in entries.values {
            // Boundary edits can join/split paragraphs and change inherited
            // native attributes. Both adjacent blocks need a new plan.
            if NSMaxRange(entry.block.range) < range.location {
                shifted[entry.block.range.location] = entry
            } else if entry.block.range.location > NSMaxRange(range) {
                entry.block.range.location += delta
                shifted[entry.block.range.location] = entry
            }
        }
        entries = shifted
        plan.replaceCharacters(in: range, with: text)
        modelRevision = nil
    }

    @discardableResult
    func apply(to storage: MarkdownTextStorage, in target: NSRange,
               highlighter: MarkdownSyntaxHighlighter) -> Int {
        let model = storage.renderModel
        var target = target
        if plan == nil { plan = NSTextStorage(string: model.text) }
        guard let plan else { return 0 }
        if modelRevision != storage.sourceRevision {
            blocks = makeBlocks(model)
            let groups = Dictionary(uniqueKeysWithValues: blocks.filter { $0.kind != .line }.map { ($0.range.location, $0) })
            // Restoring a fence opener can turn a later unclosed fence back
            // into ordinary paragraphs, beyond the local edit's new block.
            // Revisit the full old extent so those lines shed their code styles.
            for entry in entries.values where entry.block.kind != .line
                && groups[entry.block.range.location] != entry.block {
                target = NSUnionRange(target, entry.block.range)
            }
            modelRevision = storage.sourceRevision
        }

        let activeRanges = model.liveBlocks(intersecting: storage.selectedRange).map(\.lineRange)
        var requested: [Entry] = []
        var missing: [NSRange] = []
        // Source order lets distant selection changes skip the preceding note.
        var lower = 0, upper = blocks.count
        while lower < upper {
            let middle = (lower + upper) / 2
            if NSMaxRange(blocks[middle].range) <= target.location { lower = middle + 1 }
            else { upper = middle }
        }
        var index = lower
        while index < blocks.count, blocks[index].range.location < NSMaxRange(target) {
            let block = blocks[index]
            let entry = Entry(block: block, active: !storage.sourceMode && activeRanges.contains {
                NSIntersectionRange($0, block.range).length > 0
            })
            requested.append(entry)
            // Image rendering rechecks file metadata, including missing files
            // that appeared since the previous pass. Keep that check reachable.
            if block.kind != .image, entries[block.range.location] == entry {
                reuseCount += 1
            } else {
                buildCount += 1
                if let last = missing.last, NSMaxRange(last) == block.range.location {
                    missing[missing.count - 1] = NSUnionRange(last, block.range)
                } else { missing.append(block.range) }
            }
            index += 1
        }

        let context = MarkdownSyntaxHighlighter.Context(streamLinks: storage.resolvedStreamLinks,
                                                        width: storage.renderWidth, documentURL: storage.documentURL)
        for range in missing {
            // A new fence/table can cover several formerly independent blocks.
            // Their old entries cannot survive overwriting their planned styles.
            entries = entries.filter { NSIntersectionRange($0.value.block.range, range).length == 0 }
            highlighter.highlight(plan, in: range, model: model, selectedRange: storage.selectedRange,
                                  sourceMode: storage.sourceMode, context: context)
        }
        for entry in requested { entries[entry.block.range.location] = entry }

        let source = model.text as NSString
        var changedLines = 0
        storage.beginEditing()
        defer { storage.endEditing() }
        for entry in requested {
            var location = entry.block.range.location
            while location < NSMaxRange(entry.block.range) {
                let line = source.lineRange(for: NSRange(location: location, length: 0))
                let expected = plan.attributedSubstring(from: line)
                // Check actual storage even on a cache hit: paste, undo and
                // native font fixing may have changed its attributes directly.
                if !storage.attributedSubstring(from: line).isEqual(to: expected) {
                    expected.enumerateAttributes(in: NSRange(location: 0, length: expected.length)) { attributes, run, _ in
                        storage.setAttributes(attributes, range: NSRange(location: line.location + run.location, length: run.length))
                    }
                    storage.fixFontAttribute(in: line)
                    changedLines += 1
                }
                location = NSMaxRange(line)
            }
        }
        styledLineCount += changedLines
        return changedLines
    }

    private func makeBlocks(_ model: MarkdownEditorRenderModel) -> [Block] {
        let source = model.text as NSString
        let grouped = (model.fences.map { Block(range: $0.range, kind: .fence, compactHeadingSeparator: false) }
            + model.richBlocks.map { block in
                let kind: Block.Kind
                switch block.kind { case .image: kind = .image; case .table: kind = .table }
                return Block(range: block.range, kind: kind, compactHeadingSeparator: false)
            })
            .sorted { $0.range.location < $1.range.location }
        let separators = Set(model.headingSeparators.map(\.location))
        var result: [Block] = []
        var group = 0
        var location = 0
        while location < source.length {
            let block: Block
            if group < grouped.count, grouped[group].range.location == location {
                block = grouped[group]
                group += 1
            } else {
                block = Block(range: source.lineRange(for: NSRange(location: location, length: 0)),
                              kind: .line, compactHeadingSeparator: separators.contains(location))
            }
            result.append(block)
            location = NSMaxRange(block.range)
        }
        return result
    }
}
