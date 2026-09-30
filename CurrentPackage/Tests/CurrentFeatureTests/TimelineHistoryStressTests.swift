import Foundation
import Testing
@testable import CurrentFeature

private var historyCalendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    return calendar
}

@Test(arguments: [false, true]) @MainActor
func rebuildingRecentHistoryRetainsAlreadyVisibleImportedNotes(refreshFromDisk: Bool) throws {
    let calendar = historyCalendar
    let today = calendar.date(from: DateComponents(year: 2026, month: 9, day: 27))!
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("current-recent-imports-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }
    let store = StreamStore(libraryRoot: root, calendar: calendar)
    var stream = try store.defaultStream()
    stream.createdAt = today
    try store.saveLibrary(streams: [stream], folders: [])
    let imported = [3, 40, 400].map { calendar.addingDays(-$0, to: today) }
    for date in imported {
        var document = try store.loadDay(date, in: stream)
        document.text = "Imported note \(document.dayKey)"
        document.isDirty = true
        try store.saveDay(document)
    }
    let controller = TimelineController(store: store, recentDayCount: 4, now: today)
    controller.bootstrapIfNeeded(now: today)
    let expected = [today] + imported
    #expect(controller.days.map(\.date) == expected)
    for _ in 0..<3 {
        if refreshFromDisk { controller.refreshExternalChanges() }
        else { controller.jumpToToday() }
        #expect(controller.days.map(\.date) == expected)
        #expect(Set(controller.days.map(\.id)).count == controller.days.count)
        #expect(controller.activeDate == today)
    }

    // Refresh also merges a newly imported note without dropping retained ones.
    let added = calendar.addingDays(-10, to: today)
    let url = store.dayURL(for: added, in: stream)
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try "An externally imported note".write(to: url, atomically: true, encoding: .utf8)
    controller.refreshExternalChanges()
    #expect(controller.days.map(\.date) == [today, imported[0], added, imported[1]])
    #expect(controller.canLoadOlderDays)
    #expect(controller.loadOlderWindow())
    #expect(controller.days.map(\.date) == [today, imported[0], added, imported[1], imported[2]])
    #expect(Set(controller.days.map(\.id)).count == controller.days.count)
    #expect(!controller.canLoadOlderDays)
}

@Test @MainActor
func fiveYearsOfImportedHistoryCanPageBothDirectionsWithBoundedDocuments() throws {
    let calendar = historyCalendar
    let today = calendar.date(from: DateComponents(year: 2026, month: 9, day: 27))!
    let first = calendar.date(byAdding: .year, value: -5, to: today)!
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("current-history-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }
    let store = StreamStore(libraryRoot: root, calendar: calendar)
    // An imported library can contain years of notes before the stream metadata was created.
    let stream = try store.defaultStream()
    var dates: [Date] = []
    var sources: [String: String] = [:]
    var date = today
    while date >= first {
        let key = DayFormatting.dayKey(for: date, calendar: calendar)
        let longDay = dates.count.isMultiple(of: 90)
        let source = "# Review \(key)\n\n" + (longDay
            ? (0..<120).map { "Paragraph \($0): a longer note that keeps its original source when its timeline row is recycled.\n" }.joined(separator: "\n")
            : "A short daily note for \(key).\n")
        let url = store.dayURL(for: date, in: stream)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try source.write(to: url, atomically: true, encoding: .utf8)
        dates.append(date)
        sources[key] = source
        date = calendar.addingDays(-1, to: date)
    }

    let controller = TimelineController(store: store, cache: DayCache(maxCleanDocuments: 48),
                                        historyWindowDayCount: 60, autosaveDelay: 60, now: today)
    let started = Date()
    controller.bootstrapIfNeeded(now: today)
    var seen = Set(controller.days.map(\.dayKey))
    var maxDocuments = controller.cache.documents.count
    var olderPages = 0
    while controller.canLoadOlderDays, olderPages < 200 {
        #expect(autoreleasepool { controller.loadOlderWindow() })
        olderPages += 1
        seen.formUnion(controller.days.map(\.dayKey))
        maxDocuments = max(maxDocuments, controller.cache.documents.count)
        #expect(controller.days.count <= 60)
        #expect(controller.cache.documents.count <= 61)
        #expect(controller.days.map(\.date) == controller.days.map(\.date).sorted(by: >))
        #expect(Set(controller.days.map(\.dayKey)).count == controller.days.count)
        #expect(controller.topSpacerHeight >= 0 && controller.bottomSpacerHeight >= 0)
    }
    #expect(olderPages > 100 && olderPages < 200)
    #expect(seen.count == dates.count)
    #expect(controller.days.last?.date == first)

    let oldAnchor = try #require(controller.days.first)
    controller.updateViewState(StreamViewState(dayKey: DayFormatting.dayKey(for: today, calendar: calendar),
                                              scrollDayKey: oldAnchor.dayKey, scrollOffset: 82, selectionLocation: 5))
    let other = try #require(controller.createStream(name: "Temporary switch"))
    #expect(controller.stream?.id == other.id)
    controller.selectStream(stream.id)
    #expect(controller.activeDate == today)
    #expect(controller.days.first?.date == oldAnchor.date)
    #expect(!controller.days.contains { $0.date == today })
    // The caret can remain on an offscreen day; it must not be inserted across a five-year gap.
    #expect(controller.currentViewState.scrollOffset == 82)
    controller.setActiveDate(oldAnchor.date)
    controller.updateViewState(StreamViewState(dayKey: oldAnchor.dayKey, scrollDayKey: oldAnchor.dayKey,
                                              scrollOffset: 82, selectionLocation: 5))
    controller.selectStream(other.id)
    #expect(controller.stream?.id == other.id)
    controller.selectStream(stream.id)
    #expect(controller.days.first?.date == oldAnchor.date)
    #expect(controller.currentViewState.scrollOffset == 82)
    #expect(controller.activeDocument?.text == sources[oldAnchor.dayKey])

    var newerPages = 0
    while autoreleasepool(invoking: { controller.loadNewerWindow() }), newerPages < 200 {
        newerPages += 1
        maxDocuments = max(maxDocuments, controller.cache.documents.count)
        #expect(controller.days.count <= 60)
        #expect(controller.cache.documents.count <= 62) // visible days, today and the retained caret day
        #expect(controller.topSpacerHeight >= 0 && controller.bottomSpacerHeight >= 0)
        for document in controller.days { #expect(document.text == sources[document.dayKey]) }
    }
    #expect(newerPages > 100 && newerPages < 200)
    #expect(controller.days.first?.date == today)
    #expect(controller.topSpacerHeight == 0)
    #expect(controller.canLoadOlderDays)

    controller.jumpToDate(first)
    #expect(controller.activeDocument?.text == sources[DayFormatting.dayKey(for: first, calendar: calendar)])
    controller.updateText(for: first, text: "Edited after a five-year jump")
    controller.jumpToToday()
    #expect(controller.flushAllSaves())
    #expect(try store.loadDay(first, in: stream).text == "Edited after a five-year jump")
    #expect(controller.days.first?.date == today)
    print("Five-year history: \(dates.count) days, \(olderPages) older + \(newerPages) newer pages, max \(maxDocuments) cached documents, \(String(format: "%.2f", Date().timeIntervalSince(started)))s")
}

@Test
func restoringChangedRowHeightsCannotConsumeUnrestoredHistory() {
    let calendar = historyCalendar
    let today = calendar.date(from: DateComponents(year: 2026, month: 9, day: 27))!
    let dates = (0..<100).map { calendar.addingDays(-$0, to: today) }
    var state = TimelineWindowState(dates: Array(dates.prefix(20)), retainedDayCount: 20, batchSize: 10)
    state.appendOlderDates(Array(dates[20..<30])) { _ in 100 }
    #expect(state.topSpacerHeight == 1_000)
    // Wider text or a source-mode change must consume exactly the old geometry.
    state.prependNewerDates(Array(dates[5..<10])) { _ in 2_000 }
    #expect(state.topSpacerHeight == 500)
    state.prependNewerDates(Array(dates[0..<5])) { _ in 2_000 }
    #expect(state.topSpacerHeight == 0)
    #expect(state.dates.first == today)
}

@Test @MainActor
func sparseImportedHistoryReturnsAcrossYearsWithoutBlankDays() throws {
    let calendar = historyCalendar
    let today = calendar.date(from: DateComponents(year: 2026, month: 9, day: 27))!
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("current-sparse-history-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }
    let store = StreamStore(libraryRoot: root, calendar: calendar)
    let stream = try store.defaultStream()
    let dates = (0..<100).map { calendar.addingDays(-$0 * 40, to: today) }
    for date in dates {
        let url = store.dayURL(for: date, in: stream)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "Sparse imported note".write(to: url, atomically: true, encoding: .utf8)
    }
    let controller = TimelineController(store: store, cache: DayCache(maxCleanDocuments: 30),
                                        historyWindowDayCount: 30, now: today)
    controller.bootstrapIfNeeded(now: today)
    var seen = Set(controller.days.map(\.date))
    for _ in 0..<10 {
        if !controller.loadOlderWindow() { break }
        seen.formUnion(controller.days.map(\.date))
        #expect(controller.cache.documents.count <= 31)
    }
    #expect(seen == Set(dates))
    #expect(controller.days.last?.date == dates.last)
    for _ in 0..<10 {
        if !controller.loadNewerWindow() { break }
        #expect(controller.cache.documents.count <= 31)
        #expect(controller.days.allSatisfy { dates.contains($0.date) })
    }
    #expect(controller.days.first?.date == today)
    #expect(controller.topSpacerHeight == 0)
    #expect(controller.canLoadOlderDays)
    for _ in 0..<10 {
        if !controller.canLoadOlderDays { break }
        #expect(controller.loadOlderWindow())
    }
    #expect(controller.days.last?.date == dates.last)
}

@Test
func timelineSpacersConserveVaryingRowHeightsAcrossLongRoundTrip() {
    let calendar = historyCalendar
    let today = calendar.date(from: DateComponents(year: 2026, month: 9, day: 27))!
    let dates = (0..<1830).map { calendar.addingDays(-$0, to: today) }
    let heights = Dictionary(uniqueKeysWithValues: dates.enumerated().map { ($0.element, CGFloat($0.offset.isMultiple(of: 17) ? 4_500 : 97)) })
    let height: (Date) -> CGFloat = { heights[$0]! }
    var state = TimelineWindowState(dates: Array(dates.prefix(30)), retainedDayCount: 60, batchSize: 15)
    for start in stride(from: 30, to: dates.count, by: 15) {
        state.appendOlderDates(Array(dates[start..<min(start + 15, dates.count)]), heightForDate: height)
        let loadedHeight = state.dates.reduce(CGFloat(0)) { $0 + height($1) }
        let expected = dates.prefix(min(start + 15, dates.count)).reduce(CGFloat(0)) { $0 + height($1) }
        #expect(state.topSpacerHeight + loadedHeight + state.bottomSpacerHeight == expected)
        #expect(state.dates.count <= 60)
    }
    while let newest = state.dates.first, let end = dates.firstIndex(of: newest), end > 0 {
        state.prependNewerDates(Array(dates[max(0, end - 15)..<end]), heightForDate: height)
        #expect(state.topSpacerHeight + state.dates.reduce(CGFloat(0)) { $0 + height($1) } + state.bottomSpacerHeight == dates.reduce(CGFloat(0)) { $0 + height($1) })
    }
    #expect(state.dates == Array(dates.prefix(60)))
    #expect(state.topSpacerHeight == 0)
}
