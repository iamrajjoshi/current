import AppKit

/// The timeline and live editor share natural heights. Selection-dependent
/// active geometry is separate from the inactive preview of the same source.
enum MarkdownTextLayoutMeasurer {
    private final class Key: NSObject {
        let text: String
        let width: CGFloat
        let configuration: CurrentConfiguration
        let sourceMode: Bool
        let isActive: Bool
        let documentURL: URL?
        init(text: String, width: CGFloat, configuration: CurrentConfiguration, sourceMode: Bool, isActive: Bool, documentURL: URL?) {
            self.text = text
            self.width = width
            self.configuration = configuration
            self.sourceMode = sourceMode
            self.isActive = isActive
            self.documentURL = documentURL
        }
        override var hash: Int {
            var hasher = Hasher()
            hasher.combine(text); hasher.combine(width); hasher.combine(configuration)
            hasher.combine(sourceMode); hasher.combine(isActive); hasher.combine(documentURL)
            return hasher.finalize()
        }
        override func isEqual(_ object: Any?) -> Bool {
            guard let other = object as? Key else { return false }
            return width == other.width && sourceMode == other.sourceMode && isActive == other.isActive
                && configuration == other.configuration && text == other.text && documentURL == other.documentURL
        }
    }

    // NSCache synchronizes its own access; keys and values are immutable. This
    // avoids imposing actor isolation on the existing synchronous sizing API.
    nonisolated(unsafe) private static let heights: NSCache<Key, NSNumber> = {
        let cache = NSCache<Key, NSNumber>()
        cache.countLimit = 256
        cache.totalCostLimit = 8 * 1024 * 1024
        return cache
    }()

    static func measuredHeight(
        text: String,
        width: CGFloat,
        minimumHeight: CGFloat,
        configuration: CurrentConfiguration,
        sourceMode: Bool = false,
        isActive: Bool = false,
        documentURL: URL? = nil
    ) -> CGFloat {
        let width = max(1, width)
        let key = Key(text: text, width: width, configuration: configuration, sourceMode: sourceMode, isActive: isActive, documentURL: documentURL)
        if let cached = heights.object(forKey: key) { return max(minimumHeight, cached.doubleValue) }
        let textStorage = MarkdownTextStorage(string: text, configuration: configuration)
        textStorage.sourceMode = sourceMode
        textStorage.renderWidth = width
        textStorage.documentURL = documentURL
        let layoutManager = MarkdownLayoutManager()
        let textContainer = NSTextContainer(size: NSSize(width: width, height: CGFloat.greatestFiniteMagnitude))
        textContainer.lineFragmentPadding = 0
        textStorage.addLayoutManager(layoutManager)
        layoutManager.addTextContainer(textContainer)
        layoutManager.ensureLayout(for: textContainer)
        let height = ceil(layoutManager.usedRect(for: textContainer).height + CurrentTheme.editorVerticalInset * 2 + 6)
        heights.setObject(NSNumber(value: height), forKey: key, cost: text.utf16.count * 2)
        return max(minimumHeight, height)
    }

    static func rememberHeight(_ height: CGFloat, text: String, width: CGFloat,
                               configuration: CurrentConfiguration, sourceMode: Bool, selectedRange: NSRange?, documentURL: URL? = nil) {
        let key = Key(text: text, width: max(1, width), configuration: configuration,
                      sourceMode: sourceMode, isActive: selectedRange != nil, documentURL: documentURL)
        heights.setObject(NSNumber(value: height), forKey: key, cost: text.utf16.count * 2)
    }
}
