import AppKit
import Testing
@testable import CurrentFeature

@Test
func richTablesParseAlignmentEscapedPipesAndRaggedRows() {
    let source = "| Name | Value | Owner |\n| :--- | :---: | ---: |\n| A\\|B | **Ready** |\n| C | 3 | Raj | ignored |\n\nAfter"
    let blocks = MarkdownRichBlocks.blocks(in: source, protectedRanges: [])
    #expect(blocks.count == 1)
    guard case .table(let table) = blocks.first?.kind else { Issue.record("Expected a table"); return }
    #expect(table.alignments == [.left, .center, .right])
    #expect(table.rows == [["Name", "Value", "Owner"], ["A|B", "**Ready**", ""], ["C", "3", "Raj"]])
    #expect((source as NSString).substring(with: blocks[0].range).hasSuffix("ignored |\n"))
}

@Test
func richTablesRejectMalformedDelimitersAndSkipFences() {
    for source in ["Heading\n---\n", "A | B\n---\n", "A | B\n::--- | ---\n"] {
        #expect(MarkdownRichBlocks.blocks(in: source, protectedRanges: []).isEmpty)
    }
    let source = "```md\n| A | B |\n| --- | --- |\n```\n\n| C | D |\n| --- | --- |\n"
    let protected = MarkdownBlockRendering.parse(in: source).fences.map(\.range)
    let blocks = MarkdownRichBlocks.blocks(in: source, protectedRanges: protected)
    #expect(blocks.count == 1)
    #expect(blocks.first?.source.contains("| C | D |") == true)
}

@Test
@MainActor
func shortTablesFitTheirContentAndKeepIndependentColumnAlignment() throws {
    let table = MarkdownRichBlocks.Table(rows: [["Owner", "Count"], ["Raj", "3"]], alignments: [.left, .right])
    let layout = MarkdownRichBlocks.TableLayout(table: table, width: 640, configuration: .default)
    #expect(layout.width < 240)
    #expect(layout.columnWidths.reduce(0, +) == layout.width)
    #expect(layout.columnOffsets == [0, layout.columnWidths[0]])
    let left = try #require(layout.cells[1][0].attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)
    let right = try #require(layout.cells[1][1].attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)
    #expect(left.alignment == .left)
    #expect(right.alignment == .right)
}

@Test
@MainActor
func longTableCellsUseAvailableWidthAndWrapInTheirMeasuredColumns() {
    let table = MarkdownRichBlocks.Table(
        rows: [["Follow-up", "State"], ["Confirm whether the evidence request covers the EU subsidiary before sending another questionnaire to the vendor.", "Open"]],
        alignments: [.left, .center])
    let wide = MarkdownRichBlocks.TableLayout(table: table, width: 640, configuration: .default)
    let narrow = MarkdownRichBlocks.TableLayout(table: table, width: 320, configuration: .default)
    #expect(abs(wide.width - 640) < 0.01)
    #expect(abs(narrow.width - 320) < 0.01)
    #expect(wide.columnWidths[0] > wide.columnWidths[1] * 3)
    #expect(narrow.rowHeights[1] > wide.rowHeights[1])
    #expect(narrow.height == narrow.rowHeights.reduce(0, +) + 12)
    for (column, text) in narrow.cells[1].enumerated() {
        let padding = min(10, narrow.columnWidths[column] / 4)
        let actual = text.boundingRect(with: NSSize(width: narrow.columnWidths[column] - padding * 2, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading])
        #expect(actual.height <= narrow.rowHeights[1] - 16)
    }
}

@Test
@MainActor
func richTableRenderingKeepsSourceAndRevealsWholeBlockAtCaret() {
    let source = "| Task | State |\n| --- | --- |\n| Review | Ready |\n\nOutside"
    let storage = MarkdownTextStorage(string: source)
    let layout = MarkdownLayoutManager()
    let container = NSTextContainer(size: NSSize(width: CGFloat(600), height: CGFloat.greatestFiniteMagnitude))
    container.lineFragmentPadding = 0
    layout.addTextContainer(container)
    storage.addLayoutManager(layout)
    layout.ensureLayout(for: container)
    #expect(storage.string == source)
    #expect(MarkdownRichBlocks.lineHeight(in: storage, characterRange: NSRange(location: 0, length: 1)) ?? 0 > 30)
    let outside = (source as NSString).range(of: "Outside")
    let outsideGlyph = layout.glyphIndexForCharacter(at: outside.location)
    #expect(layout.lineFragmentRect(forGlyphAt: outsideGlyph, effectiveRange: nil).minY > 70)
    let cell = (source as NSString).range(of: "Ready")
    storage.updateSelectedRange(NSRange(location: cell.location, length: 0))
    #expect(storage.string == source)
    #expect(storage.attribute(.currentRichBlock, at: 0, effectiveRange: nil) == nil)
    #expect((storage.attribute(.currentCollapsedMarkdownSyntax, at: 0, effectiveRange: nil) as? Bool) == false)
    #expect(storage.attribute(.currentRichBlockHeight, at: cell.location, effectiveRange: nil) == nil)
    storage.sourceMode = true
    #expect(storage.string == source)
    #expect(storage.attribute(.currentRichBlockHeight, at: 0, effectiveRange: nil) == nil)
}

@Test
@MainActor
func missingOrRemoteRichImagesKeepReadableSource() {
    for source in ["![Missing](attachments/missing.png)\n", "![Remote](https://example.com/image.png)\n"] {
        let storage = MarkdownTextStorage(string: source)
        #expect(storage.string == source)
        #expect(storage.attribute(.currentRichBlock, at: 0, effectiveRange: nil) == nil)
        #expect((storage.attribute(.currentCollapsedMarkdownSyntax, at: 0, effectiveRange: nil) as? Bool) == false)
    }
    let document = URL(fileURLWithPath: "/tmp/library/2026/09/2026-09-28.md")
    #expect(MarkdownRichBlocks.localImageURL(destination: "attachments/a%20b.png", documentURL: document)?.path == "/tmp/library/2026/09/attachments/a b.png")
    #expect(MarkdownRichBlocks.localImageURL(destination: "https://example.com/a.png", documentURL: document) == nil)
}

@Test
@MainActor
func localImageAttachmentRetainsBytesAndReservesAspectRatio() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("CurrentRichImageTests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let note = root.appendingPathComponent("day.md")
    let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 200, pixelsHigh: 100,
                                            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
    let data = try #require(bitmap.representation(using: .png, properties: [:]))
    let markdown = try MarkdownRichBlocks.importImage(data: data, fileExtension: "png", documentURL: note)
    let blocks = MarkdownRichBlocks.blocks(in: markdown, protectedRanges: [])
    guard case .image(_, let destination) = blocks.first?.kind else { Issue.record("Expected image source"); return }
    let path = try #require(MarkdownRichBlocks.localImageURL(destination: destination, documentURL: note))
    #expect(try Data(contentsOf: path) == data)
    let storage = NSTextStorage(string: markdown)
    MarkdownRichBlocks.apply(blocks, to: storage, targetRange: NSRange(location: 0, length: storage.length),
                             selectedRange: nil, width: 100, configuration: .default, documentURL: note)
    #expect(storage.string == markdown)
    let height = try #require(MarkdownRichBlocks.lineHeight(in: storage, characterRange: NSRange(location: 0, length: 1)))
    #expect(abs(height - 62) < 1)
}
