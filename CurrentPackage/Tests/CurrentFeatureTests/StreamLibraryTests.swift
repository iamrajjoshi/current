import Foundation
import Testing
@testable import CurrentFeature

private func libraryTestRoot() throws -> URL {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("current-library-test-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
}

private var libraryTestCalendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    return calendar
}

private var libraryTestToday: Date {
    libraryTestCalendar.date(from: DateComponents(year: 2026, month: 9, day: 27))!
}

@Test @MainActor
func streamsKeepSameDayTextAndPendingSavesSeparate() throws {
    let root = try libraryTestRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let store = StreamStore(libraryRoot: root, calendar: libraryTestCalendar)
    let controller = TimelineController(store: store, autosaveDelay: 60, now: libraryTestToday)
    controller.bootstrapIfNeeded(now: libraryTestToday)
    let daily = try #require(controller.stream)
    let dailyID = try #require(controller.days.first?.documentID)
    controller.updateText(for: libraryTestToday, text: "Daily draft")
    let work = try #require(controller.createStream(name: "Work"))
    controller.updateText(for: libraryTestToday, text: "Work draft")
    #expect(controller.days.first?.documentID != dailyID)
    #expect(try store.loadDay(libraryTestToday, in: daily).text == "Daily draft")
    // A late callback from an old view stays attached to its original destination.
    controller.updateText(for: libraryTestToday, streamID: daily.id, libraryID: store.libraryID, text: "Daily late edit")
    #expect(controller.activeDocument?.text == "Work draft")
    #expect(controller.flushAllSaves())
    #expect(try store.loadDay(libraryTestToday, in: daily).text == "Daily late edit")
    #expect(try store.loadDay(libraryTestToday, in: work).text == "Work draft")
}

@Test @MainActor
func streamOrganizationChangesMetadataWithoutMovingNotes() throws {
    let root = try libraryTestRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let controller = TimelineController(store: StreamStore(libraryRoot: root), now: libraryTestToday)
    controller.bootstrapIfNeeded(now: libraryTestToday)
    let folder = try #require(controller.createFolder(name: "Work"))
    let stream = try #require(controller.createStream(name: "TPRM", folderID: folder.id))
    let originalURL = try #require(controller.activeDocument?.fileURL)
    controller.updateText(for: controller.today, text: "Evidence review")
    #expect(controller.flushAllSaves())
    controller.renameStream(stream.id, name: "Vendor reviews")
    controller.setStreamPinned(stream.id, isPinned: true)
    controller.removeFolder(folder.id)
    let renamed = try #require(controller.streams.first { $0.id == stream.id })
    #expect(renamed.name == "Vendor reviews")
    #expect(renamed.folderID == nil)
    #expect(renamed.isPinned)
    #expect(renamed.rootURL == stream.rootURL)
    controller.archiveStream(stream.id)
    #expect(controller.streams.first { $0.id == stream.id }?.isArchived == true)
    #expect(try String(contentsOf: originalURL, encoding: .utf8) == "Evidence review")
    controller.restoreStream(stream.id)
    #expect(controller.streams.first { $0.id == stream.id }?.isArchived == false)
    let library = try controller.store.loadLibrary()
    #expect(library.streams.first { $0.id == stream.id }?.name == "Vendor reviews")
}

