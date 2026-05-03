import AppKit
import SwiftUI

struct TimelineCollectionView: NSViewRepresentable {
    var days: [DayDocument]
    var today: Date
    var activeDayID: String?
    var searchQuery: String
    var configuration: CurrentConfiguration
    var canLoadOlderDays: Bool
    var topSpacerHeight: CGFloat
    var bottomSpacerHeight: CGFloat
    var scrollRequest: TimelineScrollRequest?
    var onFocus: (Date) -> Void
    var onChange: (Date, String) -> Void
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
        width: CGFloat = 700,
        configuration: CurrentConfiguration = .default
    ) -> CGFloat {
        let hasText = !document.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        guard isToday || isActive || hasText else {
            return collapsedEmptyDayHeight
        }

        let editorWidth = max(1, width)
        let minimumEditorHeight = isToday && !hasText ? todayEmptyEditorMinimumHeight : expandedEditorMinimumHeight
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
        let storage = NSTextStorage(string: text)
        let layoutManager = NSLayoutManager()
        let textContainer = NSTextContainer(
            size: NSSize(width: max(1, width), height: CGFloat.greatestFiniteMagnitude)
        )
        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = CurrentTheme.editorLineHeight(configuration: configuration)
        paragraph.maximumLineHeight = CurrentTheme.editorLineHeight(configuration: configuration)
        paragraph.lineBreakMode = .byWordWrapping

        textContainer.lineFragmentPadding = 0
        layoutManager.addTextContainer(textContainer)
        storage.addLayoutManager(layoutManager)
        storage.addAttributes(
            [
                .font: CurrentTheme.editorFont(configuration: configuration),
                .foregroundColor: CurrentTheme.primaryTextColor,
                .paragraphStyle: paragraph,
                .baselineOffset: CurrentTheme.editorBaselineOffset
            ],
            range: NSRange(location: 0, length: storage.length)
        )

        layoutManager.ensureLayout(for: textContainer)
        let used = layoutManager.usedRect(for: textContainer)
        return max(
            minimumHeight,
            ceil(used.height + CurrentTheme.editorVerticalInset * 2 + 6)
        )
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
            let spacerChanged = abs(nextParent.topSpacerHeight - parent.topSpacerHeight) > 0.5
                || abs(nextParent.bottomSpacerHeight - parent.bottomSpacerHeight) > 0.5
            let searchChanged = nextParent.searchQuery != lastSearchQuery
            let anchor = structureChanged || spacerChanged ? captureFirstVisibleDayAnchor() : nil

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
                    searchQuery: parent.searchQuery,
                    configuration: parent.configuration,
                    onFocus: parent.onFocus,
                    onChange: parent.onChange
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

        private func reconfigureVisibleDayItems() {
            guard let collectionView else { return }
            for indexPath in collectionView.indexPathsForVisibleItems() where indexPath.item < items.count {
                guard case .day(let document) = items[indexPath.item],
                      let dayItem = collectionView.item(at: indexPath) as? TimelineDayCollectionItem else { continue }
                dayItem.configure(
                    document: document,
                    isToday: Calendar.current.isDate(document.date, inSameDayAs: parent.today),
                    isActive: document.id == parent.activeDayID,
                    searchQuery: parent.searchQuery,
                    configuration: parent.configuration,
                    onFocus: parent.onFocus,
                    onChange: parent.onChange
                )
            }
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

final class TimelineDayCollectionItem: NSCollectionViewItem {
    static let reuseIdentifier = NSUserInterfaceItemIdentifier("TimelineDayCollectionItem")
    private var hostingView: NSHostingView<DaySectionView>?
    private var representedDayID: String?

    override func loadView() {
        view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        representedDayID = nil
        hostingView?.removeFromSuperview()
        hostingView = nil
    }

    func configure(
        document: DayDocument,
        isToday: Bool,
        isActive: Bool,
        searchQuery: String,
        configuration: CurrentConfiguration,
        onFocus: @escaping (Date) -> Void,
        onChange: @escaping (Date, String) -> Void
    ) {
        if representedDayID != document.id {
            representedDayID = document.id
            hostingView?.removeFromSuperview()
            hostingView = nil
        }

        let rootView = DaySectionView(
            document: document,
            isToday: isToday,
            isActive: isActive,
            searchQuery: searchQuery,
            configuration: configuration,
            onFocus: {
                onFocus(document.date)
            },
            onChange: { text in
                onChange(document.date, text)
            }
        )

        if let hostingView {
            hostingView.rootView = rootView
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
