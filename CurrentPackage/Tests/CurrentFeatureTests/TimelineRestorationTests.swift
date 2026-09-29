import Foundation
import Testing
@testable import CurrentFeature

@Suite(.serialized)
@MainActor
struct TimelineRestorationTests {
    @Test func closeFlushPersistsLatestScrollStateBeforeTheDebounceRuns() throws {
        let fixture = try Fixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        try fixture.write("2021-02-03", text: "The visible historical note")
        let controller = fixture.makeController()
        controller.updateViewState(StreamViewState(dayKey: fixture.todayKey, scrollDayKey: fixture.todayKey,
                                                  scrollOffset: 17, selectionLocation: 2))
        #expect(controller.flushAllSaves())
        let readingAnchor = MarkdownReadingAnchor.captureSource(in: "The visible historical note", at: 12, lineOffset: 2.5)
        let latest = StreamViewState(dayKey: fixture.todayKey, scrollDayKey: "2021-02-03",
                                     scrollOffset: 513.25, selectionLocation: 6, selectionLength: 2,
                                     readingAnchor: readingAnchor)
        controller.updateViewState(latest)
        // Close before the 400 ms session debounce has an opportunity to run.
        #expect(controller.flushAllSaves())
        let reopened = fixture.makeController()
        #expect(reopened.currentViewState == latest)
        #expect(reopened.activeDocument?.dayKey == fixture.todayKey)
        #expect(reopened.days.first?.dayKey == "2021-02-03")
        #expect(!reopened.days.contains { $0.dayKey == fixture.todayKey })
        #expect(reopened.scrollRequest?.dayID == reopened.dayID(for: fixture.date("2021-02-03")))
        #expect(reopened.scrollRequest?.offset == 513.25)
        #expect(reopened.scrollRequest?.selectionRange == NSRange(location: 6, length: 2))
        #expect(reopened.scrollRequest?.readingAnchor == readingAnchor)
        #expect(reopened.scrollRequest?.shouldFocusEditor == false)
        // Startup and a second close must not replace the saved visible date with the caret day.
        #expect(reopened.flushAllSaves())
        let again = fixture.makeController()
        #expect(again.currentViewState == latest)
        #expect(again.days.first?.dayKey == "2021-02-03")
        #expect(again.scrollRequest?.offset == 513.25)
    }

    @Test func reopeningAnOldBlankViewportKeepsItsSeparateOffscreenCaret() throws {
        let fixture = try Fixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let blank = fixture.date("2001-01-02")
        let controller = fixture.makeController()
        controller.jumpToDate(blank)
        controller.setActiveDate(fixture.today)
        let saved = StreamViewState(dayKey: fixture.todayKey, scrollDayKey: "2001-01-02",
                                    scrollOffset: -11, selectionLocation: 4, selectionLength: 3)
        controller.updateViewState(saved)
        #expect(controller.flushAllSaves())
        #expect(!fixture.store.dayFileExists(for: blank, in: fixture.stream))
        _ = try #require(controller.createStream(name: "Temporary switch"))
        controller.selectStream(fixture.stream.id, focusEditor: false)
        #expect(controller.days.first?.dayKey == "2001-01-02")
        #expect(controller.activeDocument?.dayKey == fixture.todayKey)
        #expect(controller.currentViewState == saved)
        #expect(controller.flushAllSaves())
        let reopened = fixture.makeController()
        #expect(reopened.currentViewState == saved)
        #expect(reopened.activeDocument?.dayKey == fixture.todayKey)
        #expect(reopened.days.first?.dayKey == "2001-01-02")
        #expect(reopened.days.contains { $0.dayKey == "2001-01-02" && $0.text.isEmpty })
        #expect(!reopened.days.contains { $0.dayKey == fixture.todayKey })
        #expect(reopened.scrollRequest?.dayID == reopened.dayID(for: blank))
        #expect(reopened.scrollRequest?.offset == -11)
        #expect(reopened.scrollRequest?.selectionRange == NSRange(location: 4, length: 3))
        #expect(!fixture.store.dayFileExists(for: blank, in: fixture.stream))
    }

