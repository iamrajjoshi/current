import Foundation
import Testing
@testable import CurrentFeature

private var polishCalendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    return calendar
}

@Test @MainActor
func ordinaryStreamSelectionDoesNotAccumulateOrReplaceExplicitTabs() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("current-tabs-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    let controller = TimelineController(store: StreamStore(libraryRoot: root), autosaveDelay: 60)
    controller.bootstrapIfNeeded()
    let daily = try #require(controller.stream)
    controller.updateText(for: controller.today, text: "Preserve this before switching")
    let work = try #require(controller.createStream(name: "Work"))
    let research = try #require(controller.createStream(name: "Research"))
    controller.selectStream(daily.id)
    #expect(controller.openStreamIDs.isEmpty)
    #expect(try controller.store.loadDay(controller.today, in: daily).text == "Preserve this before switching")
    controller.openStreamTab(daily.id)
    controller.openStreamTab(work.id)
    controller.openStreamTab(daily.id)
    #expect(controller.openStreamIDs == [daily.id, work.id])
    controller.selectStream(research.id)
    #expect(controller.openStreamIDs == [daily.id, work.id])
    #expect(controller.stream?.id == research.id)
    #expect(controller.flushAllSaves())
    let reopened = TimelineController(store: StreamStore(libraryRoot: root))
    reopened.bootstrapIfNeeded()
    #expect(reopened.stream?.id == research.id)
    #expect(reopened.openStreamIDs == [daily.id, work.id])
    reopened.closeStreamTab(daily.id)
    #expect(reopened.openStreamIDs == [work.id])
    #expect(reopened.stream?.id == research.id)
}

@Test
func searchExcerptRemovesMarkdownAndRetainsUnicodeSourceCoordinates() throws {
    let prefix = String(repeating: "Earlier context. ", count: 12)
    let source = "# A heading\n\n" + prefix + "- [ ] **Cafe\u{301} 📝 needle** with [readable label](https://example.com) and `code`.\n"
        + String(repeating: "Following context. ", count: 12)
    let sourceRange = try #require(source.range(of: "CAFE", options: [.caseInsensitive, .diacriticInsensitive]))
    let rawRange = NSRange(sourceRange, in: source)
    let excerpt = MarkdownSearchExcerpt.make(source: source, matchRange: rawRange)
    #expect(excerpt.text.hasPrefix("… ") && excerpt.text.hasSuffix(" …"))
    #expect(!excerpt.text.contains("**"))
    #expect(excerpt.text.contains("readable label"))
    #expect(!excerpt.text.contains("https://"))
    #expect(!excerpt.text.contains("`"))
    #expect((excerpt.text as NSString).substring(with: excerpt.matchRange) == "Cafe\u{301}")
    #expect((source as NSString).substring(with: rawRange) == "Cafe\u{301}")
    #expect(!excerpt.text.contains("\n"))
}

