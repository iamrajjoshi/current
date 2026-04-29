import Foundation
import CurrentFeature

@main
struct CurrentFeatureChecks {
    static func main() async throws {
        try dayPathsUseTransparentDailyMarkdownLayout()
        try bootstrapCreatesDailyStreamAndTodayFile()
        try loadOlderDaysAppendsPastBelowToday()
        try markdownListEditingContinuesCommonLists()
        try await autosaveWritesOnlyTheEditedDay()
        try rolloverCreatesANewTodayAndKeepsHistoryVisible()
        try streamStoreDetectsExternalConflictsBeforeOverwrite()
        try dayCacheEvictsCleanDocumentsButPinsDirtyAndToday()
        print("CurrentFeatureChecks passed")
    }

    static func dayPathsUseTransparentDailyMarkdownLayout() throws {
        let root = try temporaryRoot()
        let calendar = fixedCalendar()
        let store = StreamStore(libraryRoot: root, calendar: calendar)
        let stream = try store.defaultStream()
        let date = try require(calendar.date(from: DateComponents(year: 2026, month: 4, day: 29)))

        let url = store.dayURL(for: date, in: stream)

        try check(url.path.hasSuffix("/Current/Streams/Daily/2026/04/2026-04-29.md"), "Unexpected day path: \(url.path)")
    }

    @MainActor
    static func bootstrapCreatesDailyStreamAndTodayFile() throws {
        let root = try temporaryRoot()
        let calendar = fixedCalendar()
        let now = try require(calendar.date(from: DateComponents(year: 2026, month: 4, day: 29, hour: 9)))
        let controller = TimelineController(
            store: StreamStore(libraryRoot: root, calendar: calendar),
            cache: DayCache(calendar: calendar),
            recentDayCount: 3,
            now: now
        )

        controller.bootstrapIfNeeded(now: now)

        try check(controller.stream?.name == "Daily", "Expected Daily stream")
        try check(controller.days.map(\.id) == ["2026-04-29", "2026-04-28", "2026-04-27"], "Unexpected visible days")
        try check(
            FileManager.default.fileExists(atPath: root.appendingPathComponent("Streams/Daily/2026/04/2026-04-29.md").path),
            "Today file was not created"
        )
    }

    @MainActor
    static func loadOlderDaysAppendsPastBelowToday() throws {
        let root = try temporaryRoot()
        let calendar = fixedCalendar()
        let now = try require(calendar.date(from: DateComponents(year: 2026, month: 4, day: 29, hour: 9)))
        let controller = TimelineController(
            store: StreamStore(libraryRoot: root, calendar: calendar),
            cache: DayCache(calendar: calendar),
            recentDayCount: 2,
            historyBatchSize: 3,
            now: now
        )
        controller.bootstrapIfNeeded(now: now)

        controller.loadOlderDays()

        try check(
            controller.days.map(\.id) == ["2026-04-29", "2026-04-28", "2026-04-27", "2026-04-26", "2026-04-25"],
            "Older days should append below today in reverse chronological order"
        )
    }

    static func markdownListEditingContinuesCommonLists() throws {
        try checkContinuation("- first", replacement: "\n- ")
        try checkContinuation("- [x] done", replacement: "\n- [ ] ")
        try checkContinuation("7. done", replacement: "\n8. ")

        let emptyList = "- "
        let emptyEdit = try require(MarkdownListEditing.continuationEdit(
            in: emptyList,
            selectedRange: NSRange(location: emptyList.utf16.count, length: 0)
        ))
        try check(emptyEdit.range == NSRange(location: 0, length: 2), "Empty list item should be removed")
        try check(emptyEdit.replacement == "", "Empty list item should exit the list")

        let fenced = "```\n- code"
        let fencedEdit = MarkdownListEditing.continuationEdit(
            in: fenced,
            selectedRange: NSRange(location: fenced.utf16.count, length: 0)
        )
        try check(fencedEdit == nil, "Lists should not auto-continue inside fenced code")
    }

    static func checkContinuation(_ text: String, replacement: String) throws {
        let edit = try require(MarkdownListEditing.continuationEdit(
            in: text,
            selectedRange: NSRange(location: text.utf16.count, length: 0)
        ))
        try check(edit.range == NSRange(location: text.utf16.count, length: 0), "Continuation should insert at cursor")
        try check(edit.replacement == replacement, "Unexpected continuation replacement: \(edit.replacement)")
    }

