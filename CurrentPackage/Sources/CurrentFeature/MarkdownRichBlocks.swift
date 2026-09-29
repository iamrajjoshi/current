import AppKit
import ImageIO

extension NSAttributedString.Key {
    static let currentRichBlock = NSAttributedString.Key("current.richBlock")
    static let currentRichBlockHeight = NSAttributedString.Key("current.richBlockHeight")
}

/// Rich blocks decorate source characters; they never replace document text.
enum MarkdownRichBlocks {
    static let imagesDidLoad = Notification.Name("CurrentMarkdownImagesDidLoad")

    enum Alignment: Equatable { case left, center, right }

    struct Table: Equatable {
        var rows: [[String]]
        var alignments: [Alignment]
    }

    enum Kind: Equatable {
        case table(Table)
        case image(alt: String, destination: String)
    }

    struct Block: Equatable {
        var range: NSRange
        var source: String
        var kind: Kind
    }

    static func blocks(in text: String, protectedRanges: [NSRange]) -> [Block] {
        let source = text as NSString
        var lines: [(range: NSRange, body: String)] = []
        var offset = 0
        while offset < source.length {
            let range = source.lineRange(for: NSRange(location: offset, length: 0))
            lines.append((range, source.substring(with: range).trimmingCharacters(in: .newlines)))
            offset = NSMaxRange(range)
        }
        var result: [Block] = []
        var index = 0
        var protectedIndex = 0
        func protected(_ range: NSRange) -> Bool {
            while protectedIndex < protectedRanges.count, NSMaxRange(protectedRanges[protectedIndex]) <= range.location {
                protectedIndex += 1
            }
            return protectedIndex < protectedRanges.count && NSIntersectionRange(range, protectedRanges[protectedIndex]).length > 0
        }
        while index < lines.count {
            let line = lines[index]
            if protected(line.range) { index += 1; continue }
            if let image = parseImage(line.body) {
                result.append(Block(range: line.range, source: source.substring(with: line.range), kind: image))
                index += 1
                continue
            }
            guard index + 1 < lines.count, !protected(lines[index + 1].range),
                  line.body.contains("|"), let header = cells(line.body),
                  let delimiters = cells(lines[index + 1].body), header.count == delimiters.count,
                  let alignments = tableAlignments(delimiters) else { index += 1; continue }
            var rows = [header]
            var end = index + 2
            while end < lines.count, !protected(lines[end].range), lines[end].body.contains("|"),
                  let row = cells(lines[end].body) {
                rows.append(Array((row + Array(repeating: "", count: header.count)).prefix(header.count)))
                end += 1
            }
            let range = NSRange(location: line.range.location, length: NSMaxRange(lines[end - 1].range) - line.range.location)
            result.append(Block(range: range, source: source.substring(with: range), kind: .table(Table(rows: rows, alignments: alignments))))
            index = end
        }
        return result
    }

