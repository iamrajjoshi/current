import AppKit

enum MarkdownTextLayoutMeasurer {
    static func measuredHeight(
        text: String,
        width: CGFloat,
        minimumHeight: CGFloat,
        configuration: CurrentConfiguration
    ) -> CGFloat {
        let textStorage = MarkdownTextStorage(string: text, configuration: configuration)
        let layoutManager = MarkdownLayoutManager()
        let textContainer = NSTextContainer(
            size: NSSize(width: max(1, width), height: CGFloat.greatestFiniteMagnitude)
        )
        textContainer.lineFragmentPadding = 0
        textStorage.addLayoutManager(layoutManager)
        layoutManager.addTextContainer(textContainer)

        layoutManager.ensureLayout(for: textContainer)

        let used = layoutManager.usedRect(for: textContainer)
        return max(
            minimumHeight,
            ceil(used.height + CurrentTheme.editorVerticalInset * 2 + 6)
        )
    }
}