@Test
func searchExcerptsKeepCodeAndSimplifyTableAndImageContext() throws {
    let fixtures = [
        ("```swift\nlet value = a * b\n```", "value", "let value = a * b"),
        ("| Owner | Status |\n| --- | --- |\n| Maya | Ready |", "Maya", "Owner Status Maya Ready"),
        ("![A diagram of the pipeline](attachments/diagram.png)", "pipeline", "A diagram of the pipeline")
    ]
    for (source, query, expected) in fixtures {
        let range = NSRange(try #require(source.range(of: query)), in: source)
        let excerpt = MarkdownSearchExcerpt.make(source: source, matchRange: range)
        #expect(excerpt.text == expected)
        #expect((excerpt.text as NSString).substring(with: excerpt.matchRange) == query)
    }
    let source = "[Reference](https://example.com/target)"
    let range = NSRange(try #require(source.range(of: "example.com")), in: source)
    let excerpt = MarkdownSearchExcerpt.make(source: source, matchRange: range)
    #expect((excerpt.text as NSString).substring(with: excerpt.matchRange) == "example.com")
}

@Test
func collapsedPreviewRemovesLeadingFenceAndLinkSyntax() {
    #expect(MarkdownSearchExcerpt.preview(source: "```swift\nlet name = value\n```\n") == "let name = value")
    #expect(MarkdownSearchExcerpt.preview(source: "# [A readable title](https://example.com)\n") == "A readable title")
    #expect(MarkdownSearchExcerpt.preview(source: "## 📝 café", limit: 1) == "📝…")
    #expect(MarkdownSearchExcerpt.preview(source: "\n\t") == "")
}

@Test @MainActor
func historySearchUsesUnsavedSnapshotsAndRemovesObsoleteSavedMatches() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("current-search-drafts-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    let controller = TimelineController(store: StreamStore(libraryRoot: root), autosaveDelay: 60)
    controller.bootstrapIfNeeded()
    let stream = try #require(controller.stream)
    controller.updateText(for: controller.today, text: "Old saved needle")
    #expect(controller.flushAllSaves())
    controller.updateText(for: controller.today, text: "New unsaved replacement")
    func search(_ query: String) async throws {
        controller.searchHistory(query)
        for _ in 0..<100 {
            if !controller.isSearching { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(!controller.isSearching)
    }
    try await search("replacement")
    let match = try #require(controller.searchResults.first)
    #expect(("New unsaved replacement" as NSString).substring(with: match.matchRange) == "replacement")
    #expect(try controller.store.loadDay(controller.today, in: stream).lastSavedText == "Old saved needle")
    try await search("needle")
    #expect(controller.searchResults.isEmpty)
    let missing = controller.store.calendar.addingDays(-20, to: controller.today)
    controller.jumpToDate(missing)
    controller.updateText(for: missing, text: "Brand new unwritten day")
    try await search("unwritten")
    #expect(controller.searchResults.first?.date == missing)
    #expect(!controller.store.dayFileExists(for: missing, in: stream))
}

@Test @MainActor
func calendarDotsUseWrittenContentAndDirtyBuffersWithoutCreatingDays() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("current-calendar-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    let calendar = polishCalendar
    let today = calendar.date(from: DateComponents(year: 2026, month: 9, day: 28))!
    let store = StreamStore(libraryRoot: root, calendar: calendar)
    let controller = TimelineController(store: store, autosaveDelay: 60, now: today)
    controller.bootstrapIfNeeded(now: today)
    let stream = try #require(controller.stream)
    let written = calendar.addingDays(-2, to: today)
    let blank = calendar.addingDays(-3, to: today)
    for (date, text) in [(written, "Written note"), (blank, " \n\t ")] {
        let url = store.dayURL(for: date, in: stream)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }
    #expect(controller.writtenDayKeys(inMonth: today) == ["2026-09-26"])
    controller.updateText(for: today, text: "Unsaved today")
    #expect(controller.writtenDayKeys(inMonth: today) == ["2026-09-26", "2026-09-28"])
    controller.jumpToDate(written)
    controller.updateText(for: written, text: "")
    #expect(controller.writtenDayKeys(inMonth: today) == ["2026-09-28"])
    let nextMonth = calendar.date(byAdding: .month, value: 1, to: today)!
    #expect(controller.writtenDayKeys(inMonth: nextMonth).isEmpty)
    #expect(!FileManager.default.fileExists(atPath: store.dayURL(for: nextMonth, in: stream).deletingLastPathComponent().path))
    #expect(!store.dayFileExists(for: calendar.addingDays(-1, to: today), in: stream))
    #expect(controller.flushAllSaves())
    #expect(controller.writtenDayKeys(inMonth: today) == ["2026-09-28"])
    try "New external writing".write(to: store.dayURL(for: blank, in: stream), atomically: true, encoding: .utf8)
    #expect(controller.writtenDayKeys(inMonth: today) == ["2026-09-25", "2026-09-28"])
    _ = try #require(controller.createStream(name: "Other"))
    #expect(controller.writtenDayKeys(inMonth: today).isEmpty)
}

private func emptyHistoryFixture(count: Int = 12) -> [DayDocument] {
    let calendar = polishCalendar
    let today = calendar.date(from: DateComponents(year: 2026, month: 9, day: 28))!
    let streamID = UUID()
    return (0..<count).map { offset in
        let date = calendar.addingDays(-offset, to: today)
        return DayDocument(streamID: streamID, date: date,
                           fileURL: URL(fileURLWithPath: "/fixture/\(offset).md"), text: "",
                           libraryID: "/fixture", dayKey: DayFormatting.dayKey(for: date, calendar: calendar))
    }
}

@Test
func emptyHistoryGroupsPreserveTodayActiveDirtyAndJumpedDays() {
    var days = emptyHistoryFixture()
    days[4].text = " "; days[4].isDirty = true
    days[7].text = "A saved note"
    let rows = TimelineHistoryPresentation.rows(days: days, today: days[0].date, activeDayID: days[2].id,
        requestedDayID: days[9].id, expandedEmptyDayIDs: [days[11].id], calendar: polishCalendar)
    for index in [0, 2, 4, 7, 9, 11] {
        #expect(rows.contains { if case .day(let document) = $0 { document.id == days[index].id } else { false } })
    }
    for day in days { #expect(rows.filter { $0.contains(dayID: day.id) }.count == 1) }
    let groups = rows.compactMap { if case .emptyDays(let group) = $0 { group } else { nil } }
    #expect(groups.map { $0.days.count } == [1, 1, 2, 1, 2])
    let revealed = TimelineHistoryPresentation.rows(days: days, today: days[0].date, activeDayID: days[2].id,
        requestedDayID: days[9].id, expandedEmptyDayIDs: Set(days.map(\.id)), calendar: polishCalendar)
    #expect(revealed.filter { if case .day = $0 { true } else { false } }.count == days.count)
    #expect(revealed.allSatisfy { if case .emptyDays(let group) = $0 { group.isExpanded } else { true } })
    for day in days { #expect(revealed.filter { $0.contains(dayID: day.id) }.count == 1) }
    let collapsedAgain = TimelineHistoryPresentation.rows(days: days, today: days[0].date, activeDayID: days[2].id,
        requestedDayID: days[9].id, expandedEmptyDayIDs: [], calendar: polishCalendar)
    #expect(collapsedAgain.count < revealed.count)
}

@Test
func emptyHistorySpacerCorrectionSurvivesPagingAndRoundTrip() {
    let days = emptyHistoryFixture(count: 25)
    let rows = TimelineHistoryPresentation.rows(days: Array(days[1...10]), today: days[0].date,
        activeDayID: nil, requestedDayID: nil, expandedEmptyDayIDs: [], calendar: polishCalendar)
    var ledger = TimelineEmptyDaySpacerLedger()
    let older = Array(days[11...20])
    let compacted = ledger.heights(previous: rows, days: older, top: 360, bottom: 0)
    #expect(abs(compacted.top - 30) < 0.001)
    #expect(compacted.bottom == 0)
    let restored = ledger.heights(previous: [], days: Array(days[1...10]), top: 0, bottom: 360)
    #expect(restored.top == 0)
    #expect(restored.bottom == 360)
    let reset = ledger.heights(previous: rows, days: [days[0]], top: 0, bottom: 0)
    #expect(reset.top == 0 && reset.bottom == 0)
}
