import AppKit

final class MarkdownTextStorage: NSTextStorage {
    private let backingStore = NSMutableAttributedString()
    private let highlighter: MarkdownSyntaxHighlighter
    private var isApplyingDecorations = false
    private(set) var selectedRange: NSRange?

    var configuration: CurrentConfiguration {
        didSet {
            highlighter.update(configuration: configuration)
            applyDecorations()
        }
    }

    init(string: String = "", configuration: CurrentConfiguration = .default) {
        self.configuration = configuration
        self.highlighter = MarkdownSyntaxHighlighter(configuration: configuration)
        super.init()
        backingStore.setAttributedString(NSAttributedString(string: string))
        applyDecorations()
    }

    required init?(coder: NSCoder) {
        self.configuration = .default
        self.highlighter = MarkdownSyntaxHighlighter(configuration: .default)
        super.init(coder: coder)
    }

    required init?(
        pasteboardPropertyList propertyList: Any,
        ofType type: NSPasteboard.PasteboardType
    ) {
        self.configuration = .default
        self.highlighter = MarkdownSyntaxHighlighter(configuration: .default)
        super.init()
        if let string = propertyList as? String {
            backingStore.setAttributedString(NSAttributedString(string: string))
            applyDecorations()
        }
    }

    required init(itemProviderData data: Data, typeIdentifier: String) throws {
        self.configuration = .default
        self.highlighter = MarkdownSyntaxHighlighter(configuration: .default)
        super.init()
        if let string = String(data: data, encoding: .utf8) {
            backingStore.setAttributedString(NSAttributedString(string: string))
            applyDecorations()
        }
    }

    override var string: String {
        backingStore.string
    }

    override func attributes(
        at location: Int,
        effectiveRange range: NSRangePointer?
    ) -> [NSAttributedString.Key: Any] {
        backingStore.attributes(at: location, effectiveRange: range)
    }

    override func attributes(
        at location: Int,
        longestEffectiveRange range: NSRangePointer?,
        in rangeLimit: NSRange
    ) -> [NSAttributedString.Key: Any] {
        backingStore.attributes(at: location, longestEffectiveRange: range, in: rangeLimit)
    }

    override func replaceCharacters(in range: NSRange, with string: String) {
        backingStore.replaceCharacters(in: range, with: string)
        edited(.editedCharacters, range: range, changeInLength: (string as NSString).length - range.length)
    }

    override func setAttributes(_ attrs: [NSAttributedString.Key: Any]?, range: NSRange) {
        backingStore.setAttributes(attrs, range: range)
        edited(.editedAttributes, range: range, changeInLength: 0)
    }

    override func processEditing() {
        let editedCharacters = editedMask.contains(.editedCharacters)
        let decorationRange = editedRange

        super.processEditing()

        guard editedCharacters, !isApplyingDecorations else { return }
        applyDecorations(around: decorationRange)
    }

    func applyDecorations() {
        guard length > 0, !isApplyingDecorations else { return }
        isApplyingDecorations = true
        highlighter.highlight(self, selectedRange: selectedRange)
        isApplyingDecorations = false
    }

    func applyDecorations(around editedRange: NSRange?) {
        guard length > 0, !isApplyingDecorations else { return }
        isApplyingDecorations = true
        highlighter.highlightAroundEditedRange(self, editedRange: editedRange, selectedRange: selectedRange)
        isApplyingDecorations = false
    }

    func updateSelectedRange(_ range: NSRange?) {
        let boundedRange = boundedSelection(range)
        guard boundedRange != selectedRange else { return }

        let oldSelectedRange = selectedRange
        selectedRange = boundedRange
        guard length > 0, !isApplyingDecorations else { return }

        isApplyingDecorations = true
        highlighter.highlightAroundSelectionChange(
            self,
            oldSelectedRange: oldSelectedRange,
            newSelectedRange: selectedRange
        )
        isApplyingDecorations = false
    }

    func syntaxRangeIsRevealed(_ range: NSRange) -> Bool {
        guard length > 0 else { return false }
        let model = MarkdownEditorRenderModel(text: string)
        let policy = MarkdownLiveRenderPolicy(model: model, selectedRange: selectedRange)
        return policy.syntaxVisibility(for: range) == .revealed
    }

    func horizontalRuleIsActive(_ horizontalRule: MarkdownBlockRendering.HorizontalRuleLine) -> Bool {
        guard length > 0 else { return false }
        let model = MarkdownEditorRenderModel(text: string)
        let policy = MarkdownLiveRenderPolicy(model: model, selectedRange: selectedRange)
        return policy.horizontalRuleIsActive(horizontalRule)
    }

    func clearDecorations() {
        guard length > 0 else { return }
        highlighter.clearTemporaryDecorations(self)
    }

    private func boundedSelection(_ range: NSRange?) -> NSRange? {
        guard let range else { return nil }
        let boundedLocation = min(max(0, range.location), length)
        let boundedLength = min(max(0, range.length), max(0, length - boundedLocation))
        return NSRange(location: boundedLocation, length: boundedLength)
    }
}