    @Test(arguments: ["2001-01-02", "2036-11-19"])
    func directlyOpenedPastAndFutureNotesRestoreWithoutReturningToToday(dayKey: String) throws {
        let fixture = try Fixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let source = "# A dated note\n\nOriginal writing for \(dayKey).\n"
        try fixture.write(dayKey, text: source)
        let controller = fixture.makeController()
        controller.jumpToDate(fixture.date(dayKey))
        let saved = StreamViewState(dayKey: dayKey, scrollDayKey: dayKey, scrollOffset: 29.5,
                                    selectionLocation: 20, selectionLength: 8)
        controller.updateViewState(saved)
        #expect(controller.flushAllSaves())
        let reopened = fixture.makeController(now: fixture.calendar.addingDays(1, to: fixture.today))
        #expect(reopened.currentViewState == saved)
        #expect(reopened.days.first?.dayKey == dayKey)
        #expect(reopened.activeDocument?.dayKey == dayKey)
        #expect(reopened.activeDocument?.text == source)
        #expect(reopened.scrollRequest?.dayID == reopened.dayID(for: fixture.date(dayKey)))
        #expect(reopened.scrollRequest?.offset == 29.5)
        #expect(reopened.scrollRequest?.selectionRange == NSRange(location: 20, length: 8))
        #expect(reopened.days.count <= reopened.recentDayCount)
    }

    @Test func reopeningPreservesACollapsedVisibleDayWithoutFocusingItsOffscreenCaret() throws {
        let fixture = try Fixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let oldKey = "2021-02-03"
        let oldDate = fixture.date(oldKey)
        try fixture.write(oldKey, text: "A historical note that was deliberately collapsed")
        let controller = fixture.makeController()
        controller.jumpToDate(oldDate)
        controller.toggleDayMinimized(oldDate)
        controller.setActiveDate(fixture.today)
        let saved = StreamViewState(dayKey: fixture.todayKey, scrollDayKey: oldKey, scrollOffset: 12,
                                    selectionLocation: 7, minimizedDayKeys: [oldKey], editorHadFocus: true)
        controller.updateViewState(saved)
        #expect(controller.flushAllSaves())
        let reopened = fixture.makeController()
        #expect(reopened.currentViewState == saved)
        #expect(reopened.days.first?.dayKey == oldKey)
        #expect(reopened.isDayMinimized(oldDate))
        #expect(reopened.activeDocument?.dayKey == fixture.todayKey)
        #expect(!reopened.days.contains { $0.dayKey == fixture.todayKey })
        #expect(reopened.scrollRequest?.dayID == reopened.dayID(for: oldDate))
        #expect(reopened.scrollRequest?.offset == 12)
        #expect(reopened.scrollRequest?.shouldFocusEditor == false)
        reopened.restoreCurrentViewPosition()
        #expect(reopened.isDayMinimized(oldDate))
        #expect(reopened.scrollRequest?.shouldFocusEditor == false)
        #expect(reopened.scrollRequest?.offset == 12)
    }

    @Test func midnightDoesNotResetHistoricalViewportWhenTheCaretBelongsToYesterday() throws {
        let fixture = try Fixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        try fixture.write("2021-02-03", text: "Reading history at midnight")
        let controller = fixture.makeController()
        controller.jumpToDate(fixture.date("2021-02-03"))
        controller.setActiveDate(fixture.today)
        let saved = StreamViewState(dayKey: fixture.todayKey, scrollDayKey: "2021-02-03",
                                    scrollOffset: 85.5, selectionLocation: 5)
        controller.updateViewState(saved)
        let request = controller.scrollRequest
        let visibleIDs = controller.days.map(\.id)
        let tomorrow = fixture.calendar.addingDays(1, to: fixture.today)
        controller.handleDayRollover(now: tomorrow)
        #expect(controller.today == tomorrow)
        #expect(controller.activeDate == fixture.today)
        #expect(controller.days.map(\.id) == visibleIDs)
        #expect(controller.scrollRequest == request)
        #expect(controller.currentViewState == saved)
        #expect(controller.flushAllSaves())
        let reopened = fixture.makeController(now: tomorrow)
        #expect(reopened.currentViewState == saved)
        #expect(reopened.activeDocument?.dayKey == fixture.todayKey)
        #expect(reopened.days.first?.dayKey == "2021-02-03")
        #expect(reopened.scrollRequest?.offset == 85.5)
    }

