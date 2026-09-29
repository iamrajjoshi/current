import AppKit
import SwiftUI

private final class TimelineScrollView: NSScrollView {
    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // AppKit otherwise chooses a mounted text view before its saved
        // selection and reading position have been restored.
        window?.initialFirstResponder = self
    }
}

struct TimelineCollectionView: NSViewRepresentable {
    var days: [DayDocument]
    var today: Date
    var activeDayID: String?
    var minimizedDayIDs: Set<String>
    var searchQuery: String
    var configuration: CurrentConfiguration
    var sourceMode: Bool = false
    var streamLinkTargets: [MarkdownStreamLinkTarget] = []
    var onOpenStream: (UUID) -> Void = { _ in }
    var canLoadOlderDays: Bool
    var topSpacerHeight: CGFloat
    var bottomSpacerHeight: CGFloat
    var scrollRequest: TimelineScrollRequest?
    var onFocus: (Date) -> Void
    var onChange: (Date, String) -> Void
    var onToggleMinimized: (Date) -> Void
    var onLoadOlder: () -> Void
    var onLoadNewer: () -> Void
    var viewState = StreamViewState()
    var onViewStateChange: (StreamViewState) -> Void = { _ in }
    var onSaveWorkspace: () -> Void = {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = TimelineScrollView()
        scrollView.drawsBackground = false
        scrollView.backgroundColor = CurrentTheme.pageBackgroundColor
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = false
        scrollView.scrollerStyle = .overlay
        scrollView.borderType = .noBorder
        scrollView.contentView.postsBoundsChangedNotifications = true
        scrollView.contentView.postsFrameChangedNotifications = true

        let layout = TimelineColumnLayout()

        let collectionView = NSCollectionView()
        collectionView.collectionViewLayout = layout
        collectionView.dataSource = context.coordinator
        collectionView.delegate = context.coordinator
        collectionView.backgroundColors = [CurrentTheme.pageBackgroundColor]
        collectionView.frame = NSRect(
            origin: .zero,
            size: NSSize(width: max(1, scrollView.contentSize.width), height: max(1, scrollView.contentSize.height))
        )
        collectionView.isSelectable = false
        collectionView.alphaValue = 0
        collectionView.allowsMultipleSelection = false
        collectionView.autoresizingMask = [.width]
        collectionView.register(
            TimelineDayCollectionItem.self,
            forItemWithIdentifier: TimelineDayCollectionItem.reuseIdentifier
        )
        collectionView.register(
            TimelineSpacerCollectionItem.self,
            forItemWithIdentifier: TimelineSpacerCollectionItem.reuseIdentifier
        )
        collectionView.register(TimelineEmptyDaysCollectionItem.self,
                                forItemWithIdentifier: TimelineEmptyDaysCollectionItem.reuseIdentifier)

        scrollView.documentView = collectionView

        context.coordinator.scrollView = scrollView
        context.coordinator.collectionView = collectionView
        var initial = self
        if let key = viewState.scrollDayKey,
           let day = days.first(where: { $0.dayKey == key }), var request = scrollRequest {
            // onAppear runs after native view creation. A reopened window must
            // not execute the controller's stale jump while waiting for it.
            request.target = .searchMatch(day.id)
            request.offset = viewState.scrollOffset
            request.readingAnchor = viewState.readingAnchor
            request.selectionRange = NSRange(location: max(0, viewState.selectionLocation), length: max(0, viewState.selectionLength))
            request.shouldFocusEditor = viewState.editorHadFocus == true && viewState.dayKey == key
            initial.scrollRequest = request
        }
        context.coordinator.apply(initial, animated: false)
        context.coordinator.startObservingBoundsChanges()

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.scheduleApply(self)
    }

    static func dismantleNSView(_ scrollView: NSScrollView, coordinator: Coordinator) {
        coordinator.captureFinalPosition(saveNotes: false)
        coordinator.stopObservingBoundsChanges()
    }
}

public enum TimelineRowHeightCalculator {
    public static let collapsedEmptyDayHeight: CGFloat = 36
    public static let todayEmptyEditorMinimumHeight: CGFloat = 48
    public static let expandedEditorMinimumHeight: CGFloat = 48

    public static func height(
        for document: DayDocument,
        isToday: Bool,
        isActive: Bool = false,
        isMinimized: Bool = false,
        width: CGFloat = 700,
        configuration: CurrentConfiguration = .default,
        sourceMode: Bool = false
    ) -> CGFloat {
        if isMinimized && !isToday {
            return collapsedEmptyDayHeight
        }

        let hasText = MarkdownBlockRendering.hasRenderedContent(in: document.text)
        guard isToday || isActive || hasText else {
            return collapsedEmptyDayHeight
        }

        let editorWidth = max(1, width)
        let minimumEditorHeight = isToday ? todayEmptyEditorMinimumHeight : expandedEditorMinimumHeight
        let editorHeight = measuredEditorHeight(
            text: document.text,
            width: editorWidth,
            minimumHeight: minimumEditorHeight,
            configuration: configuration,
            sourceMode: sourceMode,
            isActive: isActive,
            documentURL: document.fileURL
        )

        return ceil(
            CurrentTheme.daySectionVerticalPaddingExpanded * 2
            + CurrentTheme.dayDividerIntrinsicHeight
            + CurrentTheme.dayEditorTopPadding
            + editorHeight
        )
    }

    public static func measuredEditorHeight(
        text: String,
        width: CGFloat = 700,
        minimumHeight: CGFloat = expandedEditorMinimumHeight,
        configuration: CurrentConfiguration = .default,
        sourceMode: Bool = false,
        isActive: Bool = false,
        documentURL: URL? = nil
    ) -> CGFloat {
        MarkdownTextLayoutMeasurer.measuredHeight(
            text: text,
            width: width,
            minimumHeight: minimumHeight,
            configuration: configuration,
            sourceMode: sourceMode,
            isActive: isActive,
            documentURL: documentURL
        )
    }
}

enum TimelineDayPresentation {
    static func isEffectivelyMinimized(
        document: DayDocument,
        isToday: Bool,
        minimizedDayIDs: Set<String>,
        searchQuery: String
    ) -> Bool {
        guard !isToday, minimizedDayIDs.contains(document.id) else { return false }

        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return true }
        return !document.text.localizedStandardContains(query)
    }
}

public enum TimelineLayoutMetrics {
    public static func itemWidth(
        availableWidth: CGFloat,
        configuration: CurrentConfiguration = .default
    ) -> CGFloat {
        min(
            CurrentTheme.contentMaxWidth(configuration: configuration),
            max(1, availableWidth - CurrentTheme.timelineHorizontalPadding * 2)
        )
    }

    public static func horizontalInset(
        availableWidth: CGFloat,
        configuration: CurrentConfiguration = .default
    ) -> CGFloat {
        let width = itemWidth(availableWidth: max(1, availableWidth), configuration: configuration)
        return max(
            0,
            floor((max(1, availableWidth) - width) / 2)
        )
    }

    public static func sectionInset(
        availableWidth: CGFloat,
        configuration: CurrentConfiguration = .default
    ) -> NSEdgeInsets {
        let horizontalInset = horizontalInset(availableWidth: availableWidth, configuration: configuration)
        return NSEdgeInsets(
            top: CurrentTheme.timelineTopPadding,
            left: horizontalInset,
            bottom: CurrentTheme.timelineBottomPadding,
            right: horizontalInset
        )
    }

    public static func minimumInteritemSpacing(
        availableWidth: CGFloat,
        configuration: CurrentConfiguration = .default
    ) -> CGFloat {
        max(1, availableWidth)
    }
}

// A timeline has one column. Keeping its geometry in one pass avoids the
// flow layout's independently cached item widths and section insets on resize.
@MainActor
final class TimelineColumnLayout: NSCollectionViewLayout {
    private var rowAttributes: [NSCollectionViewLayoutAttributes] = []
    private var contentSize = NSSize.zero
    private var needsPreparation = true

    override func invalidateLayout() {
        needsPreparation = true
        super.invalidateLayout()
    }

    override func invalidateLayout(with context: NSCollectionViewLayoutInvalidationContext) {
        needsPreparation = true
        super.invalidateLayout(with: context)
    }

