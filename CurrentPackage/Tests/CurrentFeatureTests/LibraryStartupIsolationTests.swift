import Foundation
import Testing
@testable import CurrentFeature

@Suite(.serialized)
@MainActor
struct LibraryStartupIsolationTests {
    @Test(arguments: [false, true])
    func configuringAnotherLibraryDoesNotSaveAnUnopenedSession(existingSession: Bool) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("current-startup-isolation-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let original = StreamStore(libraryRoot: root.appendingPathComponent("original"))
        let configured = root.appendingPathComponent("configured")
        let originalSessionURL = original.libraryRoot.appendingPathComponent(".current-session.json")
        if existingSession {
            let stream = try original.defaultStream()
            var session = LibrarySession()
            session.selectedStreamID = stream.id
            session.openStreamIDs = [stream.id]
            session.views[stream.id] = StreamViewState(dayKey: "2026-09-29", scrollDayKey: "2026-09-30",
                scrollOffset: 86, selectionLocation: 14, selectionLength: 5, minimizedDayKeys: ["2026-09-27"],
                editorHadFocus: false, visibleDayKey: "2026-09-29")
            try original.saveSession(session)
        }
        let originalBytes = try? Data(contentsOf: originalSessionURL)
        let controller = TimelineController(store: original)
        var configuration = CurrentConfiguration.default
        configuration.libraryRoot = configured
        controller.apply(configuration: configuration)
        #expect(!controller.isBootstrapped)
        #expect(controller.store.libraryRoot == configured)
        #expect((try? Data(contentsOf: originalSessionURL)) == originalBytes)
        // Closing or resigning focus before bootstrap must not manufacture a
        // session for the newly configured, still-unopened library either.
        #expect(controller.flushAllSaves())
        #expect(!FileManager.default.fileExists(atPath: configured.appendingPathComponent(".current-session.json").path))
        controller.bootstrapIfNeeded()
        #expect(controller.isBootstrapped)
        #expect(FileManager.default.fileExists(atPath: configured.appendingPathComponent(".current-library.json").path))
        #expect((try? Data(contentsOf: originalSessionURL)) == originalBytes)
    }

    @Test func switchingAwayFromAnInitializedLibraryStillSavesNotesAndPosition() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("current-open-library-switch-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let original = StreamStore(libraryRoot: root.appendingPathComponent("original"))
        let controller = TimelineController(store: original, autosaveDelay: 60)
        controller.bootstrapIfNeeded()
        let stream = try #require(controller.stream)
        let today = controller.today
        controller.updateText(for: today, text: "Unsaved writing before changing the library.")
        let dayKey = DayFormatting.dayKey(for: today, calendar: original.calendar)
        let position = StreamViewState(dayKey: dayKey, scrollDayKey: dayKey, scrollOffset: 23,
                                       selectionLocation: 8, selectionLength: 3, visibleDayKey: dayKey)
        controller.updateViewState(position)
        var configuration = CurrentConfiguration.default
        configuration.libraryRoot = root.appendingPathComponent("configured")
        controller.apply(configuration: configuration)
        #expect(try String(contentsOf: original.dayURL(for: today, in: stream), encoding: .utf8)
                == "Unsaved writing before changing the library.")
        #expect(original.loadSession().views[stream.id] == position)
        #expect(controller.store.libraryRoot == configuration.libraryRoot)
        #expect(controller.isBootstrapped)
    }

    @Test func failedBootstrapCannotReplaceAnUnloadedSession() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("current-failed-startup-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try #"{"version":999,"streams":[],"folders":[]}"#.write(to: root.appendingPathComponent(".current-library.json"),
                                                                 atomically: true, encoding: .utf8)
        let sessionURL = root.appendingPathComponent(".current-session.json")
        let saved = Data(#"{"openStreamIDs":[],"views":{}}"#.utf8)
        try saved.write(to: sessionURL)
        let controller = TimelineController(store: StreamStore(libraryRoot: root))
        controller.bootstrapIfNeeded()
        try #require(!controller.isBootstrapped)
        #expect(controller.flushAllSaves())
        #expect(try Data(contentsOf: sessionURL) == saved)
    }
}
