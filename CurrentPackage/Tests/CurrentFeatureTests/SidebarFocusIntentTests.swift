import Foundation
import Testing
@testable import CurrentFeature

@Test @MainActor
func passiveStreamSelectionRestoresPositionAndSavesWithoutRequestingEditorFocus() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("current-sidebar-focus-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    let controller = TimelineController(store: StreamStore(libraryRoot: root), autosaveDelay: 60)
    controller.bootstrapIfNeeded()
    let daily = try #require(controller.stream)
    let work = try #require(controller.createStream(name: "Work"))
    controller.updateText(for: controller.today, text: "Work selection")
    let todayKey = DayFormatting.dayKey(for: controller.today)
    controller.updateViewState(StreamViewState(dayKey: todayKey, scrollDayKey: todayKey,
        scrollOffset: 37, selectionLocation: 4, selectionLength: 2))
    controller.selectStream(daily.id)
    controller.updateText(for: controller.today, text: "Save before sidebar selection")

    controller.selectStream(work.id, focusEditor: false)
    let request = try #require(controller.scrollRequest)
    #expect(!request.shouldFocusEditor)
    #expect(request.dayID == controller.activeDayID)
    #expect(request.offset == 37)
    #expect(request.selectionRange == NSRange(location: 4, length: 2))
    #expect(controller.openStreamIDs.isEmpty)
    #expect(try controller.store.loadDay(controller.today, in: daily).text == "Save before sidebar selection")

    controller.setActiveDate(controller.today)
    #expect(controller.scrollRequest?.shouldFocusEditor == true)
    #expect(controller.scrollRequest?.id == request.id, "Focusing a day must not issue another scroll")
    controller.selectStream(work.id, focusEditor: false)
    #expect(controller.scrollRequest?.shouldFocusEditor == false)
    #expect(controller.scrollRequest?.id == request.id, "Selecting the current sidebar row must not jump the timeline")
}

@Test @MainActor
func explicitWritingNavigationStillRequestsEditorFocusAfterSidebarSelection() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("current-explicit-focus-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    let controller = TimelineController(store: StreamStore(libraryRoot: root))
    controller.bootstrapIfNeeded()
    let daily = try #require(controller.stream)
    let work = try #require(controller.createStream(name: "Work"))
    controller.selectStream(daily.id, focusEditor: false)
    controller.jumpToToday()
    #expect(controller.scrollRequest?.shouldFocusEditor == true)
    controller.selectStream(work.id, focusEditor: false)
    controller.jumpToDate(Calendar.current.date(byAdding: .day, value: -1, to: controller.today)!)
    #expect(controller.scrollRequest?.shouldFocusEditor == true)
    controller.selectStream(daily.id, focusEditor: false)
    controller.selectStream(work.id)
    #expect(controller.scrollRequest?.shouldFocusEditor == true)
    controller.selectStream(daily.id, focusEditor: false)
    controller.openStreamTab(work.id)
    #expect(controller.scrollRequest?.shouldFocusEditor == true)
    #expect(controller.openStreamIDs == [work.id])
    controller.updateText(for: controller.today, text: "Search focus")
    controller.selectStream(daily.id, focusEditor: false)
    let result = try #require(LibrarySearch.search(query: "Search focus", streams: [work], libraryRoot: root).first)
    controller.openSearchResult(result)
    #expect(controller.scrollRequest?.shouldFocusEditor == true)
    #expect(controller.scrollRequest?.selectionRange == result.matchRange)
}