    /// Escaped pipes belong to the cell, including those inside inline code.
    static func cells(_ line: String) -> [String]? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        var result: [String] = []
        var cell = ""
        var escaped = false
        for character in trimmed {
            if escaped {
                if character != "|" { cell.append("\\") }
                cell.append(character)
                escaped = false
            } else if character == "\\" {
                escaped = true
            } else if character == "|" {
                result.append(cell.trimmingCharacters(in: .whitespaces))
                cell = ""
            } else { cell.append(character) }
        }
        if escaped { cell.append("\\") }
        result.append(cell.trimmingCharacters(in: .whitespaces))
        if trimmed.first == "|", result.first == "" { result.removeFirst() }
        if trimmed.last == "|", result.last == "" { result.removeLast() }
        return result.isEmpty ? nil : result
    }

    private static func tableAlignments(_ cells: [String]) -> [Alignment]? {
        var alignments: [Alignment] = []
        for cell in cells {
            guard cell.range(of: #"^:?-+:?$"#, options: .regularExpression) != nil else { return nil }
            alignments.append(cell.hasSuffix(":") ? (cell.hasPrefix(":") ? .center : .right) : .left)
        }
        return alignments
    }

    private static let imagePattern = try! NSRegularExpression(pattern: #"^[ ]{0,3}!\[([^\]\n]*)\]\((.+)\)[ \t]*$"#)

    private static func parseImage(_ line: String) -> Kind? {
        let source = line as NSString
        guard let match = imagePattern.firstMatch(in: line, range: NSRange(location: 0, length: source.length)) else { return nil }
        var destination = source.substring(with: match.range(at: 2)).trimmingCharacters(in: .whitespaces)
        if destination.hasPrefix("<"), let close = destination.firstIndex(of: ">") {
            destination = String(destination[destination.index(after: destination.startIndex)..<close])
        } else {
            // Optional quoted Markdown image title follows a whitespace separator.
            if let title = destination.range(of: #"\s+["']"#, options: .regularExpression) {
                destination = String(destination[..<title.lowerBound])
            }
            destination = destination.replacingOccurrences(of: #"\([\() ])"#, with: "$1", options: .regularExpression)
        }
        guard !destination.isEmpty else { return nil }
        return .image(alt: source.substring(with: match.range(at: 1)), destination: destination)
    }

    static func localImageURL(destination: String, documentURL: URL?) -> URL? {
        if let url = URL(string: destination), url.scheme != nil { return url.isFileURL ? url.standardizedFileURL : nil }
        guard let documentURL, documentURL.isFileURL,
              let resolved = URL(string: destination, relativeTo: documentURL.deletingLastPathComponent())?.absoluteURL,
              resolved.isFileURL else { return nil }
        return resolved.standardizedFileURL
    }

    static func apply(_ blocks: [Block], to storage: NSTextStorage, targetRange: NSRange, selectedRange: NSRange?,
                      width: CGFloat, configuration: CurrentConfiguration, documentURL: URL?) {
        guard width.isFinite, width > 20 else { return }
        let source = storage.string as NSString
        for block in blocks where NSIntersectionRange(block.range, targetRange).length > 0 && NSMaxRange(block.range) <= source.length {
            storage.removeAttribute(.currentRichBlock, range: block.range)
            storage.removeAttribute(.currentRichBlockHeight, range: block.range)
            let selected = selectedRange.map {
                $0.length == 0 ? ($0.location >= block.range.location && $0.location < NSMaxRange(block.range))
                    : NSIntersectionRange($0, block.range).length > 0
            } ?? false
            if selected {
                storage.addAttributes([
                    .currentHiddenMarkdownSyntax: false, .currentCollapsedMarkdownSyntax: false,
                    .foregroundColor: CurrentTheme.primaryTextColor,
                    .font: CurrentTheme.editorCodeFont(configuration: configuration)
                ], range: block.range)
                continue
            }
            guard let widget = makeWidget(block, width: width, configuration: configuration, documentURL: documentURL) else {
                // A missing, unsupported, or invalid image retains its editable Markdown.
                storage.addAttributes([
                    .currentHiddenMarkdownSyntax: false, .currentCollapsedMarkdownSyntax: false,
                    .foregroundColor: CurrentTheme.secondaryTextColor
                ], range: block.range)
                continue
            }
            storage.addAttributes([
                .currentHiddenMarkdownSyntax: true, .currentCollapsedMarkdownSyntax: true,
                .foregroundColor: NSColor.clear, .underlineStyle: 0, .strikethroughStyle: 0,
                .backgroundColor: NSColor.clear, .baselineOffset: 0
            ], range: block.range)
            var location = block.range.location
            while location < NSMaxRange(block.range) {
                let line = NSIntersectionRange(source.lineRange(for: NSRange(location: location, length: 0)), block.range)
                let height = location == block.range.location ? widget.height : 1
                let paragraph = NSMutableParagraphStyle()
                paragraph.minimumLineHeight = height
                paragraph.maximumLineHeight = height
                storage.addAttributes([.paragraphStyle: paragraph, .currentRichBlockHeight: height], range: line)
                if location == block.range.location { storage.addAttribute(.currentRichBlock, value: widget, range: line) }
                // TextKit drops a paragraph containing only null glyphs. Keep one invisible
                // anchor and its line terminator so the reserved block has a drawable line.
                storage.addAttribute(.currentCollapsedMarkdownSyntax, value: false, range: NSRange(location: line.location, length: 1))
                let last = NSMaxRange(line) - 1
                if [10, 13, 0x2028, 0x2029].contains(source.character(at: last)) {
                    storage.addAttribute(.currentCollapsedMarkdownSyntax, value: false, range: NSRange(location: last, length: 1))
                }
                location = NSMaxRange(line)
            }
        }
    }

    static func lineHeight(in storage: NSTextStorage, characterRange: NSRange) -> CGFloat? {
        guard characterRange.location < storage.length else { return nil }
        return storage.attribute(.currentRichBlockHeight, at: characterRange.location, effectiveRange: nil) as? CGFloat
    }

    static func draw(in layoutManager: NSLayoutManager, glyphRange: NSRange, origin: NSPoint) {
        guard let storage = layoutManager.textStorage else { return }
        layoutManager.enumerateLineFragments(forGlyphRange: glyphRange) { rect, _, _, glyphs, _ in
            let chars = layoutManager.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
            guard chars.location < storage.length,
                  let widget = storage.attribute(.currentRichBlock, at: chars.location, effectiveRange: nil) as? Widget else { return }
            widget.draw(at: NSPoint(x: origin.x + rect.minX, y: origin.y + rect.minY))
        }
    }

    private final class Widget: NSObject {
        let height: CGFloat
        let width: CGFloat
        let table: TableLayout?
        let image: ImageResult?
        let alt: String

        init(table: TableLayout) {
            self.table = table; height = table.height; width = table.width; image = nil; alt = ""
        }

        init(image: ImageResult, width: CGFloat, alt: String) {
            self.image = image; self.width = min(width, image.size.width)
            height = max(24, image.size.height * self.width / max(1, image.size.width)) + 12
            table = nil; self.alt = alt
        }

        func draw(at point: NSPoint) {
            if let table { table.draw(at: point); return }
            let box = NSRect(x: point.x, y: point.y + 6, width: width, height: height - 12)
            if let image = image?.image {
                image.draw(in: box, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high])
            } else {
                CurrentTheme.inlineCodeBackgroundColor.setFill()
                NSBezierPath(roundedRect: box, xRadius: 6, yRadius: 6).fill()
                let caption = alt.isEmpty ? "Loading image…" : alt
                (caption as NSString).draw(in: box.insetBy(dx: 12, dy: 12), withAttributes: [
                    .font: NSFont.systemFont(ofSize: 13), .foregroundColor: CurrentTheme.secondaryTextColor
                ])
            }
        }
    }

    private static func makeWidget(_ block: Block, width: CGFloat, configuration: CurrentConfiguration, documentURL: URL?) -> Widget? {
        switch block.kind {
        case .table(let table):
            return Widget(table: TableCache.shared.layout(table: table, source: block.source, width: width, configuration: configuration))
        case .image(let alt, let destination):
            guard let url = localImageURL(destination: destination, documentURL: documentURL),
                  let result = ImageCache.shared.request(url), !result.failed else { return nil }
            return Widget(image: result, width: width, alt: alt)
        }
    }

    private final class TableCache: @unchecked Sendable {
        static let shared = TableCache()
        private let cache = NSCache<NSString, TableLayout>()
        private init() { cache.countLimit = 64; cache.totalCostLimit = 8 * 1024 * 1024 }

        func layout(table: Table, source: String, width: CGFloat, configuration: CurrentConfiguration) -> TableLayout {
            let font = CurrentTheme.editorFont(configuration: configuration)
            let key = "\(width)|\(font.fontName)|\(font.pointSize)|\(CurrentTheme.editorLineHeight(configuration: configuration))|\(source)" as NSString
            if let hit = cache.object(forKey: key) { return hit }
            let layout = TableLayout(table: table, width: width, configuration: configuration)
            cache.setObject(layout, forKey: key, cost: source.utf16.count * 8)
            return layout
        }
    }

    final class TableLayout {
        let width: CGFloat
        let height: CGFloat
        let columnWidths: [CGFloat]
        let columnOffsets: [CGFloat]
        let rowHeights: [CGFloat]
        let cells: [[NSAttributedString]]

        init(table: Table, width: CGFloat, configuration: CurrentConfiguration) {
            let rows = table.rows.enumerated().map { index, row in
                row.enumerated().map {
                    Self.cell($0.element, alignment: table.alignments[$0.offset], header: index == 0, configuration: configuration)
                }
            }
            let preferred = table.alignments.indices.map { column in
                max(44, ceil(rows.map { $0[column].size().width }.max() ?? 0) + 20)
            }
            let minimum = table.alignments.indices.map { column in
                let wordWidth = rows.flatMap { row -> [CGFloat] in
                    let text = row[column]
                    let source = text.string as NSString
                    return Self.wordPattern.matches(in: text.string, range: NSRange(location: 0, length: source.length)).map {
                        text.attributedSubstring(from: $0.range).size().width
                    }
                }.max() ?? 0
                return min(preferred[column], max(44, min(120, ceil(wordWidth) + 20)))
            }
            let widths = Self.fit(preferred: preferred, minimum: minimum, available: max(1, width))
            columnWidths = widths
            var x: CGFloat = 0
            columnOffsets = widths.map { width in defer { x += width }; return x }
            self.width = widths.reduce(0, +)
            let heights: [CGFloat] = rows.map { row in
                let contentHeight = row.enumerated().map { column, text in
                    let inset = Self.padding(for: widths[column])
                    return text.boundingRect(with: NSSize(width: max(1, widths[column] - inset * 2), height: .greatestFiniteMagnitude),
                                             options: [.usesLineFragmentOrigin, .usesFontLeading]).height
                }.max() ?? 0
                return ceil(max(CurrentTheme.editorLineHeight(configuration: configuration), contentHeight)) + 16
            }
            cells = rows; rowHeights = heights
            height = heights.reduce(0, +) + 12
        }

        private static let wordPattern = try! NSRegularExpression(pattern: #"\S+"#)

        private static func padding(for width: CGFloat) -> CGFloat { min(10, width / 4) }

        private static func fit(preferred: [CGFloat], minimum: [CGFloat], available: CGFloat) -> [CGFloat] {
            let natural = preferred.reduce(0, +)
            guard natural > available else { return preferred }
            let floor = minimum.reduce(0, +)
            if floor >= available { return minimum.map { $0 * available / floor } }
            let remaining = available - floor
            return zip(preferred, minimum).map { wanted, base in
                base + remaining * (wanted - base) / (natural - floor)
            }
        }

        func draw(at point: NSPoint) {
            guard let first = cells.first, !first.isEmpty else { return }
            var y = point.y + 6
            for (row, cellRow) in cells.enumerated() {
                let rowHeight = rowHeights[row]
                let rowRect = NSRect(x: point.x, y: y, width: width, height: rowHeight)
                if row == 0 {
                    CurrentTheme.inlineCodeBackgroundColor.setFill()
                    rowRect.fill()
                }
                for (column, text) in cellRow.enumerated() {
                    let columnWidth = columnWidths[column]
                    let box = NSRect(x: point.x + columnOffsets[column], y: y, width: columnWidth, height: rowHeight)
                    NSGraphicsContext.saveGraphicsState()
                    NSBezierPath(rect: box).addClip()
                    text.draw(with: box.insetBy(dx: Self.padding(for: columnWidth), dy: 8), options: [.usesLineFragmentOrigin, .usesFontLeading])
                    NSGraphicsContext.restoreGraphicsState()
                }
                CurrentTheme.dividerColor.setStroke()
                let line = NSBezierPath()
                line.lineWidth = 1
                line.move(to: NSPoint(x: point.x, y: y + rowHeight - 0.5))
                line.line(to: NSPoint(x: point.x + width, y: y + rowHeight - 0.5))
                line.stroke()
                y += rowHeight
            }
        }

        private static func cell(_ source: String, alignment: Alignment, header: Bool, configuration: CurrentConfiguration) -> NSAttributedString {
            let font = CurrentTheme.editorFont(configuration: configuration)
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = alignment == .center ? .center : alignment == .right ? .right : .left
            paragraph.lineBreakMode = .byWordWrapping
            paragraph.minimumLineHeight = CurrentTheme.editorLineHeight(configuration: configuration)
            paragraph.maximumLineHeight = CurrentTheme.editorLineHeight(configuration: configuration)
            let result = NSMutableAttributedString(string: source, attributes: [
                .font: header ? CurrentTheme.editorBoldFont(matching: font) : font,
                .foregroundColor: CurrentTheme.primaryTextColor, .paragraphStyle: paragraph
            ])
            let spans = MarkdownInlineRendering.spans(in: source)
            for span in spans {
                var attributes: [NSAttributedString.Key: Any] = [:]
                switch span.kind {
                case .bold: attributes[.font] = CurrentTheme.editorBoldFont(matching: font)
                case .italic: attributes[.obliqueness] = 0.12
                case .underline: attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
                case .strikethrough: attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
                case .inlineCode: attributes[.font] = CurrentTheme.editorCodeFont(configuration: configuration)
                case .link: attributes[.foregroundColor] = CurrentTheme.accentColor
                }
                result.addAttributes(attributes, range: span.contentRange)
            }
            var syntax = IndexSet()
            for range in spans.flatMap(\.syntaxRanges) { syntax.insert(integersIn: range.location..<NSMaxRange(range)) }
            for range in syntax.rangeView.reversed() { result.deleteCharacters(in: NSRange(range)) }
            return result
        }
    }

    private final class ImageResult: NSObject, @unchecked Sendable {
        let size: NSSize
        let image: NSImage?
        let failed: Bool
        init(size: NSSize, image: NSImage? = nil, failed: Bool = false) {
            self.size = size; self.image = image; self.failed = failed
        }
    }

    /// File metadata invalidates cached thumbnails after an external image edit.
    private final class ImageCache: @unchecked Sendable {
        static let shared = ImageCache()
        private let cache = NSCache<NSString, ImageResult>()
        private let lock = NSLock()
        private init() { cache.countLimit = 128; cache.totalCostLimit = 64 * 1024 * 1024 }

        func request(_ url: URL) -> ImageResult? {
            guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey]),
                  values.isRegularFile == true else { return nil }
            let key = "\(url.path)|\(values.contentModificationDate?.timeIntervalSince1970 ?? 0)|\(values.fileSize ?? 0)"
            lock.lock(); defer { lock.unlock() }
            if let hit = cache.object(forKey: key as NSString) { return hit }
            guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
                  let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                  let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
                  let height = properties[kCGImagePropertyPixelHeight] as? NSNumber,
                  width.doubleValue > 0, height.doubleValue > 0 else { return nil }
            let orientation = (properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
            let size = (5...8).contains(orientation)
                ? NSSize(width: height.doubleValue, height: width.doubleValue)
                : NSSize(width: width.doubleValue, height: height.doubleValue)
            let pending = ImageResult(size: size)
            cache.setObject(pending, forKey: key as NSString)
            DispatchQueue.global(qos: .userInitiated).async { [self] in
                var image: NSImage?
                if let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                   let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: 1600
                   ] as CFDictionary) {
                    image = NSImage(cgImage: thumbnail, size: size)
                }
                cache.setObject(ImageResult(size: size, image: image, failed: image == nil), forKey: key as NSString,
                                cost: image == nil ? 1 : 1600 * 1600 * 4)
                DispatchQueue.main.async { NotificationCenter.default.post(name: imagesDidLoad, object: url) }
            }
            return pending
        }
    }

    /// Attachments survive undo so redoing the source insertion remains valid.
    static func importImage(data: Data, fileExtension: String, documentURL: URL) throws -> String {
        guard documentURL.isFileURL, CGImageSourceCreateWithData(data as CFData, nil) != nil else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let allowedExtensions = ["png", "jpg", "jpeg", "gif", "heic", "heif", "tiff", "tif", "webp", "bmp"]
        let ext = fileExtension.lowercased()
        guard allowedExtensions.contains(ext) else { throw CocoaError(.fileReadUnknown) }
        let directory = documentURL.deletingLastPathComponent().appendingPathComponent("attachments", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let filename = "image-\(UUID().uuidString.lowercased()).\(ext)"
        try data.write(to: directory.appendingPathComponent(filename), options: .atomic)
        return "![Image](attachments/\(filename))"
    }

    static func importImage(from sourceURL: URL, documentURL: URL) throws -> String {
        try importImage(data: Data(contentsOf: sourceURL), fileExtension: sourceURL.pathExtension, documentURL: documentURL)
    }
}
