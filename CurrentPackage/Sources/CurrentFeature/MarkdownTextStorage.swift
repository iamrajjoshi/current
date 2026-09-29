import AppKit

final class MarkdownTextStorage: NSTextStorage, NSTextStorageDelegate {
    private let backingStore = NSMutableAttributedString()
    private let highlighter: MarkdownSyntaxHighlighter
    private let renderPlans = MarkdownRenderPlanCache()
    private var sourceSnapshot: String?
    private var lastAttributeRun: (range: NSRange, attributes: [NSAttributedString.Key: Any])?
    private var isApplyingDecorations = false
    private(set) var selectedRange: NSRange?
    private var cachedRenderModel: MarkdownEditorRenderModel?
    private var cachedStreamLinks: [MarkdownStreamLinks.Link]?
    private var pendingDecorationRange: NSRange?
    private var hasPendingCharacterEdit = false
    private(set) var isProcessingEdit = false
    private(set) var sourceRevision = 0
    private(set) var decorationRevision = 0
    private var decoratedSourceRevision = -1
    private(set) var parseCount = 0
    var renderPlanBuildCount: Int { renderPlans.buildCount }
    var renderPlanReuseCount: Int { renderPlans.reuseCount }
    var styledLineCount: Int { renderPlans.styledLineCount }

    var renderModel: MarkdownEditorRenderModel {
        if let cachedRenderModel { return cachedRenderModel }
        let model = MarkdownEditorRenderModel(text: string)
        cachedRenderModel = model
        parseCount += 1
        return model
    }

    var renderWidth: CGFloat = 700 {
        didSet { if abs(renderWidth - oldValue) > 0.5, !renderModel.richBlocks.isEmpty { invalidateRenderPlans() } }
    }
    var documentURL: URL? {
        didSet { if documentURL != oldValue, !renderModel.richBlocks.isEmpty { invalidateRenderPlans() } }
    }
    var streamLinkTargets: [MarkdownStreamLinkTarget] = [] {
        didSet {
            guard streamLinkTargets != oldValue else { return }
            cachedStreamLinks = nil
            invalidateRenderPlans()
        }
    }

    var resolvedStreamLinks: [MarkdownStreamLinks.Link] {
        if let cachedStreamLinks { return cachedStreamLinks }
        guard !streamLinkTargets.isEmpty, string.contains("[[") else {
            cachedStreamLinks = []
            return []
        }
        let links = MarkdownStreamLinks.resolvedLinks(in: string, targets: streamLinkTargets,
                                                      protectedRanges: streamLinkProtectedRanges)
        cachedStreamLinks = links
        return links
    }

    func streamLinkCompletion(at selection: NSRange) -> MarkdownStreamLinks.Completion? {
        guard !streamLinkTargets.isEmpty, !suspendsDecorations, string.contains("[[") else { return nil }
        return MarkdownStreamLinks.completion(in: string, selection: selection, targets: streamLinkTargets,
                                              protectedRanges: streamLinkProtectedRanges)
    }

    private var streamLinkProtectedRanges: [NSRange] {
        let model = renderModel
        return model.protectedRanges + model.inlineSpans.filter { $0.kind == .inlineCode }.map(\.fullRange)
    }
    var onAsyncLayoutChange: (() -> Void)?

