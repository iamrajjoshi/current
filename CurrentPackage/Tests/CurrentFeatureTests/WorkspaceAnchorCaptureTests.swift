import AppKit
import SwiftUI
import Testing
@testable import CurrentFeature

@Suite(.serialized)
@MainActor
struct WorkspaceAnchorCaptureTests {
    @Test(arguments: [75.0, 86.0])
    func visibleDateSkipsEmptyTodayWhitespaceWithoutChangingTheReopenedViewport(offset: Double) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("current-date-boundary-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let today = calendar.date(from: DateComponents(year: 2026, month: 9, day: 30))!
        let store = StreamStore(libraryRoot: root, calendar: calendar)
        let stream = try store.defaultStream()
        let source = (0..<25).map { "Line \($0): Read the release checklist carefully.\n" }.joined()
        for age in 1...2 {
            var document = try store.loadDay(calendar.addingDays(-age, to: today), in: stream)
            document.text = source
            document.isDirty = true
            _ = try store.saveDay(document)
        }
        let controller = TimelineController(store: store, recentDayCount: 3, autosaveDelay: 60, now: today)
        controller.bootstrapIfNeeded(now: today)
        controller.setActiveDate(calendar.addingDays(-1, to: today))
        // This is a reading-session test. Restore its selection without taking
        // the process-wide active editor from concurrently running native suites.
        controller.updateViewState(StreamViewState(dayKey: "2026-09-29", scrollDayKey: "2026-09-30",
                                                   selectionLocation: 14, selectionLength: 5, editorHadFocus: false))
        let (window, host) = mount(controller: controller, restoresRequest: true)
        defer { window.close() }
        try await waitUntil(host, "All three date rows must finish native layout") {
            guard let collection: NSCollectionView = find(in: host), hasThreeRows(collection),
                  let item = collection.item(at: IndexPath(item: 1, section: 0)),
                  let editor: MarkdownTextView = find(in: item.view) else { return false }
            let mounted = editors(in: collection)
            return collection.alphaValue == 1 && mounted.count >= 2 && mounted.allSatisfy(\.isGeometrySettled)
                && editor.selectedRange() == NSRange(location: 14, length: 5)
        }
        let collection: NSCollectionView = try #require(find(in: host))
        let scroll = try #require(collection.enclosingScrollView)
        let coordinator = try #require(collection.delegate as? TimelineCollectionView.Coordinator)
        let todayRow = try #require(collection.layoutAttributesForItem(at: IndexPath(item: 0, section: 0)))
        let yesterdayRow = try #require(collection.layoutAttributesForItem(at: IndexPath(item: 1, section: 0)))
        #expect(todayRow.frame.height == 94)
        let todayItem = try #require(collection.item(at: IndexPath(item: 0, section: 0)))
        let todayEditor: MarkdownTextView = try #require(find(in: todayItem.view))
        let yesterdayItem = try #require(collection.item(at: IndexPath(item: 1, section: 0)))
        let yesterdayEditor: MarkdownTextView = try #require(find(in: yesterdayItem.view))
        #expect(yesterdayEditor.selectedRange() == NSRange(location: 14, length: 5))
        #expect(window.firstResponder !== yesterdayEditor)
        try await settle(host)

        // Even a sliver of the final editable line still belongs to Today.
        let requestID = controller.scrollRequest?.id
        let storage = try #require(todayEditor.textStorage as? MarkdownTextStorage)
        let parseCount = storage.parseCount
        let manager = try #require(todayEditor.layoutManager)
        let lineBottom = todayEditor.convert(NSPoint(x: 0,
            y: todayEditor.textContainerOrigin.y + manager.extraLineFragmentRect.maxY), to: collection).y
        scroll.contentView.scroll(to: NSPoint(x: 0, y: lineBottom - 0.5))
        coordinator.captureFinalPosition(saveNotes: false)
        #expect(controller.currentViewState.visibleDayKey == "2026-09-30")

        let expectedY = todayRow.frame.minY + offset
        scroll.contentView.scroll(to: NSPoint(x: 0, y: expectedY))
        scroll.reflectScrolledClipView(scroll.contentView)
        try await settle(host)
        coordinator.captureFinalPosition()
        let saved = controller.currentViewState
        #expect(saved.visibleDayKey == "2026-09-29")
        #expect(saved.scrollDayKey == "2026-09-30")
        #expect(abs(saved.scrollOffset - offset) < 0.001)
        #expect(saved.dayKey == "2026-09-29")
        #expect(saved.selectionLocation == 14 && saved.selectionLength == 5)
        #expect(!((saved.editorHadFocus) ?? true))
        #expect(abs(scroll.contentView.bounds.minY - expectedY) < 0.001)
        #expect(controller.scrollRequest?.id == requestID)
        #expect(storage.parseCount == parseCount)
        // At offset86, rebasing to yesterday would give -8; at75 it
        // would give -19 and clamp on reopen if yesterday began the window.
        #expect(abs((expectedY - yesterdayRow.frame.minY) - (offset - 94)) < 0.001)
        #expect(try store.loadSession().views[stream.id] == saved)
        window.close()

        let reopened = TimelineController(store: StreamStore(libraryRoot: root, calendar: calendar),
                                          recentDayCount: 3, autosaveDelay: 60, now: today)
        reopened.bootstrapIfNeeded(now: today)
        #expect(reopened.currentViewState == saved)
        let (reopenedWindow, reopenedHost) = mount(controller: reopened, restoresRequest: true)
        defer { reopenedWindow.close() }
        try await waitUntil(reopenedHost, "Reopening must restore viewport, visible date and native selection") {
            guard let collection: NSCollectionView = find(in: reopenedHost), hasThreeRows(collection),
                  let item = collection.item(at: IndexPath(item: 1, section: 0)),
                  let editor: MarkdownTextView = find(in: item.view) else { return false }
            return collection.alphaValue == 1 && editor.isGeometrySettled
                && editor.selectedRange() == NSRange(location: 14, length: 5)
                && reopened.currentViewState.visibleDayKey == "2026-09-29"
        }
        let reopenedCollection: NSCollectionView = try #require(find(in: reopenedHost))
        let reopenedScroll = try #require(reopenedCollection.enclosingScrollView)
        #expect(abs(reopenedScroll.contentView.bounds.minY - expectedY) < 0.1)
        #expect(reopened.currentViewState.scrollDayKey == "2026-09-30")
        #expect(reopened.activeDocument?.text == source)
        #expect(reopenedWindow.firstResponder is MarkdownTextView == false)
    }

