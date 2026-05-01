import Foundation
import CurrentFeature

@main
struct CurrentFeatureChecks {
    static func main() async throws {
        try dayPathsUseTransparentDailyMarkdownLayout()
        try bootstrapCreatesDailyStreamAndTodayFile()
        try loadOlderDaysAppendsPastBelowToday()
        try loadOlderDaysDoesNotCreateMissingDayFiles()
        try loadOlderDaysKeepsGoingPastBlankHistoryRunway()
        try loadOlderDaysKeepsRenderedHistoryBounded()
        try loadOlderDaysKeepsOlderActualFilesReachable()
        try loadNewerWindowRestoresTrimmedTopHistory()
        try loadNewerWindowReloadsCleanTrimmedDocuments()
        try dirtyOffWindowDocumentsStayCachedAndSave()
        try rowHeightCalculatorKeepsEmptyCollapsedRowsStable()
        try rowHeightCalculatorExpandsActiveEmptyRows()
        try rowHeightCalculatorUsesLargeMinimumForEmptyToday()
        try rowHeightCalculatorGrowsForMultilineText()
        try timelineLayoutMetricsCenterTheWritingColumn()
        try timelineLayoutMetricsPreventWideViewportWrapping()
        try markdownListEditingContinuesCommonLists()
        try markdownHeadingRenderingTracksNotionLikeShortcuts()
        try markdownHeadingBackspaceExitsBlock()
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

    @MainActor
    static func loadOlderDaysDoesNotCreateMissingDayFiles() throws {
        let root = try temporaryRoot()
        let calendar = fixedCalendar()
        let now = try require(calendar.date(from: DateComponents(year: 2026, month: 4, day: 29, hour: 9)))
        let controller = TimelineController(
            store: StreamStore(libraryRoot: root, calendar: calendar),
            cache: DayCache(calendar: calendar),
            recentDayCount: 2,
            historyBatchSize: 5,
            now: now
        )
        controller.bootstrapIfNeeded(now: now)

        controller.loadOlderDays()

        try check(
            controller.days.map(\.id) == ["2026-04-29", "2026-04-28", "2026-04-27", "2026-04-26", "2026-04-25", "2026-04-24", "2026-04-23"],
            "Missing older days should appear in memory for scrollable history"
        )
        try check(
            !FileManager.default.fileExists(atPath: root.appendingPathComponent("Streams/Daily/2026/04/2026-04-27.md").path),
            "Scrolling history should not create missing day files"
        )
    }

    @MainActor
    static func loadOlderDaysKeepsGoingPastBlankHistoryRunway() throws {
        let root = try temporaryRoot()
        let calendar = fixedCalendar()
        let now = try require(calendar.date(from: DateComponents(year: 2026, month: 4, day: 29, hour: 9)))
        let controller = TimelineController(
            store: StreamStore(libraryRoot: root, calendar: calendar),
            cache: DayCache(calendar: calendar),
            recentDayCount: 2,
            historyBatchSize: 5,
            now: now
        )
        controller.bootstrapIfNeeded(now: now)

        controller.loadOlderDays()
        controller.loadOlderDays()
        controller.loadOlderDays()
        controller.loadOlderDays()

        try check(
            controller.days.last?.id == "2026-04-08",
            "Blank placeholder history should keep extending instead of stopping at a runway"
        )
        try check(controller.canLoadOlderDays == true, "History loader should remain available for endless scrollback")
        try check(
            !FileManager.default.fileExists(atPath: root.appendingPathComponent("Streams/Daily/2026/04/2026-04-23.md").path),
            "Blank history days should stay in memory until edited"
        )
    }

    @MainActor
    static func loadOlderDaysKeepsRenderedHistoryBounded() throws {
        let root = try temporaryRoot()
        let calendar = fixedCalendar()
        let now = try require(calendar.date(from: DateComponents(year: 2026, month: 4, day: 29, hour: 9)))
        let controller = TimelineController(
            store: StreamStore(libraryRoot: root, calendar: calendar),
            cache: DayCache(calendar: calendar),
            recentDayCount: 2,
            historyBatchSize: 5,
            historyWindowDayCount: 12,
            now: now
        )
        controller.bootstrapIfNeeded(now: now)

        controller.loadOlderDays()
        controller.loadOlderDays()
        controller.loadOlderDays()
        controller.loadOlderDays()

        try check(controller.days.count == 12, "Rendered history should stay bounded by the configured window")
        try check(controller.days.first?.id == "2026-04-19", "Compaction should slide the window toward older dates")
        try check(controller.days.last?.id == "2026-04-08", "Older scrollback should keep extending after compaction")
        try check(controller.topSpacerHeight > 0, "Compacted newer days should be represented by a top spacer")
        try check(controller.bottomSpacerHeight == 0, "Older-only scrolling should not create a bottom spacer")
        try check(controller.canLoadOlderDays == true, "History loader should remain available after compaction")

        controller.jumpToToday()

        try check(controller.days.map(\.id) == ["2026-04-29", "2026-04-28"], "Jumping to today should restore the recent window")
        try check(controller.topSpacerHeight == 0, "Jumping to today should reset the top spacer")
        try check(controller.bottomSpacerHeight == 0, "Jumping to today should reset the bottom spacer")
    }

    @MainActor
    static func loadOlderDaysKeepsOlderActualFilesReachable() throws {
        let root = try temporaryRoot()
        let calendar = fixedCalendar()
        let now = try require(calendar.date(from: DateComponents(year: 2026, month: 4, day: 29, hour: 9)))
        let store = StreamStore(libraryRoot: root, calendar: calendar)
        let stream = try store.defaultStream()
        let olderActualDate = try require(calendar.date(from: DateComponents(year: 2026, month: 4, day: 1)))
        try writeDay(olderActualDate, text: "Imported old note", stream: stream, store: store)
        let controller = TimelineController(
            store: store,
            cache: DayCache(calendar: calendar),
            recentDayCount: 2,
            historyBatchSize: 10,
            now: now
        )
        controller.bootstrapIfNeeded(now: now)

        controller.loadOlderDays()
        controller.loadOlderDays()
        controller.loadOlderDays()

        try check(
            controller.days.contains { $0.id == "2026-04-01" },
            "Actual older Markdown files should remain reachable when their date enters the endless history"
        )
        try check(
            controller.days.first { $0.id == "2026-04-01" }?.text == "Imported old note",
            "Expected the older actual file to load"
        )
    }

    @MainActor
    static func loadNewerWindowRestoresTrimmedTopHistory() throws {
        let root = try temporaryRoot()
        let calendar = fixedCalendar()
        let now = try require(calendar.date(from: DateComponents(year: 2026, month: 4, day: 29, hour: 9)))
        let controller = TimelineController(
            store: StreamStore(libraryRoot: root, calendar: calendar),
            cache: DayCache(calendar: calendar),
            recentDayCount: 2,
            historyBatchSize: 5,
            historyWindowDayCount: 12,
            now: now
        )
        controller.bootstrapIfNeeded(now: now)

        controller.loadOlderWindow()
        controller.loadOlderWindow()
        controller.loadOlderWindow()
        controller.loadOlderWindow()
        let topSpacerBefore = controller.topSpacerHeight

        try check(controller.days.first?.id == "2026-04-19", "Expected newer days to be trimmed after older paging")
        try check(topSpacerBefore > 0, "Expected top spacer before loading newer rows")

        controller.loadNewerWindow()

        try check(controller.days.first?.id == "2026-04-24", "Loading newer should restore the next newer batch above the window")
        try check(controller.days.count == 12, "Newer paging should keep the retained row count bounded")
        try check(controller.topSpacerHeight < topSpacerBefore, "Loading newer should consume top spacer height")
        try check(controller.bottomSpacerHeight > 0, "Loading newer from a trimmed top should trim older rows into a bottom spacer")
    }

    @MainActor
    static func loadNewerWindowReloadsCleanTrimmedDocuments() throws {
        let root = try temporaryRoot()
        let calendar = fixedCalendar()
        let now = try require(calendar.date(from: DateComponents(year: 2026, month: 4, day: 29, hour: 9)))
        let noteDate = calendar.addingDays(-1, to: now)
        let store = StreamStore(libraryRoot: root, calendar: calendar)
        let stream = try store.defaultStream()
        try writeDay(noteDate, text: "Persisted recent note", stream: stream, store: store)
        let controller = TimelineController(
            store: store,
            cache: DayCache(maxCleanDocuments: 4, calendar: calendar),
            recentDayCount: 2,
            historyBatchSize: 14,
            historyWindowDayCount: 30,
            now: now
        )
        controller.bootstrapIfNeeded(now: now)

        for _ in 0..<16 {
            controller.loadOlderWindow()
        }

        try check(!controller.days.contains { $0.id == "2026-04-28" }, "Recent note should be trimmed out of the visible window")
        try check(controller.cache[noteDate] == nil, "Clean off-window note should be allowed to evict from cache")

        for _ in 0..<20 where !controller.days.contains(where: { $0.id == "2026-04-28" }) {
            controller.loadNewerWindow()
        }

        try check(
            controller.days.first { $0.id == "2026-04-28" }?.text == "Persisted recent note",
            "Reloading newer rows should restore clean trimmed document text from disk"
        )
    }

    @MainActor
    static func dirtyOffWindowDocumentsStayCachedAndSave() throws {
        let root = try temporaryRoot()
        let calendar = fixedCalendar()
        let now = try require(calendar.date(from: DateComponents(year: 2026, month: 4, day: 29, hour: 9)))
        let store = StreamStore(libraryRoot: root, calendar: calendar)
        let controller = TimelineController(
            store: store,
            cache: DayCache(calendar: calendar),
            recentDayCount: 2,
            historyBatchSize: 5,
            historyWindowDayCount: 6,
            autosaveDelay: 10,
            now: now
        )
        controller.bootstrapIfNeeded(now: now)
        controller.updateText(for: now, text: "Pinned dirty note")

        controller.loadOlderWindow()
        controller.loadOlderWindow()

        try check(!controller.days.contains { $0.id == "2026-04-29" }, "Today should be trimmed out of the visible window")
        try check(controller.cache[now]?.isDirty == true, "Dirty off-window documents should remain cached")

        controller.save(now)

        let todayPath = root.appendingPathComponent("Streams/Daily/2026/04/2026-04-29.md")
        let savedText = try String(contentsOf: todayPath, encoding: .utf8)
        try check(savedText == "Pinned dirty note", "Dirty off-window document did not save correctly")
        try check(controller.cache[now]?.isDirty == false, "Saved off-window document should be clean")
    }

    static func rowHeightCalculatorKeepsEmptyCollapsedRowsStable() throws {
        let calendar = fixedCalendar()
        let date = try require(calendar.date(from: DateComponents(year: 2026, month: 4, day: 28)))
        let document = DayDocument(streamID: UUID(), date: date, fileURL: URL(fileURLWithPath: "/tmp/empty.md"), text: "")

        let height = TimelineRowHeightCalculator.height(for: document, isToday: false, width: 700)

        try check(height == TimelineRowHeightCalculator.collapsedEmptyDayHeight, "Empty non-today rows should stay collapsed")
    }

    static func rowHeightCalculatorExpandsActiveEmptyRows() throws {
        let calendar = fixedCalendar()
        let date = try require(calendar.date(from: DateComponents(year: 2026, month: 4, day: 28)))
        let document = DayDocument(streamID: UUID(), date: date, fileURL: URL(fileURLWithPath: "/tmp/active-empty.md"), text: "")

        let collapsedHeight = TimelineRowHeightCalculator.height(for: document, isToday: false, width: 700)
        let activeHeight = TimelineRowHeightCalculator.height(for: document, isToday: false, isActive: true, width: 700)

        try check(activeHeight > collapsedHeight, "Active empty rows should reserve editor height instead of overlapping following dates")
    }

    static func rowHeightCalculatorUsesLargeMinimumForEmptyToday() throws {
        let calendar = fixedCalendar()
        let date = try require(calendar.date(from: DateComponents(year: 2026, month: 4, day: 29)))
        let document = DayDocument(streamID: UUID(), date: date, fileURL: URL(fileURLWithPath: "/tmp/today.md"), text: "")

        let height = TimelineRowHeightCalculator.height(for: document, isToday: true, width: 700)

        try check(height >= 320, "Today empty row should reserve the large editor minimum")
    }

    static func rowHeightCalculatorGrowsForMultilineText() throws {
        let calendar = fixedCalendar()
        let date = try require(calendar.date(from: DateComponents(year: 2026, month: 4, day: 28)))
        let short = DayDocument(streamID: UUID(), date: date, fileURL: URL(fileURLWithPath: "/tmp/short.md"), text: "One line")
        let multiline = DayDocument(
            streamID: UUID(),
            date: date,
            fileURL: URL(fileURLWithPath: "/tmp/multiline.md"),
            text: (0..<18).map { "Line \($0)" }.joined(separator: "\n")
        )

        let shortHeight = TimelineRowHeightCalculator.height(for: short, isToday: false, width: 700)
        let multilineHeight = TimelineRowHeightCalculator.height(for: multiline, isToday: false, width: 700)

        try check(multilineHeight > shortHeight, "Multiline note height should increase deterministically")
    }

    static func timelineLayoutMetricsCenterTheWritingColumn() throws {
        try check(
            TimelineLayoutMetrics.itemWidth(availableWidth: 700) == 588,
            "Compact widths should keep fixed horizontal padding"
        )
        try check(
            TimelineLayoutMetrics.horizontalInset(availableWidth: 700) == 56,
            "Compact widths should preserve the minimum horizontal inset"
        )
        try check(
            TimelineLayoutMetrics.itemWidth(availableWidth: 820) == 700,
            "Minimum app width should allow the max writing column"
        )
        try check(
            TimelineLayoutMetrics.horizontalInset(availableWidth: 820) == 60,
            "Minimum app width should center the max writing column"
        )
        try check(
            TimelineLayoutMetrics.horizontalInset(availableWidth: 1200) == 250,
            "Wide widths should recenter the max writing column"
        )
    }

    static func timelineLayoutMetricsPreventWideViewportWrapping() throws {
        for availableWidth in [820, 1200, 2048, 3440].map(CGFloat.init) {
            let itemWidth = TimelineLayoutMetrics.itemWidth(availableWidth: availableWidth)
            let horizontalInset = TimelineLayoutMetrics.horizontalInset(availableWidth: availableWidth)
            let interitemSpacing = TimelineLayoutMetrics.minimumInteritemSpacing(availableWidth: availableWidth)
            try check(
                itemWidth + horizontalInset * 2 <= availableWidth + 0.5,
                "Single writing column should fit within the viewport at \(availableWidth)"
            )
            try check(
                itemWidth * 2 + horizontalInset * 2 + interitemSpacing > availableWidth,
                "Wide timeline rows should not have room to wrap into multiple columns at \(availableWidth)"
            )
        }
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

    static func markdownHeadingRenderingTracksNotionLikeShortcuts() throws {
        let emptyH1 = try require(MarkdownBlockRendering.headingLine(in: "# ", at: 2))
        try check(emptyH1.level == 1, "Expected # + space to create an H1 line")
        try check(emptyH1.contentRange.length == 0, "Empty heading shortcut should still render as a heading")

        let h3 = try require(MarkdownBlockRendering.headingLine(in: "### Details", at: 4))
        try check(h3.level == 3, "Expected ### + space to create an H3 line")
        try check(h3.contentRange.location == 4, "Heading content should start after the marker and space")

        let plainHash = MarkdownBlockRendering.headingLine(in: "#", at: 1)
        try check(plainHash == nil, "A bare # should stay body text until space is typed")

        let fenced = "```\n# code\n```"
        let fencedHeading = MarkdownBlockRendering.headingLine(in: fenced, at: 5)
        try check(fencedHeading == nil, "Headings should not render inside fenced code")
    }

    static func markdownHeadingBackspaceExitsBlock() throws {
        let emptyEdit = try require(MarkdownBlockEditing.headingBackspaceEdit(
            in: "# ",
            selectedRange: NSRange(location: 2, length: 0)
        ))
        try check(emptyEdit.range == NSRange(location: 0, length: 2), "Backspace in an empty heading should remove the marker")
        try check(emptyEdit.replacement == "", "Backspace should exit the empty heading")
        try check(emptyEdit.selectedRangeAfterEdit == NSRange(location: 0, length: 0), "Cursor should return to the body line")

        let titledEdit = try require(MarkdownBlockEditing.headingBackspaceEdit(
            in: "## Title",
            selectedRange: NSRange(location: 3, length: 0)
        ))
        try check(titledEdit.range == NSRange(location: 0, length: 3), "Backspace at heading content start should remove the prefix")

        let midContentEdit = MarkdownBlockEditing.headingBackspaceEdit(
            in: "## Title",
            selectedRange: NSRange(location: 5, length: 0)
        )
        try check(midContentEdit == nil, "Backspace inside heading content should keep normal character deletion")
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

    static func writeDay(_ date: Date, text: String, stream: CurrentFeature.Stream, store: StreamStore) throws {
        let url = store.dayURL(for: date, in: stream)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
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
