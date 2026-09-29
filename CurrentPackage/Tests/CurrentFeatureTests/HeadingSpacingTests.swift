import AppKit
import Testing
@testable import CurrentFeature

@Suite(.serialized)
@MainActor
struct HeadingSpacingTests {
    @Test func renderedHeadingCompactsOnlyItsSingleFollowingSeparator() {
        for separator in ["\n", " \t\n", "\r\n"] {
            let source = "Body above\n\n## Follow-ups\n" + separator + "- [ ] Ask support\n"
            let storage = MarkdownTextStorage(string: source)
            let heading = storage.renderModel.headings[0]
            let location = NSMaxRange(heading.lineRange)
            let geometry = layout(storage)
            let headingFrame = frame(at: heading.contentRange.location, in: geometry)
            let separatorFrame = frame(at: location, in: geometry)
            let bodyFrame = frame(at: location + separator.utf16.count, in: geometry)
            #expect(separatorFrame.height == 6)
            #expect(abs(bodyFrame.minY - headingFrame.maxY - 6) < 0.01)
            #expect(frame(at: "Body above\n".utf16.count, in: geometry).height == CurrentTheme.editorLineHeight)
            #expect(storage.string == source)
        }
    }

    @Test func activeSeparatorAndSourceModeKeepFullLineGeometry() {
        let source = "## Follow-ups\n\nBody\n"
        let storage = MarkdownTextStorage(string: source)
        let separator = "## Follow-ups\n".utf16.count
        let geometry = layout(storage)
        storage.updateSelectedRange(NSRange(location: separator + 2, length: 0))
        #expect(frame(at: separator, in: geometry).height == 6)
        storage.updateSelectedRange(NSRange(location: separator, length: 0))
        #expect(frame(at: separator, in: geometry).height == CurrentTheme.editorLineHeight)
        storage.updateSelectedRange(NSRange(location: separator + 1, length: 0))
        #expect(frame(at: separator, in: geometry).height == 6)
        storage.sourceMode = true
        #expect(frame(at: separator, in: geometry).height == CurrentTheme.editorLineHeight)
        storage.sourceMode = false
        #expect(frame(at: separator, in: geometry).height == 6)
        #expect(storage.string == source)
    }

    @Test func dragAndMarkedTextFreezeSeparatorGeometryUntilCommitted() {
        let source = "## Follow-ups\n\nBody\n"
        let storage = MarkdownTextStorage(string: source)
        let separator = "## Follow-ups\n".utf16.count
        let geometry = layout(storage)
        storage.updateSelectedRange(NSRange(location: separator + 1, length: 0))
        storage.suspendsDecorations = true
        storage.updateSelectedRange(NSRange(location: separator, length: 3))
        #expect(frame(at: separator, in: geometry).height == 6)
        storage.suspendsDecorations = false
        #expect(frame(at: separator, in: geometry).height == CurrentTheme.editorLineHeight)
        storage.suspendsDecorations = true
        storage.updateSelectedRange(NSRange(location: separator + 1, length: 0))
        #expect(frame(at: separator, in: geometry).height == CurrentTheme.editorLineHeight)
        storage.suspendsDecorations = false
        #expect(frame(at: separator, in: geometry).height == 6)
        #expect(storage.string == source)
    }

    @Test func intentionalBlankRunsFencesAndTrailingLinesKeepTheirHeight() {
        let fixtures = [
            "## Heading\n\n\nBody\n",
            "## Heading\n\n",
            "## Heading\n ",
            "```\n## Literal\n\nBody\n```\n",
            "## \n\nBody\n"
        ]
        for source in fixtures {
            let storage = MarkdownTextStorage(string: source)
            let text = source as NSString
            var location = 0
            while location < text.length {
                let line = text.lineRange(for: NSRange(location: location, length: 0))
                if text.substring(with: line).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    let style = storage.attribute(.paragraphStyle, at: location, effectiveRange: nil) as? NSParagraphStyle
                    #expect(style?.minimumLineHeight == CurrentTheme.editorLineHeight)
                }
                location = NSMaxRange(line)
            }
        }
    }

    @Test func editingBlankRunAndHeadingRestoresTheCorrectSeparatorStyle() {
        let storage = MarkdownTextStorage(string: "## Heading\n\n\nBody\n")
        let separator = "## Heading\n".utf16.count
        storage.replaceCharacters(in: NSRange(location: separator, length: 1), with: "")
        let geometry = layout(storage)
        #expect(frame(at: separator, in: geometry).height == 6)
        storage.replaceCharacters(in: NSRange(location: separator, length: 0), with: "\n")
        #expect(frame(at: separator, in: geometry).height == CurrentTheme.editorLineHeight)
        storage.replaceCharacters(in: NSRange(location: separator, length: 1), with: "")
        storage.replaceCharacters(in: NSRange(location: 0, length: 3), with: "")
        #expect(frame(at: separator - 3, in: geometry).height == CurrentTheme.editorLineHeight)
        #expect(storage.string == "Heading\n\nBody\n")
    }

    private func layout(_ storage: MarkdownTextStorage) -> (MarkdownLayoutManager, NSTextContainer) {
        let manager = MarkdownLayoutManager()
        let container = NSTextContainer(size: NSSize(width: 640, height: CGFloat.greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        storage.addLayoutManager(manager)
        manager.addTextContainer(container)
        return (manager, container)
    }

    private func frame(at location: Int, in geometry: (MarkdownLayoutManager, NSTextContainer)) -> NSRect {
        let (manager, container) = geometry
        manager.ensureLayout(for: container)
        return manager.lineFragmentRect(forGlyphAt: manager.glyphIndexForCharacter(at: location), effectiveRange: nil)
    }
}