    @Test(arguments: [false, true])
    func collapsedHeadersAndEmptyRunControlsKeepTheirDateWhileVisible(emptyRun: Bool) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("current-collapsed-date-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let today = calendar.date(from: DateComponents(year: 2026, month: 9, day: 30))!
        let store = StreamStore(libraryRoot: root, calendar: calendar)
        let stream = try store.defaultStream()
        let count = emptyRun ? 3 : 2
        for age in 1...count {
            var document = try store.loadDay(calendar.addingDays(-age, to: today), in: stream)
            document.text = emptyRun && age < count ? "" : (0..<25).map { "Line \($0): Review the checklist.\n" }.joined()
            document.isDirty = true
            _ = try store.saveDay(document)
        }
        let controller = TimelineController(store: store, recentDayCount: count + 1, autosaveDelay: 60, now: today)
        controller.bootstrapIfNeeded(now: today)
        if !emptyRun { controller.toggleDayMinimized(calendar.addingDays(-1, to: today)) }
        let (window, host) = mount(controller: controller)
        defer { window.close() }
        try await waitUntil(host, "Collapsed days and empty runs must finish layout") {
            guard let collection: NSCollectionView = find(in: host), hasThreeRows(collection) else { return false }
            return collection.alphaValue == 1 && editors(in: collection).allSatisfy(\.isGeometrySettled)
        }
        let collection: NSCollectionView = try #require(find(in: host))
        let scroll = try #require(collection.enclosingScrollView)
        let coordinator = try #require(collection.delegate as? TimelineCollectionView.Coordinator)
        let row = try #require(collection.layoutAttributesForItem(at: IndexPath(item: 1, section: 0)))
        #expect(row.frame.height == (emptyRun ? 30 : 36))
        let contentBottom = emptyRun ? row.frame.maxY
            : row.frame.minY + CurrentTheme.daySectionVerticalPaddingExpanded + CurrentTheme.dayDividerIntrinsicHeight
        scroll.contentView.scroll(to: NSPoint(x: 0, y: contentBottom - 0.5))
        coordinator.captureFinalPosition(saveNotes: false)
        #expect(controller.currentViewState.visibleDayKey == "2026-09-29")
        scroll.contentView.scroll(to: NSPoint(x: 0, y: contentBottom + 0.5))
        coordinator.captureFinalPosition(saveNotes: false)
        #expect(controller.currentViewState.visibleDayKey == (emptyRun ? "2026-09-27" : "2026-09-28"))
        if !emptyRun {
            #expect(controller.currentViewState.scrollDayKey == "2026-09-29")
            #expect(controller.currentViewState.minimizedDayKeys == ["2026-09-29"])
        }
    }