    @MainActor
    static func autosaveWritesOnlyTheEditedDay() async throws {
        let root = try temporaryRoot()
        let calendar = fixedCalendar()
        let now = try require(calendar.date(from: DateComponents(year: 2026, month: 4, day: 29, hour: 9)))
        let controller = TimelineController(
            store: StreamStore(libraryRoot: root, calendar: calendar),
            cache: DayCache(calendar: calendar),
            recentDayCount: 2,
            autosaveDelay: 0.05,
            now: now
        )
        controller.bootstrapIfNeeded(now: now)

        controller.updateText(for: now, text: "# Meeting\n\n- [ ] Follow up")
        try await Task.sleep(nanoseconds: 130_000_000)

        let todayPath = root.appendingPathComponent("Streams/Daily/2026/04/2026-04-29.md")
        let yesterdayPath = root.appendingPathComponent("Streams/Daily/2026/04/2026-04-28.md")
        let savedText = try String(contentsOf: todayPath, encoding: .utf8)
        try check(savedText == "# Meeting\n\n- [ ] Follow up", "Autosave did not write today's content")
        try check(!FileManager.default.fileExists(atPath: yesterdayPath.path), "Autosave created an untouched previous day")
    }

    @MainActor
    static func rolloverCreatesANewTodayAndKeepsHistoryVisible() throws {
        let root = try temporaryRoot()
        let calendar = fixedCalendar()
        let april29 = try require(calendar.date(from: DateComponents(year: 2026, month: 4, day: 29, hour: 23)))
        let april30 = try require(calendar.date(from: DateComponents(year: 2026, month: 4, day: 30, hour: 1)))
        let controller = TimelineController(
            store: StreamStore(libraryRoot: root, calendar: calendar),
            cache: DayCache(calendar: calendar),
            recentDayCount: 2,
            now: april29
        )
        controller.bootstrapIfNeeded(now: april29)

        controller.handleDayRollover(now: april30)

        try check(controller.today == calendar.startOfDay(for: april30), "Today did not roll forward")
        try check(controller.days.map(\.id).first == "2026-04-30", "New today is not at the top")
        try check(
            FileManager.default.fileExists(atPath: root.appendingPathComponent("Streams/Daily/2026/04/2026-04-30.md").path),
            "Rolled-over day file was not created"
        )
    }

    static func streamStoreDetectsExternalConflictsBeforeOverwrite() throws {
        let root = try temporaryRoot()
        let calendar = fixedCalendar()
        let store = StreamStore(libraryRoot: root, calendar: calendar)
        let stream = try store.defaultStream()
        let date = try require(calendar.date(from: DateComponents(year: 2026, month: 4, day: 29)))
        var document = try store.loadDay(date, in: stream, createIfMissing: true)

        document.text = "In-app edit"
        document.isDirty = true
        try "External edit".write(to: document.fileURL, atomically: true, encoding: .utf8)

        do {
            _ = try store.saveDay(document)
            throw CheckFailure("Expected saveDay to throw a disk conflict")
        } catch StreamStoreError.diskChanged(let url, let diskText) {
            try check(url == document.fileURL, "Conflict pointed at the wrong file")
            try check(diskText == "External edit", "Conflict returned wrong disk text")
        }
    }

    static func dayCacheEvictsCleanDocumentsButPinsDirtyAndToday() throws {
        let calendar = fixedCalendar()
        let root = URL(fileURLWithPath: "/tmp/current-cache")
        let streamID = UUID()
        var cache = DayCache(maxCleanDocuments: 2, calendar: calendar)
        let today = try require(calendar.date(from: DateComponents(year: 2026, month: 4, day: 29)))

        for offset in 0..<5 {
            let date = calendar.addingDays(-offset, to: today)
            var document = DayDocument(
                streamID: streamID,
                date: date,
                fileURL: root.appendingPathComponent("\(offset).md"),
                text: "\(offset)",
                lastLoadedAt: Date(timeIntervalSince1970: TimeInterval(offset))
            )
            if offset == 3 {
                document.text = "dirty"
                document.isDirty = true
            }
            cache.insert(document)
        }

        let evicted = cache.evictCleanDocuments(keeping: [], today: today)

        try check(cache[today] != nil, "Today was evicted")
        try check(cache[calendar.addingDays(-3, to: today)]?.isDirty == true, "Dirty day was evicted")
        try check(evicted.count == 2, "Expected 2 evicted clean documents, got \(evicted.count)")
    }

    static func temporaryRoot() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("CurrentChecks-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url.appendingPathComponent("Current", isDirectory: true)
    }

    static func fixedCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar
    }

    static func require<T>(_ value: T?, _ message: String = "Expected non-nil value") throws -> T {
        guard let value else { throw CheckFailure(message) }
        return value
    }

    static func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else { throw CheckFailure(message) }
    }
}

struct CheckFailure: Error, CustomStringConvertible {
    var description: String

    init(_ description: String) {
        self.description = description
    }
}
