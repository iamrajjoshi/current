import AppKit
import Testing
@testable import CurrentFeature

// This target stays XCTest-free so `swift test` can compile on machines that
// only have Command Line Tools installed.
func currentFeatureTestsCompile() {
    _ = StreamStore.defaultStreamName
}

@Test
func highlighterUnderlinesOnlyExplicitUnderlineContent() {
    let text = "<u>sdhusiafsd</u>\nadfjkhsd"
    let storage = highlightedStorage(text)
    let nsText = text as NSString
    let contentIndex = nsText.range(of: "sdhusiafsd").location
    let newlineIndex = nsText.range(of: "\n").location
    let followingLineIndex = nsText.range(of: "adfjkhsd").location

    #expect(intAttribute(.underlineStyle, in: storage, at: contentIndex) == NSUnderlineStyle.single.rawValue)
    #expect(intAttribute(.underlineStyle, in: storage, at: newlineIndex) == 0)
    #expect(intAttribute(.underlineStyle, in: storage, at: followingLineIndex) == 0)
    #expect(backgroundIsClear(in: storage, at: newlineIndex))
    #expect(backgroundIsClear(in: storage, at: followingLineIndex))
}

@Test
func highlighterDoesNotAddUnderlineOrBackgroundToListLines() {
    let text = "1. fdsjflkdf=\n2. fdsfs\n\n<u>sdhusiafsd</u>\nadfjkhsd"
    let storage = highlightedStorage(text)
    let nsText = text as NSString
    let firstListTextIndex = nsText.range(of: "fdsjflkdf=").location
    let secondListTextIndex = nsText.range(of: "fdsfs").location
    let firstNewlineIndex = nsText.range(of: "\n").location

    for index in [firstListTextIndex, secondListTextIndex, firstNewlineIndex] {
        #expect(intAttribute(.underlineStyle, in: storage, at: index) == 0)
        #expect(intAttribute(.strikethroughStyle, in: storage, at: index) == 0)
        #expect(backgroundIsClear(in: storage, at: index))
    }
}

@Test
func highlighterClearsStaleDecorationAttributes() {
    let storage = NSTextStorage(string: "plain")
    storage.addAttributes(
        [
            .underlineStyle: NSUnderlineStyle.single.rawValue,
            .strikethroughStyle: NSUnderlineStyle.single.rawValue,
            .backgroundColor: NSColor.systemBlue
        ],
        range: NSRange(location: 0, length: storage.length)
    )

    MarkdownSyntaxHighlighter().highlight(storage)

    #expect(intAttribute(.underlineStyle, in: storage, at: 0) == 0)
    #expect(intAttribute(.strikethroughStyle, in: storage, at: 0) == 0)
    #expect(backgroundIsClear(in: storage, at: 0))
}

@Test
func highlighterClearsTemporaryDecorationAttributes() {
    let storage = NSTextStorage(string: "plain")
    let layoutManager = NSLayoutManager()
    let textContainer = NSTextContainer(size: NSSize(width: 200, height: 200))
    layoutManager.addTextContainer(textContainer)
    storage.addLayoutManager(layoutManager)

    let range = NSRange(location: 0, length: storage.length)
    layoutManager.addTemporaryAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, forCharacterRange: range)
    layoutManager.addTemporaryAttribute(.underlineColor, value: NSColor.systemBlue, forCharacterRange: range)

    MarkdownSyntaxHighlighter().highlight(storage)

    #expect(layoutManager.temporaryAttribute(.underlineStyle, atCharacterIndex: 0, effectiveRange: nil) == nil)
    #expect(layoutManager.temporaryAttribute(.underlineColor, atCharacterIndex: 0, effectiveRange: nil) == nil)
}

private func highlightedStorage(_ text: String) -> NSTextStorage {
    let storage = NSTextStorage(string: text)
    MarkdownSyntaxHighlighter().highlight(storage)
    return storage
}

private func intAttribute(_ key: NSAttributedString.Key, in storage: NSTextStorage, at index: Int) -> Int {
    switch storage.attribute(key, at: index, effectiveRange: nil) {
    case let value as Int:
        return value
    case let value as NSNumber:
        return value.intValue
    default:
        return 0
    }
}

private func backgroundIsClear(in storage: NSTextStorage, at index: Int) -> Bool {
    guard let color = storage.attribute(.backgroundColor, at: index, effectiveRange: nil) as? NSColor else {
        return true
    }
    return color.alphaComponent == 0
}