    override func shouldInvalidateLayout(forBoundsChange newBounds: NSRect) -> Bool {
        abs(newBounds.width - (collectionView?.bounds.width ?? 0)) > 0.5
    }

    override func prepare() {
        super.prepare()
        guard needsPreparation, let collectionView,
              let delegate = collectionView.delegate as? NSCollectionViewDelegateFlowLayout else { return }
        needsPreparation = false
        let width = max(1, collectionView.bounds.width)
        if abs(width - contentSize.width) > 0.5, !rowAttributes.isEmpty {
            (collectionView.delegate as? TimelineCollectionView.Coordinator)?.willReflow(rows: rowAttributes)
        }
        let inset = delegate.collectionView?(collectionView, layout: self, insetForSectionAt: 0) ?? NSEdgeInsets()
        var y = inset.top
        rowAttributes.removeAll(keepingCapacity: true)
        for item in 0..<collectionView.numberOfItems(inSection: 0) {
            let path = IndexPath(item: item, section: 0)
            let size = delegate.collectionView?(collectionView, layout: self, sizeForItemAt: path) ?? .zero
            let attributes = NSCollectionViewLayoutAttributes(forItemWith: path)
            attributes.frame = NSRect(x: inset.left, y: y, width: min(size.width, width), height: max(0, size.height))
            rowAttributes.append(attributes)
            y += attributes.frame.height
        }
        contentSize = NSSize(width: width, height: y + inset.bottom)
    }

    override var collectionViewContentSize: NSSize { contentSize }

    override func layoutAttributesForElements(in rect: NSRect) -> [NSCollectionViewLayoutAttributes] {
        rowAttributes.filter { $0.frame.intersects(rect) }
    }

    override func layoutAttributesForItem(at indexPath: IndexPath) -> NSCollectionViewLayoutAttributes? {
        guard indexPath.section == 0, rowAttributes.indices.contains(indexPath.item) else { return nil }
        return rowAttributes[indexPath.item]
    }
}

enum TimelineCollectionItem: Equatable {
    case topSpacer(CGFloat)
    case day(DayDocument)
    case emptyDays(TimelineEmptyDayGroup)
    case bottomSpacer(CGFloat)

    var identity: String {
        switch self {
        case .topSpacer:
            return "spacer.top"
        case .day(let document):
            return document.id
        case .emptyDays(let group):
            return group.id
        case .bottomSpacer:
            return "spacer.bottom"
        }
    }

    var dayID: String? {
        switch self {
        case .day(let document): return document.id
        case .emptyDays(let group): return group.days.first?.id
        default: return nil
        }
    }

    func contains(dayID: String) -> Bool {
        switch self {
        case .day(let document): return document.id == dayID
        case .emptyDays(let group): return !group.isExpanded && group.days.contains { $0.id == dayID }
        default: return false
        }
    }
}

extension TimelineCollectionView {
    @MainActor
    final class Coordinator: NSObject, NSCollectionViewDataSource, NSCollectionViewDelegateFlowLayout {
        var parent: TimelineCollectionView
        weak var scrollView: NSScrollView?
        weak var collectionView: NSCollectionView?
        private var items: [TimelineCollectionItem] = []
        private var handledScrollRequestID: UUID?
        private var lastSearchQuery = ""
        private var isApplyingSnapshot = false
        private var didCaptureWindowClose = false
        private var isLoadingOlder = false
        private var isLoadingNewer = false
        private var lastRequestedOlderBoundaryID: String?
        private var lastRequestedNewerBoundaryID: String?
        private var lastViewportWidth: CGFloat = 0
        private var pendingMinimizedToggleAnchor: ScrollAnchor?
        private var pendingEditorLayout = false
        private var hasAppliedSnapshot = false
        private var pendingSnapshot: TimelineCollectionView?
        private var scheduledSnapshot: TimelineCollectionView?
        private var updateScheduled = false
        private var pendingReflowAnchor: ScrollAnchor?
        private var pendingCaretRestore: MarkdownEditorCaretAnchor?
        private var expandedEmptyDayIDs: Set<String> = []
        private var emptySpacerLedger = TimelineEmptyDaySpacerLedger()
        private var pendingWorkspaceRestore: TimelineScrollRequest?
        private var restoredSelectionRequestID: UUID?
        private var lastStableAnchor: ScrollAnchor?
        private var isRestoringWorkspace = false
        private var pendingReadingRestore: (anchor: ScrollAnchor, requestID: UUID?)?

        init(_ parent: TimelineCollectionView) {
            self.parent = parent
            self.items = Self.items(from: parent, expandedEmptyDayIDs: [], top: parent.topSpacerHeight, bottom: parent.bottomSpacerHeight)
            self.lastSearchQuery = parent.searchQuery
        }

