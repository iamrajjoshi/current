import AppKit
import SwiftUI

struct TimelineCollectionView: NSViewRepresentable {
    var days: [DayDocument]
    var today: Date
    var activeDayID: String?
    var minimizedDayIDs: Set<String>
    var searchQuery: String
    var configuration: CurrentConfiguration
    var canLoadOlderDays: Bool
    var topSpacerHeight: CGFloat
    var bottomSpacerHeight: CGFloat
    var scrollRequest: TimelineScrollRequest?
    var onFocus: (Date) -> Void
    var onChange: (Date, String) -> Void
    var onToggleMinimized: (Date) -> Void
    var onLoadOlder: () -> Void
    var onLoadNewer: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.backgroundColor = CurrentTheme.pageBackgroundColor
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = false
        scrollView.scrollerStyle = .overlay
        scrollView.borderType = .noBorder
        scrollView.contentView.postsBoundsChangedNotifications = true
        scrollView.contentView.postsFrameChangedNotifications = true

        let layout = NSCollectionViewFlowLayout()
        layout.scrollDirection = .vertical
        layout.minimumLineSpacing = 0
        layout.minimumInteritemSpacing = TimelineLayoutMetrics.minimumInteritemSpacing(
            availableWidth: 1,
            configuration: configuration
        )
        layout.sectionInset = TimelineLayoutMetrics.sectionInset(
            availableWidth: 1,
            configuration: configuration
        )

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

        scrollView.documentView = collectionView

        context.coordinator.scrollView = scrollView
        context.coordinator.collectionView = collectionView
        context.coordinator.apply(self, animated: false)
        context.coordinator.startObservingBoundsChanges()

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.apply(self, animated: false)
    }

    static func dismantleNSView(_ scrollView: NSScrollView, coordinator: Coordinator) {
        coordinator.stopObservingBoundsChanges()
    }
}

public enum TimelineRowHeightCalculator {
    public static let collapsedEmptyDayHeight: CGFloat = 36
    public static let todayEmptyEditorMinimumHeight: CGFloat = 280
    public static let expandedEditorMinimumHeight: CGFloat = 64