    @Test func midnightKeepsWritingInTheExistingDayUntilAnExplicitTodayJump() throws {
        let fixture = try Fixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let controller = fixture.makeController()
        controller.updateText(for: fixture.today, text: "Writing across midnight")
        let saved = StreamViewState(dayKey: fixture.todayKey, scrollDayKey: fixture.todayKey,
                                    scrollOffset: 42, selectionLocation: 22)
        controller.updateViewState(saved)
        let request = controller.scrollRequest
        let tomorrow = fixture.calendar.addingDays(1, to: fixture.today)
        controller.handleDayRollover(now: tomorrow)
        #expect(controller.today == tomorrow)
        #expect(controller.activeDate == fixture.today)
        #expect(controller.activeDocument?.text == "Writing across midnight")
        #expect(controller.scrollRequest == request)
        #expect(controller.currentViewState == saved)
        controller.updateText(for: fixture.today, text: "Writing across midnight, still in the same note")
        #expect(controller.flushAllSaves())
        #expect(try fixture.store.loadDay(fixture.today, in: fixture.stream).text == "Writing across midnight, still in the same note")
        #expect(try fixture.store.loadDay(tomorrow, in: fixture.stream).text.isEmpty)
        controller.jumpToToday()
        #expect(controller.activeDate == tomorrow)
        #expect(controller.days.first?.date == tomorrow)
        #expect(controller.scrollRequest?.id != request?.id)
    }

    @Test func streamSwitchAndRelaunchPreserveIndependentVisibleAndCaretDays() throws {
        let fixture = try Fixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        try fixture.write("2021-02-03", text: "Daily historical note")
        let controller = fixture.makeController()
        controller.jumpToDate(fixture.date("2021-02-03"))
        controller.setActiveDate(fixture.today)
        let dailyState = StreamViewState(dayKey: fixture.todayKey, scrollDayKey: "2021-02-03",
                                         scrollOffset: 46, selectionLocation: 3)
        controller.updateViewState(dailyState)
        let work = try #require(controller.createStream(name: "Work"))
        controller.updateText(for: fixture.today, text: "Work today")
        let workState = StreamViewState(dayKey: fixture.todayKey, scrollDayKey: fixture.todayKey,
                                        scrollOffset: 19, selectionLocation: 7, selectionLength: 2)
        controller.updateViewState(workState)
        controller.selectStream(fixture.stream.id, focusEditor: false)
        #expect(controller.currentViewState == dailyState)
        #expect(controller.scrollRequest?.shouldFocusEditor == false)
        #expect(controller.scrollRequest?.offset == 46)
        controller.selectStream(work.id)
        #expect(controller.currentViewState == workState)
        #expect(controller.flushAllSaves())
        let reopened = fixture.makeController()
        #expect(reopened.stream?.id == work.id)
        #expect(reopened.currentViewState == workState)
        #expect(reopened.activeDocument?.text == "Work today")
        reopened.selectStream(fixture.stream.id, focusEditor: false)
        #expect(reopened.currentViewState == dailyState)
        #expect(reopened.days.first?.dayKey == "2021-02-03")
        #expect(reopened.activeDocument?.dayKey == fixture.todayKey)
        #expect(reopened.scrollRequest?.offset == 46)
        #expect(reopened.scrollRequest?.shouldFocusEditor == false)
    }

    @Test(arguments: [false, true])
    func relaunchRestoresEditorFocusOnlyWhenItWasExplicitlySaved(editorHadFocus: Bool) throws {
        let fixture = try Fixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let controller = fixture.makeController()
        let saved = StreamViewState(dayKey: fixture.todayKey, scrollDayKey: fixture.todayKey,
                                    scrollOffset: 18, selectionLocation: 5, editorHadFocus: editorHadFocus)
        controller.updateViewState(saved)
        #expect(controller.flushAllSaves())
        let reopened = fixture.makeController()
        #expect(reopened.currentViewState == saved)
        #expect(reopened.scrollRequest?.shouldFocusEditor == editorHadFocus)
        #expect(reopened.scrollRequest?.offset == 18)
        #expect(reopened.scrollRequest?.selectionRange == NSRange(location: 5, length: 0))
    }