    private func configureObservers() {
        delegate = self
        NotificationCenter.default.addObserver(self, selector: #selector(imagesDidLoad), name: MarkdownRichBlocks.imagesDidLoad, object: nil)
    }

    @objc private func imagesDidLoad(_ notification: Notification) {
        guard !sourceMode, !suspendsDecorations, cachedRenderModel?.richBlocks.isEmpty == false else { return }
        invalidateRenderPlans()
        onAsyncLayoutChange?()
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    var sourceMode = false {
        didSet { if sourceMode != oldValue { invalidateRenderPlans() } }
    }

    /// Native marked text and drag selection own their geometry until committed.
    var suspendsDecorations = false {
        didSet {
            if oldValue && !suspendsDecorations { applyDecorations() }
        }
    }

    var configuration: CurrentConfiguration {
        didSet {
            highlighter.update(configuration: configuration)
            invalidateRenderPlans()
        }
    }

    init(string: String = "", configuration: CurrentConfiguration = .default) {
        self.configuration = configuration
        self.highlighter = MarkdownSyntaxHighlighter(configuration: configuration)
        super.init()
        configureObservers()
        backingStore.setAttributedString(NSAttributedString(string: string))
        applyDecorations()
    }

    required init?(coder: NSCoder) {
        self.configuration = .default
        self.highlighter = MarkdownSyntaxHighlighter(configuration: .default)
        super.init(coder: coder)
        configureObservers()
    }

    required init?(
        pasteboardPropertyList propertyList: Any,
        ofType type: NSPasteboard.PasteboardType
    ) {
        self.configuration = .default
        self.highlighter = MarkdownSyntaxHighlighter(configuration: .default)
        super.init()
        configureObservers()
        if let string = propertyList as? String {
            backingStore.setAttributedString(NSAttributedString(string: string))
            applyDecorations()
        }
    }

    required init(itemProviderData data: Data, typeIdentifier: String) throws {
        self.configuration = .default
        self.highlighter = MarkdownSyntaxHighlighter(configuration: .default)
        super.init()
        configureObservers()
        if let string = String(data: data, encoding: .utf8) {
            backingStore.setAttributedString(NSAttributedString(string: string))
            applyDecorations()
        }
    }

    override var string: String {
        if let sourceSnapshot { return sourceSnapshot }
        let snapshot = backingStore.string
        sourceSnapshot = snapshot
        return snapshot
    }

    // NSTextStorage's default length implementation asks for string, which
    // repeatedly bridges the full backing string during native glyph layout.
    override var length: Int { backingStore.length }

    // Native layout frequently asks for one attribute. The inherited method
    // would call our full Swift dictionary primitive and bridge every entry
    // back to Objective-C for each query.
    override func attribute(_ attrName: NSAttributedString.Key, at location: Int,
                            effectiveRange range: NSRangePointer?) -> Any? {
        backingStore.attribute(attrName, at: location, effectiveRange: range)
    }

    override func attribute(_ attrName: NSAttributedString.Key, at location: Int,
                            longestEffectiveRange range: NSRangePointer?, in rangeLimit: NSRange) -> Any? {
        backingStore.attribute(attrName, at: location, longestEffectiveRange: range, in: rangeLimit)
    }

    override func attributes(
        at location: Int,
        effectiveRange range: NSRangePointer?
    ) -> [NSAttributedString.Key: Any] {
        if let run = lastAttributeRun, NSLocationInRange(location, run.range) {
            range?.pointee = run.range
            return run.attributes
        }
        var effectiveRange = NSRange()
        let attributes = backingStore.attributes(at: location, effectiveRange: &effectiveRange)
        lastAttributeRun = (effectiveRange, attributes)
        range?.pointee = effectiveRange
        return attributes
    }

    override func attributes(
        at location: Int,
        longestEffectiveRange range: NSRangePointer?,
        in rangeLimit: NSRange
    ) -> [NSAttributedString.Key: Any] {
        backingStore.attributes(at: location, longestEffectiveRange: range, in: rangeLimit)
    }

    override func replaceCharacters(in range: NSRange, with string: String) {
        let delta = (string as NSString).length - range.length
        if !suspendsDecorations && !hasPendingCharacterEdit {
            let oldRange = renderModel.decorationRange(around: range)
            // This old block may no longer exist after deleting its opening fence.
            // Carry its extent into the new source coordinates before discarding it.
            let end = max(NSMaxRange(oldRange) + delta, oldRange.location)
            pendingDecorationRange = NSRange(location: min(oldRange.location, range.location), length: max(0, end - min(oldRange.location, range.location)))
        } else {
            pendingDecorationRange = nil // compound changes get a complete plan
        }
        hasPendingCharacterEdit = true
        lastAttributeRun = nil
        renderPlans.replaceCharacters(in: range, with: string)
        backingStore.replaceCharacters(in: range, with: string)
        sourceSnapshot = nil
        cachedRenderModel = nil
        cachedStreamLinks = nil
        sourceRevision += 1
        edited(.editedCharacters, range: range, changeInLength: delta)
    }

    override func setAttributes(_ attrs: [NSAttributedString.Key: Any]?, range: NSRange) {
        lastAttributeRun = nil
        backingStore.setAttributes(attrs, range: range)
        edited(.editedAttributes, range: range, changeInLength: 0)
    }

    override func addAttributes(_ attrs: [NSAttributedString.Key: Any], range: NSRange) {
        lastAttributeRun = nil
        backingStore.addAttributes(attrs, range: range)
        edited(.editedAttributes, range: range, changeInLength: 0)
    }

    override func addAttribute(_ name: NSAttributedString.Key, value: Any, range: NSRange) {
        lastAttributeRun = nil
        backingStore.addAttribute(name, value: value, range: range)
        edited(.editedAttributes, range: range, changeInLength: 0)
    }

    override func removeAttribute(_ name: NSAttributedString.Key, range: NSRange) {
        lastAttributeRun = nil
        backingStore.removeAttribute(name, range: range)
        edited(.editedAttributes, range: range, changeInLength: 0)
    }

    override func processEditing() {
        let wasProcessing = isProcessingEdit
        isProcessingEdit = true
        defer {
            isProcessingEdit = wasProcessing
            hasPendingCharacterEdit = false
            pendingDecorationRange = nil
        }
        super.processEditing()
    }

    func textStorage(_ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions,
                     range changedRange: NSRange, changeInLength delta: Int) {
        // This callback runs after native attribute fixing but before layout
        // notification, preserving AppKit's original character edit range.
        // Styling before processEditing widens that range and moves the caret;
        // styling after it leaves glyphs cached with the insertion font.
        guard editedMask.contains(.editedCharacters), !isApplyingDecorations else { return }
        guard !suspendsDecorations else { return }
        if length == 0 { applyDecorations(); return }
        let fullRange = NSRange(location: 0, length: length)
        // Expand again in the new tree after including the old block. A removed
        // opener can turn its old closing fence into a new opener farther down.
        let target = pendingDecorationRange.map {
            renderModel.decorationRange(around: NSIntersectionRange(NSUnionRange($0, changedRange), fullRange))
        } ?? fullRange
        decorate(target)
    }

    func applyDecorations() {
        decorate(NSRange(location: 0, length: length))
    }

    private func invalidateRenderPlans() {
        renderPlans.invalidate()
        applyDecorations()
    }

    func applyDecorations(around editedRange: NSRange?) {
        decorate(editedRange.map { renderModel.decorationRange(around: $0) } ?? NSRange(location: 0, length: length))
    }

    private func decorate(_ range: NSRange) {
        guard !isApplyingDecorations, !suspendsDecorations else { return }
        if length == 0 {
            if decoratedSourceRevision != sourceRevision { decorationRevision += 1 }
            decoratedSourceRevision = sourceRevision
            return
        }
        guard range.length > 0 else { return }
        isApplyingDecorations = true
        let changedLines = renderPlans.apply(to: self, in: range, highlighter: highlighter)
        // Plain text can wrap differently without changing a single attribute.
        if changedLines > 0 || decoratedSourceRevision != sourceRevision { decorationRevision += 1 }
        decoratedSourceRevision = sourceRevision
        isApplyingDecorations = false
    }

    func updateSelectedRange(_ range: NSRange?) {
        let next = boundedSelection(range)
        guard next != selectedRange else { return }
        let previous = selectedRange
        selectedRange = next
        guard !sourceMode, !suspendsDecorations, length > 0 else { return }
        let model = renderModel
        let oldBlocks = model.liveBlocks(intersecting: previous).map(\.lineRange)
        let newBlocks = model.liveBlocks(intersecting: next).map(\.lineRange)
        guard oldBlocks != newBlocks else { return }
        // A distant click should only restyle the departed and entered blocks.
        var ranges: [NSRange] = []
        for range in (oldBlocks + newBlocks).sorted(by: { $0.location < $1.location }) where range.length > 0 {
            if let last = ranges.last, NSMaxRange(last) >= range.location {
                ranges[ranges.count - 1] = NSUnionRange(last, range)
            } else { ranges.append(range) }
        }
        for range in ranges { decorate(range) }
    }

    func syntaxRangeIsRevealed(_ range: NSRange) -> Bool {
        sourceMode || MarkdownLiveRenderPolicy(model: renderModel, selectedRange: selectedRange).syntaxVisibility(for: range) == .revealed
    }

    func horizontalRuleIsActive(_ horizontalRule: MarkdownBlockRendering.HorizontalRuleLine) -> Bool {
        sourceMode || MarkdownLiveRenderPolicy(model: renderModel, selectedRange: selectedRange).horizontalRuleIsActive(horizontalRule)
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