@Test
func legacyMigrationPreservesIdentityBytesAndRelocatesPaths() throws {
    let root = try libraryTestRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let original = root.appendingPathComponent("original")
    let copy = root.appendingPathComponent("copy")
    let streamRoot = original.appendingPathComponent("streams/daily")
    try FileManager.default.createDirectory(at: streamRoot, withIntermediateDirectories: true)
    let legacy = Stream(name: "Daily", slug: "daily", rootURL: streamRoot, createdAt: libraryTestToday)
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let originalMetadata = try encoder.encode(legacy)
    try originalMetadata.write(to: streamRoot.appendingPathComponent(".current-stream.json"))
    let store = StreamStore(libraryRoot: original, calendar: libraryTestCalendar)
    let dayURL = store.dayURL(for: libraryTestToday, in: legacy)
    try FileManager.default.createDirectory(at: dayURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    let bytes = Data("# Original\n\nCafe\u{301} 📝\n".utf8)
    try bytes.write(to: dayURL)
    let adopted = try store.defaultStream()
    #expect(adopted.id == legacy.id)
    #expect(try Data(contentsOf: dayURL) == bytes)
    #expect(try Data(contentsOf: streamRoot.appendingPathComponent(".current-stream.json.backup")) == originalMetadata)
    #expect(try store.defaultStream().id == legacy.id)
    let manifest = try String(contentsOf: store.manifestURL, encoding: .utf8)
    #expect(!manifest.contains(original.path))
    try FileManager.default.copyItem(at: original, to: copy)
    let copiedStore = StreamStore(libraryRoot: copy, calendar: libraryTestCalendar)
    let copiedStream = try copiedStore.defaultStream()
    #expect(copiedStream.id == legacy.id)
    #expect(copiedStream.rootURL.path.hasPrefix(copy.path))
    var document = try copiedStore.loadDay(libraryTestToday, in: copiedStream)
    #expect(document.documentID != (try store.loadDay(libraryTestToday, in: adopted)).documentID)
    document.text = "Copy only"
    document.isDirty = true
    try copiedStore.saveDay(document)
    #expect(try Data(contentsOf: dayURL) == bytes)
}

@Test @MainActor
func directDateJumpAndSearchReachUnloadedHistory() throws {
    let root = try libraryTestRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let store = StreamStore(libraryRoot: root, calendar: libraryTestCalendar)
    let stream = try store.defaultStream()
    let oldDate = libraryTestCalendar.date(from: DateComponents(year: 2021, month: 2, day: 3))!
    var old = try store.loadDay(oldDate, in: stream)
    old.text = "A searchable café from years ago"
    old.isDirty = true
    try store.saveDay(old)
    let matches = LibrarySearch.search(query: "CAFE", streams: [stream], libraryRoot: root, calendar: libraryTestCalendar)
    #expect(matches.count == 1)
    #expect(matches.first?.dayKey == "2021-02-03")
    #expect(matches.first?.matchRange.length == 4)
    let controller = TimelineController(store: store, recentDayCount: 1, now: libraryTestToday)
    controller.bootstrapIfNeeded(now: libraryTestToday)
    #expect(!controller.days.contains { $0.dayKey == "2021-02-03" })
    controller.openSearchResult(try #require(matches.first))
    #expect(controller.activeDocument?.text == old.text)
    #expect(controller.scrollRequest?.selectionRange == matches.first?.matchRange)
    let missing = libraryTestCalendar.date(from: DateComponents(year: 2019, month: 1, day: 1))!
    controller.jumpToDate(missing)
    #expect(controller.days.first?.dayKey == "2019-01-01")
    #expect(!store.dayFileExists(for: missing, in: stream))
}

@Test @MainActor
func streamSwitchAndRelaunchRestoreViewStateAndTabs() throws {
    let root = try libraryTestRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let store = StreamStore(libraryRoot: root, calendar: libraryTestCalendar)
    let controller = TimelineController(store: store, now: libraryTestToday)
    controller.bootstrapIfNeeded(now: libraryTestToday)
    let daily = try #require(controller.stream)
    let other = try #require(controller.createStream(name: "Research"))
    controller.updateViewState(StreamViewState(dayKey: "2026-09-27", scrollDayKey: "2026-09-27", scrollOffset: 74,
                                             selectionLocation: 9, selectionLength: 2))
    controller.selectStream(daily.id)
    controller.selectStream(other.id)
    #expect(controller.currentViewState.scrollOffset == 74)
    #expect(controller.scrollRequest?.selectionRange == NSRange(location: 9, length: 2))
    #expect(controller.flushAllSaves())
    let reopened = TimelineController(store: store, now: libraryTestToday)
    reopened.bootstrapIfNeeded(now: libraryTestToday)
    #expect(reopened.stream?.id == other.id)
    #expect(reopened.openStreamIDs == controller.openStreamIDs)
    #expect(reopened.currentViewState.scrollOffset == 74)
    reopened.closeStreamTab(other.id)
    #expect(reopened.streams.contains { $0.id == other.id && !$0.isArchived })
}

@Test @MainActor
func unsavedConflictRemainsRecoverableAcrossSwitchAndRootChange() throws {
    let root = try libraryTestRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let original = root.appendingPathComponent("original")
    let store = StreamStore(libraryRoot: original, calendar: libraryTestCalendar)
    let controller = TimelineController(store: store, autosaveDelay: 60, now: libraryTestToday)
    controller.bootstrapIfNeeded(now: libraryTestToday)
    let daily = try #require(controller.stream)
    controller.updateText(for: libraryTestToday, text: "Unsaved local version")
    let url = try #require(controller.activeDocument?.fileURL)
    try "External version".write(to: url, atomically: true, encoding: .utf8)
    _ = controller.createStream(name: "Other")
    #expect(controller.hasUnsavedChanges)
    #expect(controller.conflicts.count == 1)
    controller.apply(configuration: CurrentConfiguration(libraryRoot: root.appendingPathComponent("different")))
    #expect(controller.store.libraryRoot.path == original.standardizedFileURL.path)
    #expect(!controller.flushAllSaves())
    let recovered = try StreamStore(libraryRoot: original, calendar: libraryTestCalendar).loadDay(libraryTestToday, in: daily)
    #expect(recovered.text == "Unsaved local version")
    #expect(recovered.isDirty)
    #expect(try String(contentsOf: url, encoding: .utf8) == "External version")
}

@Test
func invalidUTF8NeverLoadsAsAnEmptyWritableDocument() throws {
    let root = try libraryTestRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let store = StreamStore(libraryRoot: root, calendar: libraryTestCalendar)
    let stream = try store.defaultStream()
    let url = store.dayURL(for: libraryTestToday, in: stream)
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let invalid = Data([0xff, 0xfe, 0xff])
    try invalid.write(to: url)
    #expect(throws: StreamStoreError.self) { try store.loadDay(libraryTestToday, in: stream) }
    #expect(try Data(contentsOf: url) == invalid)
}

@Test @MainActor
func keepBothUsesTheLatestLocalAndDiskConflictVersions() throws {
    let root = try libraryTestRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let store = StreamStore(libraryRoot: root, calendar: libraryTestCalendar)
    let controller = TimelineController(store: store, autosaveDelay: 60, now: libraryTestToday)
    controller.bootstrapIfNeeded(now: libraryTestToday)
    let url = try #require(controller.activeDocument?.fileURL)
    controller.updateText(for: libraryTestToday, text: "First local draft")
    try "First external edit".write(to: url, atomically: true, encoding: .utf8)
    controller.save(libraryTestToday)
    let conflict = try #require(controller.conflicts.first)
    controller.updateText(for: libraryTestToday, text: "Latest local draft")
    try "Latest external edit".write(to: url, atomically: true, encoding: .utf8)
    controller.keepBothConflictVersions(conflict.id)
    #expect(controller.conflicts.isEmpty)
    #expect(controller.activeDocument?.text == "Latest external edit")
    let copies = try FileManager.default.contentsOfDirectory(at: url.deletingLastPathComponent(), includingPropertiesForKeys: nil)
        .filter { $0.lastPathComponent.contains("conflict-") }
    #expect(copies.count == 1)
    #expect(try String(contentsOf: #require(copies.first), encoding: .utf8) == "Latest local draft")
    #expect(controller.flushAllSaves())
    #expect(try String(contentsOf: url, encoding: .utf8) == "Latest external edit")
}

@Test @MainActor
func fileWatcherRefreshesAnExternalEditWithoutTheMaintenanceTimer() async throws {
    let root = try libraryTestRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let controller = TimelineController(store: StreamStore(libraryRoot: root, calendar: libraryTestCalendar), now: libraryTestToday)
    controller.bootstrapIfNeeded(now: libraryTestToday)
    let url = try #require(controller.activeDocument?.fileURL)
    try "Written by another editor".write(to: url, atomically: true, encoding: .utf8)
    for _ in 0..<30 {
        if controller.activeDocument?.text == "Written by another editor" { break }
        try await Task.sleep(for: .milliseconds(100))
    }
    #expect(controller.activeDocument?.text == "Written by another editor")
}

@Test @MainActor
func flushAfterUndoDoesNotResurrectAnOlderRecoverySnapshot() throws {
    let root = try libraryTestRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let store = StreamStore(libraryRoot: root, calendar: libraryTestCalendar)
    let controller = TimelineController(store: store, autosaveDelay: 60, now: libraryTestToday)
    controller.bootstrapIfNeeded(now: libraryTestToday)
    let stream = try #require(controller.stream)
    controller.updateText(for: libraryTestToday, text: "Later undone")
    try store.writeRecovery(#require(controller.activeDocument))
    controller.updateText(for: libraryTestToday, text: "")
    #expect(controller.flushAllSaves())
    #expect(try store.loadDay(libraryTestToday, in: stream).text == "")
    #expect(!((try store.loadDay(libraryTestToday, in: stream)).isDirty))
}

@Test @MainActor
func copiedLibraryRejectsCallbacksFromTheOriginalLibrary() throws {
    let root = try libraryTestRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let original = root.appendingPathComponent("original")
    let copied = root.appendingPathComponent("copied")
    let store = StreamStore(libraryRoot: original, calendar: libraryTestCalendar)
    let controller = TimelineController(store: store, now: libraryTestToday)
    controller.bootstrapIfNeeded(now: libraryTestToday)
    let id = try #require(controller.stream?.id)
    controller.updateText(for: libraryTestToday, text: "Original saved text")
    #expect(controller.flushAllSaves())
    try FileManager.default.copyItem(at: original, to: copied)
    controller.apply(configuration: CurrentConfiguration(libraryRoot: copied))
    #expect(controller.stream?.id == id)
    controller.updateText(for: libraryTestToday, streamID: id, libraryID: store.libraryID, text: "Stale callback")
    #expect(controller.activeDocument?.text == "Original saved text")
    controller.updateText(for: libraryTestToday, text: "Copy saved text")
    #expect(controller.flushAllSaves())
    #expect(try store.loadDay(libraryTestToday, in: store.defaultStream()).text == "Original saved text")
}

@Test @MainActor
func archivedSearchOpensTheCorrectStreamWithoutRestoringIt() throws {
    let root = try libraryTestRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let store = StreamStore(libraryRoot: root, calendar: libraryTestCalendar)
    let controller = TimelineController(store: store, now: libraryTestToday)
    controller.bootstrapIfNeeded(now: libraryTestToday)
    let archived = try #require(controller.createStream(name: "Finished project"))
    controller.updateText(for: libraryTestToday, text: "Archived unique needle")
    #expect(controller.flushAllSaves())
    controller.archiveStream(archived.id)
    let result = try #require(LibrarySearch.search(query: "unique needle", streams: controller.streams,
                                                    libraryRoot: root, calendar: libraryTestCalendar).first)
    controller.openSearchResult(result)
    #expect(controller.stream?.id == archived.id)
    #expect(controller.stream?.isArchived == true)
    #expect(controller.activeDocument?.text == "Archived unique needle")
    #expect(controller.scrollRequest?.selectionRange == result.matchRange)
}

@Test @MainActor
func relaunchRestoresDistinctCaretDayAndScrollAnchorDay() throws {
    let root = try libraryTestRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let store = StreamStore(libraryRoot: root, calendar: libraryTestCalendar)
    var stream = try store.defaultStream()
    stream.createdAt = libraryTestCalendar.addingDays(-3, to: libraryTestToday)
    try store.saveLibrary(streams: [stream], folders: [])
    let controller = TimelineController(store: store, now: libraryTestToday)
    controller.bootstrapIfNeeded(now: libraryTestToday)
    controller.updateText(for: libraryTestToday, text: "Caret belongs here")
    controller.updateViewState(StreamViewState(dayKey: "2026-09-27", scrollDayKey: "2026-09-26",
                                             scrollOffset: 34, selectionLocation: 6, selectionLength: 2))
    #expect(controller.flushAllSaves())
    let reopened = TimelineController(store: store, now: libraryTestToday)
    reopened.bootstrapIfNeeded(now: libraryTestToday)
    #expect(reopened.activeDocument?.dayKey == "2026-09-27")
    #expect(reopened.days.contains { $0.dayKey == "2026-09-27" })
    #expect(reopened.scrollRequest?.dayID == reopened.dayID(for: libraryTestCalendar.addingDays(-1, to: libraryTestToday)))
    #expect(reopened.scrollRequest?.selectionRange == NSRange(location: 6, length: 2))
    #expect(reopened.scrollRequest?.offset == 34)
}

@Test @MainActor
func fileWatcherDiscoversNewHistoricalNotesWithoutNavigation() async throws {
    let root = try libraryTestRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let store = StreamStore(libraryRoot: root, calendar: libraryTestCalendar)
    let controller = TimelineController(store: store, now: libraryTestToday)
    controller.bootstrapIfNeeded(now: libraryTestToday)
    let stream = try #require(controller.stream)
    let oldDate = libraryTestCalendar.addingDays(-20, to: libraryTestToday)
    var external = try store.loadDay(oldDate, in: stream)
    external.text = "Created outside the application"
    external.isDirty = true
    try store.saveDay(external)
    for _ in 0..<30 {
        if controller.days.contains(where: { $0.dayKey == external.dayKey }) { break }
        try await Task.sleep(for: .milliseconds(100))
    }
    #expect(controller.days.contains { $0.dayKey == external.dayKey && $0.text == external.text })
}