    @Test func legacyViewStateDecodesWithoutDiscardingItsSavedPosition() throws {
        let legacy = Data(#"{"dayKey":"2026-09-28","scrollDayKey":"2021-02-03","scrollOffset":37.5,"selectionLocation":8,"selectionLength":3,"minimizedDayKeys":["2020-01-02"]}"#.utf8)
        let state = try JSONDecoder().decode(StreamViewState.self, from: legacy)
        #expect(state.dayKey == "2026-09-28")
        #expect(state.scrollDayKey == "2021-02-03")
        #expect(state.scrollOffset == 37.5)
        #expect(state.selectionLocation == 8 && state.selectionLength == 3)
        #expect(state.minimizedDayKeys == ["2020-01-02"])
        #expect(state.readingAnchor == nil)
        #expect(state.editorHadFocus == nil)
    }

    @Test func reopeningAWindowWithTheSameControllerRestoresTheLatestViewport() throws {
        let fixture = try Fixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        try fixture.write("2021-02-03", text: "The original jump and caret destination")
        try fixture.write("2021-02-02", text: "The later viewport position")
        let controller = fixture.makeController()
        controller.jumpToDate(fixture.date("2021-02-03"))
        let originalRequestID = controller.scrollRequest?.id
        let windowIDs = controller.days.map(\.id)
        let readingAnchor = MarkdownReadingAnchor.captureSource(in: "The later viewport position", at: 10, lineOffset: 4.5)
        let saved = StreamViewState(dayKey: "2021-02-03", scrollDayKey: "2021-02-02", scrollOffset: 87.5,
                                    selectionLocation: 9, selectionLength: 3, readingAnchor: readingAnchor,
                                    editorHadFocus: true)
        controller.updateViewState(saved)
        #expect(controller.flushAllSaves())
        // Closing a WindowGroup window need not terminate its app-level controller.
        controller.restoreCurrentViewPosition()
        #expect(controller.days.map(\.id) == windowIDs)
        #expect(controller.activeDocument?.dayKey == "2021-02-03")
        #expect(controller.currentViewState == saved)
        #expect(controller.scrollRequest?.id != originalRequestID)
        #expect(controller.scrollRequest?.dayID == controller.dayID(for: fixture.date("2021-02-02")))
        #expect(controller.scrollRequest?.offset == 87.5)
        #expect(controller.scrollRequest?.selectionRange == NSRange(location: 9, length: 3))
        #expect(controller.scrollRequest?.readingAnchor == readingAnchor)
        // Restoring an offscreen caret must not move a reader back to its day.
        #expect(controller.scrollRequest?.shouldFocusEditor == false)
        let restoredRequestID = controller.scrollRequest?.id
        controller.bootstrapIfNeeded(now: fixture.today)
        #expect(controller.scrollRequest?.id != restoredRequestID)
        #expect(controller.scrollRequest?.dayID == controller.dayID(for: fixture.date("2021-02-02")))
        #expect(controller.scrollRequest?.offset == 87.5)
    }

    @Test func workspaceSourceAndFocusModesSurviveRecreation() throws {
        let suite = "current-restoration-preferences-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let workspace = WorkspaceViewState(defaults: defaults)
        #expect(!workspace.sourceMode && !workspace.focusMode)
        workspace.sourceMode = true
        workspace.focusMode = true
        let reopened = WorkspaceViewState(defaults: defaults)
        #expect(reopened.sourceMode && reopened.focusMode)
        reopened.sourceMode = false
        #expect(!WorkspaceViewState(defaults: defaults).sourceMode)
        #expect(WorkspaceViewState(defaults: defaults).focusMode)
        reopened.focusMode = false
        #expect(!WorkspaceViewState(defaults: defaults).focusMode)
    }

    @MainActor private final class Fixture {
        let root: URL
        let calendar: Calendar
        let store: StreamStore
        let stream: CurrentFeature.Stream
        let today: Date
        let todayKey = "2026-09-28"

        init() throws {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(secondsFromGMT: 0)!
            self.calendar = calendar
            today = calendar.date(from: DateComponents(year: 2026, month: 9, day: 28))!
            root = FileManager.default.temporaryDirectory.appendingPathComponent("current-restoration-\(UUID().uuidString)")
            store = StreamStore(libraryRoot: root, calendar: calendar)
            var stream = try store.defaultStream()
            stream.createdAt = calendar.addingDays(-30, to: today)
            try store.saveLibrary(streams: [stream], folders: [])
            self.stream = stream
            try write(todayKey, text: "Today's existing caret and writing")
        }

        func date(_ key: String) -> Date { store.date(for: key)! }

        func write(_ key: String, text: String) throws {
            var document = try store.loadDay(date(key), in: stream)
            document.text = text
            document.isDirty = true
            _ = try store.saveDay(document)
        }

        func makeController(now: Date? = nil) -> TimelineController {
            let date = now ?? today
            // Recreate the store as well: an app relaunch cannot rely on in-memory indexes or windows.
            let store = StreamStore(libraryRoot: root, calendar: calendar)
            let controller = TimelineController(store: store, recentDayCount: 3, historyWindowDayCount: 30,
                                                autosaveDelay: 60, now: date)
            controller.bootstrapIfNeeded(now: date)
            return controller
        }
    }
}