    @Test func immediateEditAndClosePreserveReadingAnchorAndLatestSelection() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("current-anchor-capture-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let today = calendar.date(from: DateComponents(year: 2026, month: 9, day: 28))!
        let store = StreamStore(libraryRoot: root, calendar: calendar)
        let stream = try store.defaultStream()
        let source = (0..<60).map { "Paragraph \($0): The team is reviewing the release checklist and recording what to verify before the next meeting.\n\n" }.joined()
        var document = try store.loadDay(today, in: stream)
        document.text = source
        document.isDirty = true
        _ = try store.saveDay(document)
        let controller = TimelineController(store: store, recentDayCount: 1, autosaveDelay: 60, now: today)
        controller.bootstrapIfNeeded(now: today)

        let host = NSHostingView(rootView: Fixture(controller: controller))
        host.sizingOptions = []
        host.frame = NSRect(x: 0, y: 0, width: 720, height: 360)
        let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 720, height: 360),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderFront(nil)
        defer { window.close() }
        try await settle(host)
        let collection: NSCollectionView = try #require(find(in: host))
        let scrollView = try #require(collection.enclosingScrollView)
        let coordinator = try #require(collection.delegate as? TimelineCollectionView.Coordinator)
        let editor: MarkdownTextView = try #require(find(in: collection))
        try #require(editor.isGeometrySettled)
        try #require(window.makeFirstResponder(editor))