    public static func height(
        for document: DayDocument,
        isToday: Bool,
        isActive: Bool = false,
        isMinimized: Bool = false,
        width: CGFloat = 700,
        configuration: CurrentConfiguration = .default
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
            configuration: configuration
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
        configuration: CurrentConfiguration = .default
    ) -> CGFloat {
        MarkdownTextLayoutMeasurer.measuredHeight(
            text: text,
            width: width,
            minimumHeight: minimumHeight,
            configuration: configuration
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
            CurrentTheme.timelineHorizontalPadding,
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

private enum TimelineCollectionItem: Equatable {
    case topSpacer(CGFloat)
    case day(DayDocument)
    case bottomSpacer(CGFloat)

    var identity: String {
        switch self {
        case .topSpacer:
            return "spacer.top"
        case .day(let document):
            return document.id
        case .bottomSpacer:
            return "spacer.bottom"
        }
    }

    var dayID: String? {
        guard case .day(let document) = self else { return nil }
        return document.id
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
        private var isLoadingOlder = false
        private var isLoadingNewer = false
        private var lastRequestedOlderBoundaryID: String?
        private var lastRequestedNewerBoundaryID: String?
        private var lastViewportWidth: CGFloat = 0
        private var pendingMinimizedToggleAnchor: ScrollAnchor?

        init(_ parent: TimelineCollectionView) {
            self.parent = parent
            self.items = Self.items(from: parent)
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

        func apply(_ nextParent: TimelineCollectionView, animated: Bool) {
            guard let collectionView else { return }
            syncCollectionViewFrame()

            let nextItems = Self.items(from: nextParent)
            let structureChanged = nextItems.map(\.identity) != items.map(\.identity)
            let contentChanged = nextItems != items
            let spacerChanged = abs(nextParent.topSpacerHeight - parent.topSpacerHeight) > 0.5
                || abs(nextParent.bottomSpacerHeight - parent.bottomSpacerHeight) > 0.5
            let searchChanged = nextParent.searchQuery != lastSearchQuery
            let activeDayChanged = nextParent.activeDayID != parent.activeDayID
            let minimizedChanged = nextParent.minimizedDayIDs != parent.minimizedDayIDs
            let configurationChanged = nextParent.configuration != parent.configuration
            let todayChanged = nextParent.today != parent.today
            let contentOnlyChanged = contentChanged
                && !structureChanged
                && !spacerChanged
                && !searchChanged
                && !activeDayChanged
                && !minimizedChanged
                && !configurationChanged
                && !todayChanged
            let activeOnlyChanged = activeDayChanged
                && !structureChanged
                && !contentChanged
                && !spacerChanged
                && !searchChanged
                && !minimizedChanged
                && !configurationChanged
                && !todayChanged
            let layoutStateChanged = minimizedChanged || searchChanged
            let preferredAnchor = minimizedChanged ? pendingMinimizedToggleAnchor : nil
            let anchor = structureChanged || spacerChanged || layoutStateChanged
                ? preferredAnchor ?? captureFirstVisibleDayAnchor()
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
            let caretAnchor = contentChangeAffectsRowHeight ? captureActiveEditorCaretAnchor() : nil
            if minimizedChanged {
                pendingMinimizedToggleAnchor = nil
            }

            parent = nextParent
            isApplyingSnapshot = true
            items = nextItems

            if structureChanged || spacerChanged {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0
                    context.allowsImplicitAnimation = false
                    collectionView.reloadData()
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

            handleExplicitScrollRequestIfNeeded()
            isApplyingSnapshot = false
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
                configuration: parent.configuration
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
            case .day(let document):
                let height = TimelineRowHeightCalculator.height(
                    for: document,
                    isToday: Calendar.current.isDate(document.date, inSameDayAs: parent.today),
                    isActive: document.id == parent.activeDayID,
                    isMinimized: effectiveIsMinimized(document),
                    width: width,
                    configuration: parent.configuration
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

        @objc private func viewportDidChange(_ notification: Notification) {
            let widthChanged = recordViewportWidthChange()
            let anchor = widthChanged ? captureFirstVisibleDayAnchor() : nil
            syncCollectionViewFrame()
            if widthChanged {
                collectionView?.collectionViewLayout?.invalidateLayout()
                collectionView?.layoutSubtreeIfNeeded()
                syncCollectionViewFrame()
                reconfigureVisibleDayItems()
                if let anchor {
                    restore(anchor)
                }
            }
            maybeLoadMore()
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
            updateFlowLayoutForViewportWidth(clipSize.width)
            let contentSize = collectionView.collectionViewLayout?.collectionViewContentSize ?? clipSize
            if lastViewportWidth == 0 {
                lastViewportWidth = max(1, clipSize.width)
            }
            collectionView.frame = NSRect(
                x: 0,
                y: 0,
                width: max(1, clipSize.width),
                height: max(1, clipSize.height, contentSize.height)
            )
        }

        private func updateFlowLayoutForViewportWidth(_ width: CGFloat) {
            guard let layout = collectionView?.collectionViewLayout as? NSCollectionViewFlowLayout else { return }
            let targetInset = TimelineLayoutMetrics.sectionInset(
                availableWidth: width,
                configuration: parent.configuration
            )
            let targetInteritemSpacing = TimelineLayoutMetrics.minimumInteritemSpacing(
                availableWidth: width,
                configuration: parent.configuration
            )
            let insetChanged = abs(layout.sectionInset.left - targetInset.left) > 0.5
                || abs(layout.sectionInset.right - targetInset.right) > 0.5
            let spacingChanged = abs(layout.minimumInteritemSpacing - targetInteritemSpacing) > 0.5

            guard insetChanged || spacingChanged else { return }

            layout.sectionInset = targetInset
            layout.minimumInteritemSpacing = targetInteritemSpacing
            layout.invalidateLayout()
        }

        private func maybeLoadMore() {
            guard !isApplyingSnapshot,
                  let scrollView,
                  let collectionView else { return }

            let visibleRect = scrollView.contentView.bounds
            let contentHeight = max(collectionView.collectionViewLayout?.collectionViewContentSize.height ?? collectionView.bounds.height, collectionView.bounds.height)
            let distanceToBottom = contentHeight - visibleRect.maxY

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

            if parent.topSpacerHeight > 0,
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

        private func captureFirstVisibleDayAnchor() -> ScrollAnchor? {
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
                guard case .day(let document) = items[indexPath.item],
                      let attributes = collectionView.layoutAttributesForItem(at: indexPath) else { continue }
                return ScrollAnchor(
                    dayID: document.id,
                    offsetFromVisibleTop: visibleRect.minY - attributes.frame.minY
                )
            }

            return nil
        }

        private func restore(_ anchor: ScrollAnchor) {
            guard let collectionView,
                  let scrollView,
                  let indexPath = indexPath(forDayID: anchor.dayID),
                  let attributes = collectionView.layoutAttributesForItem(at: indexPath) else { return }

            let targetY = attributes.frame.minY + anchor.offsetFromVisibleTop
            scroll(toY: targetY, in: scrollView, collectionView: collectionView)
        }

        private func captureActiveEditorCaretAnchor() -> MarkdownEditorCaretAnchor? {
            guard let collectionView,
                  let scrollView,
                  let textView = MarkdownTextView.activeEditor,
                  textView.isDescendant(of: collectionView),
                  let caretY = caretY(in: collectionView, for: textView) else {
                return nil
            }

            return MarkdownEditorCaretAnchor(
                dayID: textView.currentDayID,
                offsetFromVisibleTop: scrollView.contentView.bounds.minY - caretY
            )
        }

        private func restore(_ anchor: MarkdownEditorCaretAnchor) {
            guard let collectionView,
                  let scrollView,
                  let textView = MarkdownTextView.activeEditor,
                  textView.currentDayID == anchor.dayID,
                  textView.isDescendant(of: collectionView),
                  let caretY = caretY(in: collectionView, for: textView) else {
                return
            }

            let targetY = caretY + anchor.offsetFromVisibleTop
            scroll(toY: targetY, in: scrollView, collectionView: collectionView)
        }

        private func caretY(in collectionView: NSCollectionView, for textView: MarkdownTextView) -> CGFloat? {
            MarkdownVisibleCaret.caretY(in: collectionView, for: textView)
        }

        private func handleExplicitScrollRequestIfNeeded() {
            guard let request = parent.scrollRequest,
                  request.id != handledScrollRequestID,
                  let collectionView,
                  let scrollView,
                  let indexPath = indexPath(forDayID: request.dayID),
                  let attributes = collectionView.layoutAttributesForItem(at: indexPath) else { return }

            let viewportHeight = scrollView.contentView.bounds.height
            let targetY = attributes.frame.minY - viewportHeight * CurrentTheme.scrollTargetAnchorY
            scroll(toY: targetY, in: scrollView, collectionView: collectionView)
            if case .today = request.target {
                DispatchQueue.main.async {
                    MarkdownTextView.focusEditor(dayID: request.dayID)
                }
            }
            handledScrollRequestID = request.id
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
                guard case .day(let document) = items[indexPath.item],
                      let dayItem = collectionView.item(at: indexPath) as? TimelineDayCollectionItem else { continue }
                if let dayIDs, !dayIDs.contains(document.id) {
                    continue
                }
                if document.id == activeDayID {
                    continue
                }
                dayItem.configure(
                    document: document,
                    isToday: Calendar.current.isDate(document.date, inSameDayAs: parent.today),
                    isActive: document.id == parent.activeDayID,
                    isMinimized: effectiveIsMinimized(document),
                    searchQuery: parent.searchQuery,
                    configuration: parent.configuration,
                    onFocus: parent.onFocus,
                    onChange: parent.onChange,
                    onToggleMinimized: { [weak self] date, dayID in
                        self?.toggleMinimized(for: date, dayID: dayID)
                    }
                )
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
                offsetFromVisibleTop: scrollView.contentView.bounds.minY - attributes.frame.minY
            )
        }

        private func indexPath(forDayID dayID: String) -> IndexPath? {
            guard let index = items.firstIndex(where: { $0.dayID == dayID }) else { return nil }
            return IndexPath(item: index, section: 0)
        }

        private func itemWidth(in collectionView: NSCollectionView) -> CGFloat {
            TimelineLayoutMetrics.itemWidth(
                availableWidth: viewportWidth(in: collectionView),
                configuration: parent.configuration
            )
        }

        private func viewportWidth(in collectionView: NSCollectionView) -> CGFloat {
            max(1, collectionView.enclosingScrollView?.contentView.bounds.width ?? collectionView.bounds.width)
        }

        private func viewportWidth() -> CGFloat {
            if let collectionView {
                return viewportWidth(in: collectionView)
            }
            return max(1, scrollView?.contentView.bounds.width ?? 1)
        }

        private static func items(from parent: TimelineCollectionView) -> [TimelineCollectionItem] {
            var items: [TimelineCollectionItem] = []
            if parent.topSpacerHeight > 0.5 {
                items.append(.topSpacer(parent.topSpacerHeight))
            }
            items.append(contentsOf: parent.days.map(TimelineCollectionItem.day))
            if parent.bottomSpacerHeight > 0.5 {
                items.append(.bottomSpacer(parent.bottomSpacerHeight))
            }
            return items
        }
    }
}

private struct ScrollAnchor {
    var dayID: String
    var offsetFromVisibleTop: CGFloat
}

private struct MarkdownEditorCaretAnchor {
    var dayID: String?
    var offsetFromVisibleTop: CGFloat
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

    func configure(
        document: DayDocument,
        isToday: Bool,
        isActive: Bool,
        isMinimized: Bool,
        searchQuery: String,
        configuration: CurrentConfiguration,
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