        func startObservingBoundsChanges() {
            guard let clipView = scrollView?.contentView else { return }
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(viewportDidChange(_:)),
                name: NSView.boundsDidChangeNotification,
                object: clipView
            )
            NotificationCenter.default.addObserver(self, selector: #selector(editorHeightChanged(_:)),
                name: Notification.Name("Current.editorHeightChanged"), object: nil)
            NotificationCenter.default.addObserver(self, selector: #selector(editorSelectionChanged(_:)),
                name: NSTextView.didChangeSelectionNotification, object: nil)
            NotificationCenter.default.addObserver(self, selector: #selector(editorLayoutSettled(_:)),
                name: Notification.Name("Current.editorLayoutSettled"), object: nil)
            NotificationCenter.default.addObserver(self, selector: #selector(captureWorkspacePosition(_:)),
                name: .captureCurrentWorkspacePosition, object: nil)
            NotificationCenter.default.addObserver(self, selector: #selector(windowWillClose(_:)),
                name: NSWindow.willCloseNotification, object: nil)
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(viewportDidChange(_:)),
                name: NSView.frameDidChangeNotification,
                object: clipView
            )
        }

        func stopObservingBoundsChanges() {
            NotificationCenter.default.removeObserver(self)
        }

        func captureFinalPosition(saveNotes: Bool = true) {
            guard !didCaptureWindowClose else { return }
            publishViewState()
            if saveNotes { parent.onSaveWorkspace() }
        }

        @objc private func captureWorkspacePosition(_ notification: Notification) {
            publishViewState()
        }

        @objc private func windowWillClose(_ notification: Notification) {
            guard let window = notification.object as? NSWindow, window === scrollView?.window else { return }
            captureFinalPosition()
            didCaptureWindowClose = true
        }

        @objc private func editorLayoutSettled(_ notification: Notification) {
            guard let editor = notification.object as? MarkdownTextView,
                  let collectionView, editor.isDescendant(of: collectionView) else { return }
            finishWorkspaceRestoreIfReady()
            finishReadingRestoreIfReady()
            // A reused editor may reject focus while its newly mounted frame
            // still differs from its measured geometry. Retry the saved caret
            // only after that frame is ready, including equal-height reflows.
            if pendingWorkspaceRestore == nil { restorePendingCaret() }
            publishViewState()
        }

        func scheduleApply(_ nextParent: TimelineCollectionView) {
            scheduledSnapshot = nextParent
            guard !updateScheduled else { return }
            updateScheduled = true
            // Reusing collection items asks SwiftUI hosting views for their
            // responder nodes. Do that after the current SwiftUI update ends.
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.updateScheduled = false
                guard let next = self.scheduledSnapshot else { return }
                self.scheduledSnapshot = nil
                self.apply(next, animated: false)
            }
        }

        func apply(_ nextParent: TimelineCollectionView, animated: Bool) {
            guard let collectionView else { return }
            guard !isApplyingSnapshot else { pendingSnapshot = nextParent; return }
            syncCollectionViewFrame()

            let newScrollRequest = nextParent.scrollRequest?.id != parent.scrollRequest?.id
            if nextParent.days.last?.id != parent.days.last?.id || newScrollRequest
                || (!parent.canLoadOlderDays && nextParent.canLoadOlderDays) {
                lastRequestedOlderBoundaryID = nil
            }
            if nextParent.days.first?.id != parent.days.first?.id || newScrollRequest {
                lastRequestedNewerBoundaryID = nil
            }
            let adjustedSpacers = emptySpacerLedger.heights(previous: items, days: nextParent.days,
                                                            top: nextParent.topSpacerHeight, bottom: nextParent.bottomSpacerHeight)
            let nextItems = Self.items(from: nextParent, expandedEmptyDayIDs: expandedEmptyDayIDs,
                                       top: adjustedSpacers.top, bottom: adjustedSpacers.bottom)
            let previousIdentities = items.map(\.identity)
            let nextIdentities = nextItems.map(\.identity)
            let structureChanged = nextItems.map(\.identity) != items.map(\.identity)
            let contentChanged = nextItems != items
            let spacerChanged = abs(nextParent.topSpacerHeight - parent.topSpacerHeight) > 0.5
                || abs(nextParent.bottomSpacerHeight - parent.bottomSpacerHeight) > 0.5
            let searchChanged = nextParent.searchQuery != lastSearchQuery
            let activeDayChanged = nextParent.activeDayID != parent.activeDayID
            let minimizedChanged = nextParent.minimizedDayIDs != parent.minimizedDayIDs
            let focusIntentChanged = nextParent.scrollRequest?.shouldFocusEditor != parent.scrollRequest?.shouldFocusEditor
            let configurationChanged = nextParent.configuration != parent.configuration || nextParent.sourceMode != parent.sourceMode
                || nextParent.streamLinkTargets != parent.streamLinkTargets
            let todayChanged = nextParent.today != parent.today
            if hasAppliedSnapshot && !contentChanged && !searchChanged && !activeDayChanged
                && !minimizedChanged && !configurationChanged && !todayChanged && !focusIntentChanged {
                parent = nextParent
                handleExplicitScrollRequestIfNeeded()
                return
            }
            let contentOnlyChanged = contentChanged
                && !structureChanged
                && !spacerChanged
                && !searchChanged
                && !activeDayChanged
                && !minimizedChanged
                && !configurationChanged
                && !focusIntentChanged
                && !todayChanged
            let activeOnlyChanged = activeDayChanged
                && !structureChanged
                && !contentChanged
                && !spacerChanged
                && !searchChanged
                && !minimizedChanged
                && !configurationChanged
                && !focusIntentChanged
                && !todayChanged
            let presentationChanged = minimizedChanged || searchChanged || activeDayChanged || configurationChanged || todayChanged || focusIntentChanged
            let layoutStateChanged = minimizedChanged || searchChanged
            let preferredAnchor = minimizedChanged ? pendingMinimizedToggleAnchor : nil
            let anchor = structureChanged || spacerChanged || layoutStateChanged || configurationChanged
                ? preferredAnchor ?? captureFirstVisibleDayAnchor(preferring: Set(nextParent.days.map(\.id)))
                : nil
            let previousActiveDayID = parent.activeDayID
            let nextActiveDayID = nextParent.activeDayID
            let contentChangedDayIDs = contentOnlyChanged
                ? changedDayIDs(from: items, to: nextItems)
                : []
            let contentChangeAffectsRowHeight = contentOnlyChanged
                && dayHeightChanged(
                    dayIDs: contentChangedDayIDs,
                    from: parent,
                    to: nextParent
                )
            let caretAnchor = contentChangeAffectsRowHeight || configurationChanged ? captureActiveEditorCaretAnchor(visibleOnly: configurationChanged) : nil
            if minimizedChanged {
                pendingMinimizedToggleAnchor = nil
            }

            parent = nextParent
            isApplyingSnapshot = true
            items = nextItems

            if structureChanged || spacerChanged {
                if structureChanged && !Set(previousIdentities).isDisjoint(with: nextIdentities) {
                    let difference = nextIdentities.difference(from: previousIdentities)
                    let removed = Set(difference.removals.map { change -> IndexPath in
                        guard case .remove(let offset, _, _) = change else { preconditionFailure() }
                        return IndexPath(item: offset, section: 0)
                    })
                    let inserted = Set(difference.insertions.map { change -> IndexPath in
                        guard case .insert(let offset, _, _) = change else { preconditionFailure() }
                        return IndexPath(item: offset, section: 0)
                    })
                    NSAnimationContext.runAnimationGroup { context in
                        context.duration = 0
                        context.allowsImplicitAnimation = false
                        collectionView.performBatchUpdates {
                            collectionView.deleteItems(at: removed)
                            collectionView.insertItems(at: inserted)
                        } completionHandler: { [weak self] _ in
                            guard let self else { return }
                            self.reconfigureVisibleDayItems(skipsActiveEditor: !presentationChanged)
                            collectionView.collectionViewLayout?.invalidateLayout()
                            collectionView.layoutSubtreeIfNeeded()
                            self.syncCollectionViewFrame()
                            if let anchor { self.restore(anchor, adjustsForReflow: configurationChanged) }
                            if configurationChanged { self.restoreAfterReflow(caretAnchor) }
                            self.lastSearchQuery = self.parent.searchQuery
                            self.handleExplicitScrollRequestIfNeeded()
                            self.finishSnapshot()
                        }
                    }
                    return
                }
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0
                    context.allowsImplicitAnimation = false
                    if structureChanged {
                        collectionView.reloadData()
                    } else {
                        reconfigureVisibleDayItems(skipsActiveEditor: !presentationChanged)
                    }
                    collectionView.collectionViewLayout?.invalidateLayout()
                    collectionView.layoutSubtreeIfNeeded()
                }
                syncCollectionViewFrame()
                if let anchor {
                    restore(anchor)
                }
            } else if contentOnlyChanged {
                reconfigureVisibleDayItems(matching: contentChangedDayIDs, skipsActiveEditor: true)
                if contentChangeAffectsRowHeight {
                    collectionView.collectionViewLayout?.invalidateLayout()
                    collectionView.layoutSubtreeIfNeeded()
                    syncCollectionViewFrame()
                    if let caretAnchor {
                        restore(caretAnchor)
                    }
                }
            } else if layoutStateChanged {
                reconfigureVisibleDayItems()
                collectionView.collectionViewLayout?.invalidateLayout()
                collectionView.layoutSubtreeIfNeeded()
                syncCollectionViewFrame()
                if let anchor {
                    restore(anchor)
                }
            } else if activeOnlyChanged {
                reconfigureVisibleDayItems(matching: Set([previousActiveDayID, nextActiveDayID].compactMap { $0 }))
                if activeChangeCanAffectRowHeight(previousActiveDayID, nextActiveDayID) {
                    collectionView.collectionViewLayout?.invalidateLayout()
                    collectionView.layoutSubtreeIfNeeded()
                    syncCollectionViewFrame()
                }
            } else {
                reconfigureVisibleDayItems()
                collectionView.collectionViewLayout?.invalidateLayout()
                collectionView.layoutSubtreeIfNeeded()
                syncCollectionViewFrame()
            }

            if searchChanged {
                lastSearchQuery = nextParent.searchQuery
            }

            if configurationChanged, let anchor {
                restore(anchor, adjustsForReflow: true)
                restoreAfterReflow(caretAnchor)
            }
            handleExplicitScrollRequestIfNeeded()
            finishSnapshot()
        }

        private func finishSnapshot() {
            isApplyingSnapshot = false
            hasAppliedSnapshot = true
            if let next = pendingSnapshot {
                pendingSnapshot = nil
                apply(next, animated: false)
            }
            finishWorkspaceRestoreIfReady()
            if parent.scrollRequest == nil { collectionView?.alphaValue = 1 }
        }

        private func changedDayIDs(from oldItems: [TimelineCollectionItem], to newItems: [TimelineCollectionItem]) -> Set<String> {
            let oldDays = Dictionary(uniqueKeysWithValues: oldItems.compactMap { item -> (String, DayDocument)? in
                guard case .day(let document) = item else { return nil }
                return (document.id, document)
            })
            let newDays = Dictionary(uniqueKeysWithValues: newItems.compactMap { item -> (String, DayDocument)? in
                guard case .day(let document) = item else { return nil }
                return (document.id, document)
            })

            return Set(newDays.compactMap { dayID, document in
                oldDays[dayID] == document ? nil : dayID
            })
        }

        private func dayHeightChanged(
            dayIDs: Set<String>,
            from oldParent: TimelineCollectionView,
            to newParent: TimelineCollectionView
        ) -> Bool {
            guard !dayIDs.isEmpty,
                  let collectionView else { return false }
            let width = itemWidth(in: collectionView)
            let oldDocuments = Dictionary(uniqueKeysWithValues: oldParent.days.map { ($0.id, $0) })
            let newDocuments = Dictionary(uniqueKeysWithValues: newParent.days.map { ($0.id, $0) })

            return dayIDs.contains { dayID in
                guard let oldDocument = oldDocuments[dayID],
                      let newDocument = newDocuments[dayID] else {
                    return true
                }

                let oldHeight = height(
                    for: oldDocument,
                    in: oldParent,
                    width: width
                )
                let newHeight = height(
                    for: newDocument,
                    in: newParent,
                    width: width
                )
                return abs(oldHeight - newHeight) > 0.5
            }
        }

        private func height(
            for document: DayDocument,
            in parent: TimelineCollectionView,
            width: CGFloat
        ) -> CGFloat {
            TimelineRowHeightCalculator.height(
                for: document,
                isToday: Calendar.current.isDate(document.date, inSameDayAs: parent.today),
                isActive: document.id == parent.activeDayID,
                isMinimized: TimelineDayPresentation.isEffectivelyMinimized(
                    document: document,
                    isToday: Calendar.current.isDate(document.date, inSameDayAs: parent.today),
                    minimizedDayIDs: parent.minimizedDayIDs,
                    searchQuery: parent.searchQuery
                ),
                width: width,
                configuration: parent.configuration,
                sourceMode: parent.sourceMode
            )
        }

        func collectionView(
            _ collectionView: NSCollectionView,
            numberOfItemsInSection section: Int
        ) -> Int {
            items.count
        }

        func collectionView(
            _ collectionView: NSCollectionView,
            itemForRepresentedObjectAt indexPath: IndexPath
        ) -> NSCollectionViewItem {
            switch items[indexPath.item] {
            case .topSpacer, .bottomSpacer:
                return collectionView.makeItem(
                    withIdentifier: TimelineSpacerCollectionItem.reuseIdentifier,
                    for: indexPath
                )
            case .emptyDays(let group):
                let item = collectionView.makeItem(withIdentifier: TimelineEmptyDaysCollectionItem.reuseIdentifier, for: indexPath)
                if let item = item as? TimelineEmptyDaysCollectionItem { configureEmptyDayItem(item, group: group) }
                return item
            case .day(let document):
                let item = collectionView.makeItem(
                    withIdentifier: TimelineDayCollectionItem.reuseIdentifier,
                    for: indexPath
                )
                guard let dayItem = item as? TimelineDayCollectionItem else {
                    return item
                }
                dayItem.configure(
                    document: document,
                    isToday: Calendar.current.isDate(document.date, inSameDayAs: parent.today),
                    isActive: document.id == parent.activeDayID,
                    isMinimized: effectiveIsMinimized(document),
                    searchQuery: parent.searchQuery,
                    configuration: parent.configuration,
                    sourceMode: parent.sourceMode,
                    allowsEditorFocus: parent.scrollRequest?.offset == nil && (parent.scrollRequest?.shouldFocusEditor ?? true),
                    streamLinkTargets: parent.streamLinkTargets,
                    onOpenStream: parent.onOpenStream,
                    onFocus: parent.onFocus,
                    onChange: parent.onChange,
                    onToggleMinimized: { [weak self] date, dayID in
                        self?.toggleMinimized(for: date, dayID: dayID)
                    }
                )
                return dayItem
            }
        }

        func collectionView(
            _ collectionView: NSCollectionView,
            layout collectionViewLayout: NSCollectionViewLayout,
            sizeForItemAt indexPath: IndexPath
        ) -> NSSize {
            let width = itemWidth(in: collectionView)
            switch items[indexPath.item] {
            case .topSpacer(let height), .bottomSpacer(let height):
                return NSSize(width: width, height: max(0, height))
            case .emptyDays:
                return NSSize(width: width, height: TimelineHistoryPresentation.emptyGroupHeight)
            case .day(let document):
                let height = TimelineRowHeightCalculator.height(
                    for: document,
                    isToday: Calendar.current.isDate(document.date, inSameDayAs: parent.today),
                    isActive: document.id == parent.activeDayID,
                    isMinimized: effectiveIsMinimized(document),
                    width: width,
                    configuration: parent.configuration,
                    sourceMode: parent.sourceMode
                )
                return NSSize(width: width, height: height)
            }
        }

        func collectionView(
            _ collectionView: NSCollectionView,
            layout collectionViewLayout: NSCollectionViewLayout,
            insetForSectionAt section: Int
        ) -> NSEdgeInsets {
            TimelineLayoutMetrics.sectionInset(
                availableWidth: viewportWidth(in: collectionView),
                configuration: parent.configuration
            )
        }

        func collectionView(
            _ collectionView: NSCollectionView,
            layout collectionViewLayout: NSCollectionViewLayout,
            minimumLineSpacingForSectionAt section: Int
        ) -> CGFloat {
            0
        }

        func collectionView(
            _ collectionView: NSCollectionView,
            layout collectionViewLayout: NSCollectionViewLayout,
            minimumInteritemSpacingForSectionAt section: Int
        ) -> CGFloat {
            TimelineLayoutMetrics.minimumInteritemSpacing(
                availableWidth: viewportWidth(in: collectionView),
                configuration: parent.configuration
            )
        }

        // AppKit can prepare the new width before posting the clip-view
        // notification. Capture from the old frames before they are replaced.
        func willReflow(rows: [NSCollectionViewLayoutAttributes]) {
            guard pendingReflowAnchor == nil, pendingWorkspaceRestore == nil,
                  parent.scrollRequest == nil || parent.scrollRequest?.id == handledScrollRequestID,
                  let scrollView else { return }
            let visible = scrollView.contentView.bounds
            guard visible.height > 0,
                  let row = rows.first(where: { row in
                      guard let index = row.indexPath?.item else { return false }
                      return row.frame.intersects(visible) && items.indices.contains(index) && items[index].dayID != nil
                  }), let index = row.indexPath?.item, let dayID = items[index].dayID else { return }
            let anchor = ScrollAnchor(dayID: dayID, offsetFromVisibleTop: visible.minY - row.frame.minY,
                                      rowHeight: row.frame.height, itemIdentity: items[index].identity,
                                      readingAnchor: lastStableAnchor?.dayID == dayID ? lastStableAnchor?.readingAnchor : nil)
            let caretAnchor = captureActiveEditorCaretAnchor(visibleOnly: true)
            let requestID = parent.scrollRequest?.id
            pendingReflowAnchor = anchor
            DispatchQueue.main.async { [weak self] in
                guard let self, self.pendingReflowAnchor != nil,
                      self.parent.scrollRequest?.id == requestID else { return }
                self.pendingReflowAnchor = nil
                self.restore(anchor, adjustsForReflow: true)
                self.restoreAfterReflow(caretAnchor)
                self.maybeLoadMore()
                self.publishViewState()
            }
        }

        @objc private func viewportDidChange(_ notification: Notification) {
            let widthChanged = recordViewportWidthChange()
            let anchor = widthChanged ? pendingReflowAnchor ?? captureFirstVisibleDayAnchor() : nil
            let caretAnchor = widthChanged ? captureActiveEditorCaretAnchor(visibleOnly: true) : nil
            syncCollectionViewFrame()
            if widthChanged {
                collectionView?.collectionViewLayout?.invalidateLayout()
                collectionView?.layoutSubtreeIfNeeded()
                syncCollectionViewFrame()
                reconfigureVisibleDayItems()
                if let anchor {
                    restore(anchor, adjustsForReflow: true)
                }
                restoreAfterReflow(caretAnchor)
            }
            handleExplicitScrollRequestIfNeeded()
            finishWorkspaceRestoreIfReady()
            maybeLoadMore()
            publishViewState()
        }

        @objc private func editorSelectionChanged(_ notification: Notification) {
            guard let textView = notification.object as? MarkdownTextView,
                  let collectionView, textView.isDescendant(of: collectionView) else { return }
            publishViewState()
        }

        @objc private func editorHeightChanged(_ notification: Notification) {
            guard let textView = notification.object as? MarkdownTextView,
                  let collectionView, textView.isDescendant(of: collectionView), !pendingEditorLayout else { return }
            pendingEditorLayout = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.pendingEditorLayout = false
                guard !self.isApplyingSnapshot else { return }
                let anchor = self.pendingWorkspaceRestore == nil ? self.captureActiveEditorCaretAnchor() : nil
                self.isApplyingSnapshot = true
                self.collectionView?.collectionViewLayout?.invalidateLayout()
                self.collectionView?.layoutSubtreeIfNeeded()
                self.syncCollectionViewFrame()
                if let anchor { self.restore(anchor) }
                self.restorePendingCaret()
                self.finishSnapshot()
                self.finishWorkspaceRestoreIfReady()
                self.publishViewState()
                DispatchQueue.main.async { [weak self] in
                    self?.restorePendingCaret()
                    self?.keepEditingCaretVisible()
                }
            }
        }

        private func keepEditingCaretVisible() {
            guard pendingWorkspaceRestore == nil, let collectionView, let scrollView,
                  let editor = MarkdownTextView.activeEditor,
                  editor.window?.firstResponder === editor,
                  editor.window?.attachedSheet == nil,
                  editor.currentDayID == parent.activeDayID,
                  editor.isDescendant(of: collectionView),
                  let y = caretY(in: collectionView, for: editor) else { return }
            let visible = scrollView.contentView.bounds
            let margin = CurrentTheme.editorLineHeight(configuration: parent.configuration) + 10
            if y > visible.maxY - margin {
                scroll(toY: y - visible.height + margin, in: scrollView, collectionView: collectionView)
            } else if y < visible.minY + 6 {
                scroll(toY: max(0, y - 6), in: scrollView, collectionView: collectionView)
            }
        }

        private func publishViewState() {
            guard !didCaptureWindowClose, !isApplyingSnapshot, pendingReflowAnchor == nil, pendingWorkspaceRestore == nil,
                  pendingReadingRestore == nil, pendingCaretRestore == nil,
                  parent.scrollRequest == nil || parent.scrollRequest?.id == handledScrollRequestID,
                  var anchor = captureFirstVisibleDayAnchor(),
                  let document = parent.days.first(where: { $0.id == anchor.dayID }) else { return }
            let textTop = CurrentTheme.daySectionVerticalPaddingExpanded
                + CurrentTheme.dayDividerIntrinsicHeight + CurrentTheme.dayEditorTopPadding
            if let readingEditor = editor(forDayID: anchor.dayID),
               !effectiveIsMinimized(document), anchor.offsetFromVisibleTop >= textTop,
               pendingEditorLayout || !readingEditor.isGeometrySettled {
                // Typing publishes selection before native layout finishes.
                // Closing in that interval must not erase the last source
                // anchor; the latest selection is still captured below.
                anchor.readingAnchor = lastStableAnchor?.dayID == anchor.dayID
                    ? lastStableAnchor?.readingAnchor : nil
                if anchor.readingAnchor == nil, parent.viewState.scrollDayKey == document.dayKey {
                    anchor.readingAnchor = parent.viewState.readingAnchor
                }
            } else {
                lastStableAnchor = anchor
            }
            let editor = MarkdownTextView.activeEditor
            let activeDocument = parent.days.first { $0.id == parent.activeDayID }
            let selection = editor?.currentDayID == parent.activeDayID ? editor?.selectedRange() : nil
            let state = StreamViewState(
                dayKey: activeDocument?.dayKey ?? parent.viewState.dayKey,
                scrollDayKey: document.dayKey,
                scrollOffset: Double(anchor.offsetFromVisibleTop),
                selectionLocation: selection?.location ?? parent.viewState.selectionLocation,
                selectionLength: selection?.length ?? parent.viewState.selectionLength,
                minimizedDayKeys: Set(parent.minimizedDayIDs.compactMap { $0.split(separator: "|").last.map(String.init) }),
                readingAnchor: anchor.readingAnchor,
                editorHadFocus: captureActiveEditorCaretAnchor(visibleOnly: true)?.wasFirstResponder == true
            )
            parent.onViewStateChange(state)
        }

        private func recordViewportWidthChange() -> Bool {
            let width = viewportWidth()
            guard lastViewportWidth > 0 else {
                lastViewportWidth = width
                return false
            }

            guard abs(width - lastViewportWidth) > 0.5 else {
                return false
            }

            lastViewportWidth = width
            return true
        }

        private func syncCollectionViewFrame() {
            guard let scrollView,
                  let collectionView else { return }
            let clipSize = scrollView.contentView.bounds.size
            let width = max(1, clipSize.width)
            if abs(collectionView.frame.width - width) > 0.5 {
                collectionView.setFrameSize(NSSize(width: width, height: collectionView.frame.height))
            }
            let contentSize = collectionView.collectionViewLayout?.collectionViewContentSize ?? clipSize
            if lastViewportWidth == 0 {
                lastViewportWidth = max(1, clipSize.width)
            }
            collectionView.frame = NSRect(
                x: 0,
                y: 0,
                width: width,
                height: max(1, clipSize.height, contentSize.height)
            )
        }

        private func maybeLoadMore() {
            guard !isApplyingSnapshot, pendingReflowAnchor == nil, pendingWorkspaceRestore == nil,
                  pendingReadingRestore == nil,
                  parent.scrollRequest == nil || parent.scrollRequest?.id == handledScrollRequestID,
                  let scrollView,
                  let collectionView else { return }

            let visibleRect = scrollView.contentView.bounds
            let contentHeight = max(collectionView.collectionViewLayout?.collectionViewContentSize.height ?? collectionView.bounds.height, collectionView.bounds.height)
            // The trailing spacer represents evicted rows. Page before reaching
            // it, rather than waiting for the far end of unloaded history.
            let oldestRowEnd = parent.days.last.flatMap { day in
                indexPath(forDayID: day.id).flatMap { collectionView.layoutAttributesForItem(at: $0)?.frame.maxY }
            } ?? contentHeight
            let distanceToBottom = oldestRowEnd - visibleRect.maxY

            if parent.canLoadOlderDays,
               distanceToBottom < CurrentTheme.historyPreloadDistance,
               let oldestID = parent.days.last?.id,
               oldestID != lastRequestedOlderBoundaryID,
               !isLoadingOlder {
                isLoadingOlder = true
                lastRequestedOlderBoundaryID = oldestID
                parent.onLoadOlder()
                DispatchQueue.main.async { [weak self] in
                    self?.isLoadingOlder = false
                    self?.maybeLoadMore()
                }
            }

            if parent.days.first.map({ $0.date < parent.today }) == true,
               let newestID = parent.days.first?.id,
               shouldLoadNewer(visibleRect: visibleRect, newestID: newestID),
               newestID != lastRequestedNewerBoundaryID,
               !isLoadingNewer {
                isLoadingNewer = true
                lastRequestedNewerBoundaryID = newestID
                parent.onLoadNewer()
                DispatchQueue.main.async { [weak self] in
                    self?.isLoadingNewer = false
                    self?.maybeLoadMore()
                }
            }
        }

        private func shouldLoadNewer(visibleRect: CGRect, newestID: String) -> Bool {
            guard let collectionView,
                  let indexPath = indexPath(forDayID: newestID),
                  let attributes = collectionView.layoutAttributesForItem(at: indexPath) else {
                return visibleRect.minY < CurrentTheme.historyPreloadDistance
            }

            return visibleRect.minY < attributes.frame.minY + CurrentTheme.historyPreloadDistance
        }

        private func captureFirstVisibleDayAnchor(preferring retainedIDs: Set<String>? = nil) -> ScrollAnchor? {
            guard let collectionView,
                  let scrollView else { return nil }

            let visibleRect = scrollView.contentView.bounds
            let visibleIndexPaths = collectionView.indexPathsForVisibleItems()
            let sortedIndexPaths = visibleIndexPaths.sorted { lhs, rhs in
                let lhsY = collectionView.layoutAttributesForItem(at: lhs)?.frame.minY ?? .greatestFiniteMagnitude
                let rhsY = collectionView.layoutAttributesForItem(at: rhs)?.frame.minY ?? .greatestFiniteMagnitude
                return lhsY < rhsY
            }

            for indexPath in sortedIndexPaths where indexPath.item < items.count {
                let item = items[indexPath.item]
                let dayID: String?
                if case .emptyDays(let group) = item, let retainedIDs {
                    dayID = group.days.first(where: { retainedIDs.contains($0.id) })?.id
                } else { dayID = item.dayID }
                guard let dayID, retainedIDs?.contains(dayID) != false,
                      let attributes = collectionView.layoutAttributesForItem(at: indexPath),
                      attributes.frame.intersects(visibleRect) else { continue }
                return ScrollAnchor(
                    dayID: dayID,
                    offsetFromVisibleTop: visibleRect.minY - attributes.frame.minY,
                    rowHeight: attributes.frame.height,
                    itemIdentity: item.identity,
                    readingAnchor: readingAnchor(forDayID: dayID)
                )
            }

            return nil
        }

        private func restore(_ anchor: ScrollAnchor, adjustsForReflow: Bool = false) {
            guard let collectionView,
                  let scrollView,
                  let indexPath = anchor.itemIdentity.flatMap({ identity in
                      items.firstIndex(where: { $0.identity == identity }).map { IndexPath(item: $0, section: 0) }
                  }) ?? indexPath(forDayID: anchor.dayID),
                  let attributes = collectionView.layoutAttributesForItem(at: indexPath) else { return }

            // An absolute offset can land in a different day when a tall note
            // contracts. Keep the same position within its new row until the
            // native editor finishes reflowing and can restore the exact caret.
            if adjustsForReflow, let reading = anchor.readingAnchor,
               let editor = editor(forDayID: anchor.dayID), editor.isGeometrySettled,
               let point = reading.lineOrigin(in: editor) {
                let y = editor.convert(point, to: collectionView).y + reading.lineOffset
                scroll(toY: y, in: scrollView, collectionView: collectionView)
                return
            }
            if adjustsForReflow, anchor.readingAnchor != nil {
                pendingReadingRestore = (anchor, parent.scrollRequest?.id)
            }
            let offset = adjustsForReflow && anchor.rowHeight > 0
                ? anchor.offsetFromVisibleTop * attributes.frame.height / anchor.rowHeight
                : anchor.offsetFromVisibleTop
            let targetY = attributes.frame.minY + offset
            scroll(toY: targetY, in: scrollView, collectionView: collectionView)
        }

        private func editor(forDayID dayID: String) -> MarkdownTextView? {
            guard let collectionView, let path = indexPath(forDayID: dayID),
                  let item = collectionView.item(at: path) else { return nil }
            func find(in view: NSView) -> MarkdownTextView? {
                if let editor = view as? MarkdownTextView, editor.currentDayID == dayID { return editor }
                return view.subviews.lazy.compactMap { find(in: $0) }.first
            }
            return find(in: item.view)
        }

        private func readingAnchor(forDayID dayID: String) -> MarkdownReadingAnchor? {
            guard let scrollView, let collectionView, let editor = editor(forDayID: dayID),
                  editor.isGeometrySettled else { return nil }
            let y = editor.convert(NSPoint(x: 0, y: scrollView.contentView.bounds.minY), from: collectionView).y
            guard y >= editor.textContainerOrigin.y else { return nil }
            return MarkdownReadingAnchor.capture(in: editor, readingY: y)
        }

        private func finishReadingRestoreIfReady() {
            guard !isApplyingSnapshot, pendingWorkspaceRestore == nil,
                  let pending = pendingReadingRestore, let collectionView, let scrollView else { return }
            guard pending.requestID == parent.scrollRequest?.id,
                  parent.days.contains(where: { $0.id == pending.anchor.dayID && !effectiveIsMinimized($0) }) else {
                pendingReadingRestore = nil
                return
            }
            guard let editor = editor(forDayID: pending.anchor.dayID), editor.isGeometrySettled,
                  let anchor = pending.anchor.readingAnchor, let point = anchor.lineOrigin(in: editor) else { return }
            pendingReadingRestore = nil
            scroll(toY: editor.convert(point, to: collectionView).y + anchor.lineOffset,
                   in: scrollView, collectionView: collectionView)
            publishViewState()
        }

        private func restoreAfterReflow(_ anchor: MarkdownEditorCaretAnchor?) {
            guard let anchor else { return }
            pendingReadingRestore = nil
            pendingCaretRestore = anchor
            DispatchQueue.main.async { [weak self] in self?.restorePendingCaret() }
        }

        private func restorePendingCaret() {
            guard let anchor = pendingCaretRestore else { return }
            guard parent.activeDayID == anchor.dayID else { pendingCaretRestore = nil; return }
            if restore(anchor) {
                pendingCaretRestore = nil
                keepEditingCaretVisible()
            }
        }

        private func captureActiveEditorCaretAnchor(visibleOnly: Bool = false) -> MarkdownEditorCaretAnchor? {
            guard let collectionView,
                  let scrollView,
                  let textView = MarkdownTextView.activeEditor,
                  textView.isDescendant(of: collectionView),
                  let caretY = caretY(in: collectionView, for: textView) else {
                return nil
            }

            if visibleOnly && (caretY < scrollView.contentView.bounds.minY || caretY > scrollView.contentView.bounds.maxY) {
                return nil
            }
            return MarkdownEditorCaretAnchor(
                dayID: textView.currentDayID,
                offsetFromVisibleTop: scrollView.contentView.bounds.minY - caretY,
                wasFirstResponder: textView.window?.firstResponder === textView
            )
        }

        @discardableResult
        private func restore(_ anchor: MarkdownEditorCaretAnchor) -> Bool {
            guard let collectionView,
                  let scrollView,
                  let textView = MarkdownTextView.activeEditor,
                  textView.currentDayID == anchor.dayID,
                  textView.isDescendant(of: collectionView),
                  !anchor.wasFirstResponder || textView.isGeometrySettled,
                  let caretY = caretY(in: collectionView, for: textView) else {
                return false
            }
            if anchor.wasFirstResponder, let window = textView.window,
               window.attachedSheet == nil,
               !((window.firstResponder as? NSTextView)?.isFieldEditor ?? false) {
                // AppKit can return true after the old responder resigns even
                // when this editor rejects focus and the window takes it.
                guard !textView.visibleRect.isEmpty, window.makeFirstResponder(textView),
                      window.firstResponder === textView else { return false }
            }
            let targetY = caretY + anchor.offsetFromVisibleTop
            scroll(toY: targetY, in: scrollView, collectionView: collectionView)
            return true
        }

        private func caretY(in collectionView: NSCollectionView, for textView: MarkdownTextView) -> CGFloat? {
            guard let y = MarkdownVisibleCaret.caretY(in: collectionView, for: textView),
                  let dayID = textView.currentDayID, let path = indexPath(forDayID: dayID),
                  let frame = collectionView.layoutAttributesForItem(at: path)?.frame,
                  y >= frame.minY, y <= frame.maxY else { return nil }
            // During reflow the native editor may still have its previous width.
            // Its stale caret must not scroll past the newly measured day row.
            return y
        }

        private func handleExplicitScrollRequestIfNeeded() {
            guard let request = parent.scrollRequest,
                  request.id != handledScrollRequestID,
                  let collectionView,
                  let scrollView, scrollView.contentSize.width > 1, scrollView.contentSize.height > 1,
                  let indexPath = indexPath(forDayID: request.dayID),
                  let attributes = collectionView.layoutAttributesForItem(at: indexPath) else { return }

            let viewportHeight = scrollView.contentView.bounds.height
            // A requested date or saved position supersedes reflow work that
            // was queued from the previous viewport before this request.
            pendingReflowAnchor = nil
            pendingCaretRestore = nil
            pendingReadingRestore = nil
            if request.offset != nil {
                pendingWorkspaceRestore = request
                collectionView.alphaValue = 0
                // Logical anchors need their row mounted before resolving a
                // source line. Older sessions only saved a pixel offset that
                // can legitimately extend beyond the named row.
                let offset = request.readingAnchor == nil ? request.offset ?? 0
                    : min(request.offset ?? 0, max(0, attributes.frame.height - 1))
                handledScrollRequestID = request.id
                scroll(toY: attributes.frame.minY + offset, in: scrollView, collectionView: collectionView)
                DispatchQueue.main.async { [weak self] in self?.finishWorkspaceRestoreIfReady() }
                return
            }
            pendingWorkspaceRestore = nil
            collectionView.alphaValue = 1
            let targetY = attributes.frame.minY + (request.offset ?? -viewportHeight * CurrentTheme.scrollTargetAnchorY)
            scroll(toY: targetY, in: scrollView, collectionView: collectionView)
            if case .today = request.target, request.shouldFocusEditor {
                DispatchQueue.main.async { [weak self] in
                    guard self?.parent.scrollRequest?.id == request.id,
                          self?.parent.scrollRequest?.shouldFocusEditor == true else { return }
                    MarkdownTextView.focusEditor(dayID: request.dayID)
                }
            } else {
                let focusID = request.offset == nil ? request.dayID : parent.activeDayID ?? request.dayID
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.parent.scrollRequest?.id == request.id,
                          let collectionView = self.collectionView else { return }
                    @MainActor func editor(in view: NSView) -> MarkdownTextView? {
                        if let editor = view as? MarkdownTextView, editor.currentDayID == focusID { return editor }
                        return view.subviews.lazy.compactMap { editor(in: $0) }.first
                    }
                    guard let editor = editor(in: collectionView) else { return }
                    let length = editor.string.utf16.count
                    if request.shouldFocusEditor, self.parent.scrollRequest?.shouldFocusEditor == true {
                        editor.window?.makeFirstResponder(editor)
                    }
                    if let selection = request.selectionRange {
                        let location = min(selection.location, length)
                        editor.setSelectedRange(NSRange(location: location, length: min(selection.length, length - location)))
                    }
                    if request.offset == nil { editor.scrollRangeToVisible(editor.selectedRange()) }
                    else if let scrollView = self.scrollView { self.scroll(toY: targetY, in: scrollView, collectionView: collectionView) }
                }
            }
            handledScrollRequestID = request.id
        }

        private func finishWorkspaceRestoreIfReady() {
            guard !isApplyingSnapshot, !isRestoringWorkspace, let request = pendingWorkspaceRestore,
                  let collectionView, let scrollView else { return }
            isRestoringWorkspace = true
            defer { isRestoringWorkspace = false }
            guard request.id == parent.scrollRequest?.id else {
                pendingWorkspaceRestore = nil
                collectionView.alphaValue = 1
                return
            }
            guard let path = indexPath(forDayID: request.dayID),
                  let attributes = collectionView.layoutAttributesForItem(at: path) else { return }

            let readingEditor = editor(forDayID: request.dayID)
            let requiresReadingEditor = request.readingAnchor != nil
                || attributes.frame.intersects(scrollView.contentView.bounds)
            let focusID = parent.activeDayID ?? request.dayID
            if restoredSelectionRequestID != request.id {
                if let editor = editor(forDayID: focusID) {
                    restoredSelectionRequestID = request.id
                    if let selection = request.selectionRange {
                        let location = min(selection.location, editor.string.utf16.count)
                        editor.setSelectedRange(NSRange(location: location,
                            length: min(selection.length, editor.string.utf16.count - location)))
                    }
                }
            }
            if requiresReadingEditor, let editor = readingEditor, !editor.isGeometrySettled { return }
            // A populated row may be waiting for its SwiftUI host to mount.
            if requiresReadingEditor, readingEditor == nil, case .day(let document) = items[path.item],
               !effectiveIsMinimized(document),
               MarkdownBlockRendering.hasRenderedContent(in: document.text)
                || document.id == parent.activeDayID || document.date == parent.today {
                return
            }
            if requiresReadingEditor, request.shouldFocusEditor, focusID == request.dayID,
               parent.scrollRequest?.shouldFocusEditor == true, let editor = readingEditor,
               let window = editor.window, window.isKeyWindow, window.attachedSheet == nil,
               !((window.firstResponder as? NSTextView)?.isFieldEditor ?? false) {
                // Selection can be restored before the row's frame is ready;
                // first-responder eligibility deliberately waits for geometry.
                // Keep focus outside the selection-once gate so it isn't lost
                // when the initial, unmeasured mount rejects it.
                guard window.makeFirstResponder(editor), window.firstResponder === editor else { return }
            }
            let offset = request.readingAnchor == nil ? request.offset ?? 0
                : min(request.offset ?? 0, max(0, attributes.frame.height - 1))
            var targetY = attributes.frame.minY + offset
            if let anchor = request.readingAnchor, let editor = readingEditor,
               let point = anchor.lineOrigin(in: editor) {
                targetY = editor.convert(point, to: collectionView).y + anchor.lineOffset
            }
            scroll(toY: targetY, in: scrollView, collectionView: collectionView)
            pendingWorkspaceRestore = nil
            collectionView.alphaValue = 1
            publishViewState()
            maybeLoadMore()
        }

        private func scroll(toY targetY: CGFloat, in scrollView: NSScrollView, collectionView: NSCollectionView) {
            let viewportHeight = scrollView.contentView.bounds.height
            let contentHeight = max(collectionView.collectionViewLayout?.collectionViewContentSize.height ?? collectionView.bounds.height, collectionView.bounds.height)
            let maxY = max(0, contentHeight - viewportHeight)
            let clampedY = min(max(0, targetY), maxY)
            scrollView.contentView.scroll(to: NSPoint(x: 0, y: clampedY))
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }

        private func reconfigureVisibleDayItems(
            matching dayIDs: Set<String>? = nil,
            skipsActiveEditor: Bool = false
        ) {
            guard let collectionView else { return }
            let activeDayID = skipsActiveEditor ? MarkdownTextView.activeEditor?.currentDayID : nil
            for indexPath in collectionView.indexPathsForVisibleItems() where indexPath.item < items.count {
                if case .emptyDays(let group) = items[indexPath.item],
                   let item = collectionView.item(at: indexPath) as? TimelineEmptyDaysCollectionItem {
                    configureEmptyDayItem(item, group: group)
                    continue
                }
                guard case .day(let document) = items[indexPath.item],
                      let dayItem = collectionView.item(at: indexPath) as? TimelineDayCollectionItem else { continue }
                if let dayIDs, !dayIDs.contains(document.id) {
                    continue
                }
                if document.id == activeDayID, document.text == MarkdownTextView.activeEditor?.string {
                    dayItem.updateSaveState(document)
                    continue
                }
                dayItem.configure(
                    document: document,
                    isToday: Calendar.current.isDate(document.date, inSameDayAs: parent.today),
                    isActive: document.id == parent.activeDayID,
                    isMinimized: effectiveIsMinimized(document),
                    searchQuery: parent.searchQuery,
                    configuration: parent.configuration,
                    sourceMode: parent.sourceMode,
                    allowsEditorFocus: parent.scrollRequest?.offset == nil && (parent.scrollRequest?.shouldFocusEditor ?? true),
                    streamLinkTargets: parent.streamLinkTargets,
                    onOpenStream: parent.onOpenStream,
                    onFocus: parent.onFocus,
                    onChange: parent.onChange,
                    onToggleMinimized: { [weak self] date, dayID in
                        self?.toggleMinimized(for: date, dayID: dayID)
                    }
                )
            }
        }

        private func configureEmptyDayItem(_ item: TimelineEmptyDaysCollectionItem, group: TimelineEmptyDayGroup) {
            item.configure(group: group) { [weak self] in
                guard let self else { return }
                if group.isExpanded { self.expandedEmptyDayIDs.subtract(group.days.map(\.id)) }
                else { self.expandedEmptyDayIDs.formUnion(group.days.map(\.id)) }
                self.apply(self.pendingSnapshot ?? self.scheduledSnapshot ?? self.parent, animated: false)
            }
        }

        private func activeChangeCanAffectRowHeight(_ previousActiveDayID: String?, _ nextActiveDayID: String?) -> Bool {
            [previousActiveDayID, nextActiveDayID]
                .compactMap { $0 }
                .contains { dayID in
                    guard case .day(let document) = items.first(where: { $0.dayID == dayID }) else { return false }
                    let hasText = MarkdownBlockRendering.hasRenderedContent(in: document.text)
                    let isToday = Calendar.current.isDate(document.date, inSameDayAs: parent.today)
                    return !hasText && !isToday
                }
        }

        private func toggleMinimized(for date: Date, dayID: String) {
            pendingMinimizedToggleAnchor = captureAnchor(forDayID: dayID)
            parent.onToggleMinimized(date)
        }

        private func effectiveIsMinimized(_ document: DayDocument) -> Bool {
            TimelineDayPresentation.isEffectivelyMinimized(
                document: document,
                isToday: Calendar.current.isDate(document.date, inSameDayAs: parent.today),
                minimizedDayIDs: parent.minimizedDayIDs,
                searchQuery: parent.searchQuery
            )
        }

        private func captureAnchor(forDayID dayID: String) -> ScrollAnchor? {
            guard let collectionView,
                  let scrollView,
                  let indexPath = indexPath(forDayID: dayID),
                  let attributes = collectionView.layoutAttributesForItem(at: indexPath) else { return nil }

            return ScrollAnchor(
                dayID: dayID,
                offsetFromVisibleTop: scrollView.contentView.bounds.minY - attributes.frame.minY,
                itemIdentity: items[indexPath.item].identity
            )
        }

        private func indexPath(forDayID dayID: String) -> IndexPath? {
            guard let index = items.firstIndex(where: { $0.contains(dayID: dayID) }) else { return nil }
            return IndexPath(item: index, section: 0)
        }

        private func itemWidth(in collectionView: NSCollectionView) -> CGFloat {
            TimelineLayoutMetrics.itemWidth(
                availableWidth: viewportWidth(in: collectionView),
                configuration: parent.configuration
            )
        }

        private func viewportWidth(in collectionView: NSCollectionView) -> CGFloat {
            // Measure from the same bounds used to place rows; the clip view
            // may already have its next width during a window resize.
            max(1, collectionView.bounds.width)
        }

        private func viewportWidth() -> CGFloat {
            max(1, scrollView?.contentView.bounds.width ?? collectionView?.bounds.width ?? 1)
        }

        private static func items(from parent: TimelineCollectionView, expandedEmptyDayIDs: Set<String>,
                                  top: CGFloat, bottom: CGFloat) -> [TimelineCollectionItem] {
            var items: [TimelineCollectionItem] = []
            if top > 0.5 {
                items.append(.topSpacer(top))
            }
            items.append(contentsOf: TimelineHistoryPresentation.rows(days: parent.days, today: parent.today,
                activeDayID: parent.activeDayID, requestedDayID: parent.scrollRequest?.dayID,
                expandedEmptyDayIDs: expandedEmptyDayIDs))
            if bottom > 0.5 {
                items.append(.bottomSpacer(bottom))
            }
            return items
        }
    }
}