        let readingLocation = (source as NSString).range(of: "Paragraph 20:").location
        let editLocation = (source as NSString).range(of: "Paragraph 21:").location + "Paragraph 21:".utf16.count
        editor.setSelectedRange(NSRange(location: editLocation, length: 0))
        try await settle(host)
        let reading = MarkdownReadingAnchor.captureSource(in: source, at: readingLocation)
        let lineOrigin = try #require(reading.lineOrigin(in: editor))
        let viewportY = editor.convert(lineOrigin, to: collection).y + 3
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: viewportY))
        scrollView.reflectScrolledClipView(scrollView.contentView)
        try await settle(host)
        coordinator.captureFinalPosition()
        let before = controller.currentViewState
        let stableAnchor = try #require(before.readingAnchor)
        #expect(stableAnchor.sourceLocation == readingLocation)

        // Native selection notifications arrive synchronously, before the
        // editor's queued geometry publication. Closing here must merge the
        // new selection without replacing a valid source anchor with nil.
        editor.insertText(" updated", replacementRange: editor.selectedRange())
        try #require(!editor.isGeometrySettled)
        let selectionAfterTyping = editor.selectedRange()
        #expect(selectionAfterTyping.location == editLocation + " updated".utf16.count)
        #expect(controller.currentViewState.readingAnchor == stableAnchor)
        coordinator.captureFinalPosition()
        let saved = try #require(store.loadSession().views[stream.id])
        #expect(saved.readingAnchor == stableAnchor)
        #expect(saved.scrollDayKey == document.dayKey)
        #expect(saved.selectionLocation == selectionAfterTyping.location)
        #expect(saved.selectionLength == selectionAfterTyping.length)
        #expect(saved.selectionLocation != before.selectionLocation)
        #expect(saved.readingAnchor?.resolvedSourceLocation(in: editor.string) == readingLocation)
        try await settle(host)
    }

    @Test func legacyOffsetBeyondItsRecordedDayRestoresTheVisibleOlderNote() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("current-legacy-anchor-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let today = calendar.date(from: DateComponents(year: 2026, month: 9, day: 28))!
        let store = StreamStore(libraryRoot: root, calendar: calendar)
        let stream = try store.defaultStream()
        for age in 1...2 {
            var document = try store.loadDay(calendar.addingDays(-age, to: today), in: stream)
            document.text = (0..<25).map { "September \(28 - age), line \($0): Review the release checklist.\n" }.joined()
            document.isDirty = true
            _ = try store.saveDay(document)
        }
        let controller = TimelineController(store: store, recentDayCount: 3, autosaveDelay: 60, now: today)
        controller.bootstrapIfNeeded(now: today)
        try #require(controller.days.map(\.dayKey) == ["2026-09-28", "2026-09-27", "2026-09-26"])

        let (originalWindow, originalHost) = mount(controller: controller)
        defer { originalWindow.close() }
        try await waitUntil(originalHost, "The original timeline must publish and lay out its three rows") {
            guard let collection: NSCollectionView = find(in: originalHost), hasThreeRows(collection) else { return false }
            let mountedEditors = editors(in: collection)
            return collection.alphaValue == 1 && !mountedEditors.isEmpty
                && mountedEditors.allSatisfy(\.isGeometrySettled)
        }
        let originalCollection: NSCollectionView = try #require(find(in: originalHost))
        try #require(hasThreeRows(originalCollection))
        let todayRow = try #require(originalCollection.layoutAttributesForItem(at: IndexPath(item: 0, section: 0)))
        let olderRow = try #require(originalCollection.layoutAttributesForItem(at: IndexPath(item: 2, section: 0)))
        let expectedViewportY = olderRow.frame.minY + 120
        let legacyOffset = Double(expectedViewportY - todayRow.frame.minY)
        try #require(legacyOffset > todayRow.frame.height)
        originalWindow.close()

        // Older versions sometimes saved Today from an overscan item while
        // the pixel offset actually referred to a following day's content.
        let legacy = StreamViewState(dayKey: "2026-09-26", scrollDayKey: "2026-09-28",
                                     scrollOffset: legacyOffset, selectionLocation: 14, selectionLength: 5,
                                     readingAnchor: nil, editorHadFocus: false)
        controller.setActiveDate(calendar.addingDays(-2, to: today))
        controller.updateViewState(legacy)
        #expect(controller.flushAllSaves())
        let reopened = TimelineController(store: StreamStore(libraryRoot: root, calendar: calendar),
                                          recentDayCount: 3, autosaveDelay: 60, now: today)
        reopened.bootstrapIfNeeded(now: today)
        #expect(reopened.currentViewState == legacy)
        #expect(abs((reopened.scrollRequest?.offset ?? -1) - legacyOffset) < 0.001)
        let (window, host) = mount(controller: reopened, restoresRequest: true)
        defer { window.close() }
        try await waitUntil(host, "The restored timeline must finish older-note layout and selection restoration") {
            guard let collection: NSCollectionView = find(in: host), hasThreeRows(collection),
                  let item = collection.item(at: IndexPath(item: 2, section: 0)),
                  let editor: MarkdownTextView = find(in: item.view) else { return false }
            return collection.alphaValue == 1 && editor.isGeometrySettled && editor.visibleRect.height > 0
                && editor.selectedRange() == NSRange(location: 14, length: 5)
        }
        let collection: NSCollectionView = try #require(find(in: host))
        try #require(hasThreeRows(collection))
        let scrollView = try #require(collection.enclosingScrollView)
        #expect(abs((reopened.scrollRequest?.offset ?? -1) - legacyOffset) < 0.001)
        let restoredOlderRow = try #require(collection.layoutAttributesForItem(at: IndexPath(item: 2, section: 0)))
        #expect(abs(scrollView.contentView.bounds.minY - expectedViewportY) < 1)
        #expect(restoredOlderRow.frame.intersects(scrollView.contentView.bounds))
        #expect(collection.alphaValue == 1)
        #expect(reopened.currentViewState.scrollDayKey == "2026-09-26")
        let olderItem = try #require(collection.item(at: IndexPath(item: 2, section: 0)))
        let olderEditor: MarkdownTextView = try #require(find(in: olderItem.view))
        #expect(olderEditor.visibleRect.height > 0)
        #expect(olderEditor.string.hasPrefix("September 26, line 0:"))
        #expect(reopened.currentViewState.selectionLocation == 14)
        #expect(reopened.currentViewState.selectionLength == 5)
        #expect(olderEditor.selectedRange() == NSRange(location: 14, length: 5))
        #expect(window.firstResponder !== olderEditor)
    }

    private func mount(controller: TimelineController, restoresRequest: Bool = false) -> (NSWindow, NSHostingView<Fixture>) {
        let host = NSHostingView(rootView: Fixture(controller: controller, restoresRequest: restoresRequest))
        host.sizingOptions = []
        host.frame = NSRect(x: 0, y: 0, width: 720, height: 360)
        let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 720, height: 360),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderFront(nil)
        return (window, host)
    }

    private func hasThreeRows(_ collection: NSCollectionView) -> Bool {
        // AppKit raises an Objective-C exception for an out-of-bounds layout
        // query, which #require cannot catch. Validate its published counts first.
        guard collection.numberOfSections == 1, collection.numberOfItems(inSection: 0) == 3 else { return false }
        return (0..<3).allSatisfy { index in
            guard let row = collection.layoutAttributesForItem(at: IndexPath(item: index, section: 0)) else { return false }
            return row.frame.width > 0 && row.frame.height > 0
        }
    }

    private func waitUntil(_ view: NSView, _ reason: String, condition: () -> Bool) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(10))
        repeat {
            view.layoutSubtreeIfNeeded()
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        } while clock.now < deadline
        try #require(condition(), "\(reason)")
    }

    private func settle(_ view: NSView) async throws {
        for _ in 0..<20 {
            view.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(5))
        }
    }

    private func find<T: NSView>(in view: NSView) -> T? {
        if let result = view as? T { return result }
        return view.subviews.lazy.compactMap { find(in: $0) as T? }.first
    }

    private func editors(in view: NSView) -> [MarkdownTextView] {
        if let editor = view as? MarkdownTextView { return [editor] }
        return view.subviews.flatMap { editors(in: $0) }
    }

    private struct Fixture: View {
        @ObservedObject var controller: TimelineController
        var restoresRequest = false

        var body: some View {
            TimelineCollectionView(
                days: controller.days, today: controller.today, activeDayID: controller.activeDayID,
                minimizedDayIDs: controller.minimizedDayIDs, searchQuery: "", configuration: .default,
                canLoadOlderDays: false, topSpacerHeight: 0, bottomSpacerHeight: 0,
                scrollRequest: restoresRequest ? controller.scrollRequest : nil,
                onFocus: { controller.setActiveDate($0) },
                onChange: { controller.updateText(for: $0, text: $1) },
                onToggleMinimized: { controller.toggleDayMinimized($0) },
                onLoadOlder: {}, onLoadNewer: {}, viewState: controller.currentViewState,
                onViewStateChange: { controller.updateViewState($0) },
                onSaveWorkspace: { controller.flushAllSaves() }
            )
            .onAppear {
                if restoresRequest { controller.bootstrapIfNeeded(now: controller.today) }
            }
        }
    }
}