private struct ScrollAnchor {
    var dayID: String
    var offsetFromVisibleTop: CGFloat
    var rowHeight: CGFloat = 0
    var itemIdentity: String? = nil
    var readingAnchor: MarkdownReadingAnchor? = nil
}

private struct MarkdownEditorCaretAnchor {
    var dayID: String?
    var offsetFromVisibleTop: CGFloat
    var wasFirstResponder: Bool
}

final class TimelineDayCollectionItem: NSCollectionViewItem {
    static let reuseIdentifier = NSUserInterfaceItemIdentifier("TimelineDayCollectionItem")
    private var hostingView: NSHostingView<DaySectionView>?
    private var model: DaySectionModel?
    private var representedDayID: String?

    override func loadView() {
        view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        representedDayID = nil
        model = nil
        hostingView?.removeFromSuperview()
        hostingView = nil
    }

    func updateSaveState(_ document: DayDocument) {
        model?.updateSaveState(document)
    }

    func configure(
        document: DayDocument,
        isToday: Bool,
        isActive: Bool,
        isMinimized: Bool,
        searchQuery: String,
        configuration: CurrentConfiguration,
        sourceMode: Bool = false,
        allowsEditorFocus: Bool = true,
        streamLinkTargets: [MarkdownStreamLinkTarget] = [],
        onOpenStream: @escaping (UUID) -> Void = { _ in },
        onFocus: @escaping (Date) -> Void,
        onChange: @escaping (Date, String) -> Void,
        onToggleMinimized: @escaping (Date, String) -> Void
    ) {
        if representedDayID != document.id {
            representedDayID = document.id
            model = nil
            hostingView?.removeFromSuperview()
            hostingView = nil
        }

        let focus = {
            onFocus(document.date)
        }
        let change = { text in
            onChange(document.date, text)
        }
        let toggleMinimized = {
            onToggleMinimized(document.date, document.id)
        }

        if let model {
            model.update(
                document: document,
                isToday: isToday,
                isActive: isActive,
                isMinimized: isMinimized,
                searchQuery: searchQuery,
                configuration: configuration,
                sourceMode: sourceMode,
                allowsEditorFocus: allowsEditorFocus,
                streamLinkTargets: streamLinkTargets,
                onOpenStream: onOpenStream,
                onFocus: focus,
                onChange: change,
                onToggleMinimized: toggleMinimized
            )
            return
        }

        let model = DaySectionModel(
            document: document,
            isToday: isToday,
            isActive: isActive,
            isMinimized: isMinimized,
            searchQuery: searchQuery,
            configuration: configuration,
            sourceMode: sourceMode,
            allowsEditorFocus: allowsEditorFocus,
            streamLinkTargets: streamLinkTargets,
            onOpenStream: onOpenStream,
            onFocus: focus,
            onChange: change,
            onToggleMinimized: toggleMinimized
        )
        let rootView = DaySectionView(model: model)

        if let hostingView {
            hostingView.rootView = rootView
            self.model = model
        } else {
            let hostingView = NSHostingView(rootView: rootView)
            hostingView.translatesAutoresizingMaskIntoConstraints = false
            hostingView.setContentHuggingPriority(.defaultLow, for: .horizontal)
            hostingView.setContentHuggingPriority(.defaultLow, for: .vertical)
            hostingView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            hostingView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
            view.addSubview(hostingView)
            NSLayoutConstraint.activate([
                hostingView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                hostingView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                hostingView.topAnchor.constraint(equalTo: view.topAnchor),
                hostingView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
            ])
            self.hostingView = hostingView
            self.model = model
        }
    }
}

final class TimelineSpacerCollectionItem: NSCollectionViewItem {
    static let reuseIdentifier = NSUserInterfaceItemIdentifier("TimelineSpacerCollectionItem")

    override func loadView() {
        view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor
    }
}

final class TimelineEmptyDaysCollectionItem: NSCollectionViewItem {
    static let reuseIdentifier = NSUserInterfaceItemIdentifier("TimelineEmptyDaysCollectionItem")
    private var button: NSButton?
    private var reveal: (() -> Void)?

    override func loadView() {
        view = NSView()
        let button = NSButton(title: "", target: self, action: #selector(showDays))
        button.isBordered = false
        button.alignment = .left
        button.font = .systemFont(ofSize: 12)
        button.imagePosition = .imageLeading
        button.contentTintColor = CurrentTheme.secondaryTextColor
        button.lineBreakMode = .byTruncatingTail
        button.setAccessibilityIdentifier("timeline.emptyDays")
        button.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(button)
        NSLayoutConstraint.activate([
            button.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            button.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            button.topAnchor.constraint(equalTo: view.topAnchor),
            button.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        self.button = button
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        reveal = nil
    }

    func configure(group: TimelineEmptyDayGroup, reveal: @escaping () -> Void) {
        _ = view
        self.reveal = reveal
        let formatter = DateIntervalFormatter()
        formatter.dateTemplate = "MMM d"
        let dates = formatter.string(from: group.days[group.days.count - 1].date, to: group.days[0].date)
        let title = "\(dates) · \(group.days.count) empty \(group.days.count == 1 ? "day" : "days")"
        button?.title = title
        button?.image = NSImage(systemSymbolName: group.isExpanded ? "chevron.down" : "chevron.right", accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 9, weight: .medium))
        button?.toolTip = group.isExpanded ? "Hide these empty dates" : "Show these dates to start a note"
        button?.setAccessibilityLabel("\(group.isExpanded ? "Hide" : "Show") \(group.days.count) empty \(group.days.count == 1 ? "day" : "days"), \(dates)")
    }

    @objc private func showDays() { reveal?() }
}
