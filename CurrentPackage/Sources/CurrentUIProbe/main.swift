import AppKit
import ApplicationServices
import CurrentFeature
import SwiftUI

@main
struct CurrentUIProbe {
    @MainActor static var nativeInputTiming: [String: Any] = [:]
    @MainActor static var sceneLimitations: [String] = []
    @MainActor static var capturesImages = true
    #if DEBUG
    static let buildConfiguration = "debug"
    #else
    static let buildConfiguration = "release"
    #endif
    @MainActor
    static func main() {
        do {
            try run(Options(arguments: Array(CommandLine.arguments.dropFirst())))
        } catch {
            FileHandle.standardError.write(Data("CurrentUIProbe failed: \(error)\n".utf8))
            exit(1)
        }
    }

    struct Options {
        var output = FileManager.default.temporaryDirectory.appendingPathComponent("current-ui-probe-\(UUID().uuidString)")
        var live = false
        var hold = false
        var exercise = false
        var linksOnly = false
        var calendarOnly = false
        var restorationOnly = false
        var noImages = false
        var emptyToday = false
        var dark = false
        var stress = false
        var stressLines = 1000
        var historyDays = 21
        var width: CGFloat = 1200
        var height: CGFloat = 820

        init(arguments: [String]) throws {
            var index = 0
            while index < arguments.count {
                let argument = arguments[index]
                switch argument {
                case "--live": live = true
                case "--hold": hold = true; live = true
                case "--exercise": exercise = true
                case "--links-only": exercise = true; linksOnly = true
                case "--calendar-only": exercise = true; calendarOnly = true
                case "--restoration-only": restorationOnly = true
                case "--no-images": noImages = true
                case "--empty-today": emptyToday = true
                case "--dark": dark = true
                case "--stress": stress = true
                case "--output", "--width", "--height", "--stress-lines", "--history-days":
                    index += 1
                    guard index < arguments.count else { throw ProbeError("Missing value for \(argument)") }
                    let value = arguments[index]
                    if argument == "--output" {
                        output = URL(fileURLWithPath: value, isDirectory: true)
                    } else if argument == "--stress-lines" {
                        guard let lines = Int(value), (100...5000).contains(lines) else { throw ProbeError("Stress lines must be 100...5000") }
                        stress = true
                        stressLines = lines
                    } else if argument == "--history-days" {
                        guard let days = Int(value), (100...500).contains(days) else { throw ProbeError("History days must be 100...500") }
                        historyDays = days
                    } else {
                        guard let number = Double(value), number.isFinite,
                              number >= (argument == "--width" ? 820 : 640), number <= 4000 else {
                            throw ProbeError("Invalid \(argument): \(value)")
                        }
                        if argument == "--width" { width = number } else { height = number }
                    }
                default:
                    throw ProbeError("Usage: CurrentUIProbe [--live|--hold] [--exercise|--links-only|--calendar-only|--restoration-only] [--empty-today] [--stress] [--stress-lines 1000] [--history-days 130] [--no-images] [--dark] [--output directory] [--width 1200] [--height 820]")
                }
                index += 1
            }
            guard !emptyToday || (!exercise && !stress) else { throw ProbeError("--empty-today is a static visual fixture") }
        }
    }

    struct ProbeError: Error, CustomStringConvertible {
        let description: String
        init(_ description: String) { self.description = description }
    }

    @MainActor
    static func run(_ options: Options) throws {
        let started = Date()
        capturesImages = !options.noImages
        var memoryStages: [[String: Any]] = []
        let watchdog = options.stress || options.historyDays > 21 ? stressWatchdog() : nil
        defer { watchdog?.cancel() }
        let app = NSApplication.shared
        app.setActivationPolicy(options.hold ? .regular : .accessory)
        app.appearance = NSAppearance(named: options.dark ? .darkAqua : .aqua)
        app.finishLaunching()
        if options.restorationOnly {
            try exerciseWindowRestoration(options)
            return
        }

        // Every run owns a new library and config. Never load the user's notes or settings.
        let fixture = FileManager.default.temporaryDirectory.appendingPathComponent("current-probe-library-\(UUID().uuidString)")
        let library = fixture.appendingPathComponent("library")
        try FileManager.default.createDirectory(at: options.output, withIntermediateDirectories: true)
        let configURL = fixture.appendingPathComponent("config/current/config.current")
        try FileManager.default.createDirectory(at: configURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let historySetting = options.historyDays > 21 ? "history-window-days = 60\n" : ""
        try "library-root = \(library.path)\nautosave-delay = 0.1\n\(historySetting)".write(to: configURL, atomically: true, encoding: .utf8)
        let locations = CurrentConfigurationLocations(
            environment: ["XDG_CONFIG_HOME": fixture.appendingPathComponent("config").path],
            homeDirectory: fixture,
            applicationSupportDirectory: fixture.appendingPathComponent("support")
        )
        let configuration = CurrentConfigurationStore(locations: locations, homeDirectory: fixture)
        let store = StreamStore(libraryRoot: library)
        let now = Date()
        var stream = try store.defaultStream()
        stream.createdAt = Calendar.current.date(byAdding: .day, value: -options.historyDays, to: now)!
        let work = StreamFolder(name: "Work")
        let personal = StreamFolder(name: "Personal", order: 1)
        try store.saveLibrary(streams: [stream], folders: [work, personal])
        let reviewStream = try store.createStream(name: "TPRM", folderID: work.id)
        _ = try store.createStream(name: "Payments", folderID: work.id)
        _ = try store.createStream(name: "Journal", folderID: personal.id)
        let sampleDate = options.emptyToday ? Calendar.current.date(byAdding: .day, value: -1, to: now)! : now
        var today = try store.loadDay(sampleDate, in: stream, createIfMissing: true)
        try imageFixture(at: today.fileURL.deletingLastPathComponent().appendingPathComponent("attachments/probe.png"))
        let initialSource = sampleNote + (options.stress ? stressAppendix(minimumLines: options.stressLines) : "")
        today.text = initialSource
        today.isDirty = true
        today = try store.saveDay(today)
        var review = try store.loadDay(now, in: reviewStream, createIfMissing: true)
        review.text = "# Vendor review\n\nSOC 2 report expires next month. Ask Elena whether the new report covers the EU entity; the questionnaire still lists the US address.\n\n- [ ] Confirm scope before the renewal call\n"
        review.isDirty = true
        try store.saveDay(review)
        let historyOffsets = options.historyDays > 21 ? Array(1..<options.historyDays) : [1, 3, 7, 14]
        for offset in historyOffsets {
            if options.emptyToday && offset == 1 { continue }
            let date = Calendar.current.date(byAdding: .day, value: -offset, to: now)!
            var day = try store.loadDay(date, in: stream, createIfMissing: true)
            day.text = "## Renewal follow-up\n\nFrom the call \(offset) days ago: finance can approve the extension, but legal still needs the revised liability cap. Maya will check the redline before Friday.\n"
            day.isDirty = true
            try store.saveDay(day)
        }
        let controller = TimelineController(store: store, now: now)
        controller.apply(configuration: configuration.configuration)
        controller.bootstrapIfNeeded(now: now)

        let defaultsName = "CurrentUIProbe.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: defaultsName) else { throw ProbeError("Cannot create isolated preferences") }
        defer { defaults.removePersistentDomain(forName: defaultsName) }
        let workspace = WorkspaceViewState(defaults: defaults)
        workspace.appearance = options.dark ? .dark : .light

        let origin = options.live ? CGPoint(x: 80, y: 80) : CGPoint(x: -10000, y: -10000)
        // A shipping NSApplication drains mount-time Objective-C temporaries
        // at the event boundary. This command-line entry point must do so too.
        let (window, host) = autoreleasepool { () -> (NSWindow, NSHostingView<AnyView>) in
            let window = NSWindow(
                contentRect: CGRect(origin: origin, size: CGSize(width: options.width, height: options.height)),
                styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false
            )
            window.title = "Current · isolated validation library"
            window.titleVisibility = .hidden
            window.toolbarStyle = .unified
            window.isReleasedWhenClosed = false
            let host = NSHostingView(rootView: AnyView(ContentView(controller: controller, configurationStore: configuration, workspace: workspace)))
            host.frame = CGRect(x: 0, y: 0, width: options.width, height: options.height)
            window.contentView = host
            window.makeKeyAndOrderFront(nil)
            settle(window)
            // Toolbar attachment can resize the window. Requested dimensions
            // describe the whole native window, including its titlebar.
            window.setFrame(NSRect(origin: origin, size: NSSize(width: options.width, height: options.height)), display: true)
            settle(window)
            return (window, host)
        }
        defer { window.close() }
        if options.exercise { activateAccessibility() }
        memoryStages.append(["stage": "mounted", "footprintBytes": processFootprint()])

        guard let editor = editors(in: host).first(where: { $0.string.contains("Payments sync") }) else {
            throw ProbeError("The mounted shell did not create the fixture's native text editor")
        }
        try require(editor.bounds.width > 100 && editor.bounds.height > 20, "Editor has invalid geometry")
        try require(editor.string == initialSource, "Mounting or rendering changed Markdown source")
        if !options.exercise {
            window.makeFirstResponder(nil)
            editor.setSelectedRange(NSRange(location: max(0, editor.string.utf16.count - 1), length: 0))
            settle(window)
        }
        // Measure the document's top inset at the actual scroll origin, after
        // the controller's initial focus/restore request has been consumed.
        if let scroll = descendants(in: host).compactMap({ $0 as? NSCollectionView }).first?.enclosingScrollView {
            scroll.contentView.scroll(to: .zero)
            scroll.reflectScrolledClipView(scroll.contentView)
            settle(window)
        }
        try snapshot(host, to: options.output.appendingPathComponent("initial.png"))
        memoryStages.append(["stage": "initialSnapshot", "footprintBytes": processFootprint()])
        var checks = ["native editor mounted", "rendering preserved source", "nonempty editor geometry"]
        let initialShellGeometry = try checkNativeShell(window: window, host: host, inspectAccessibility: options.exercise, checks: &checks)
        try checkRichBlocks(editor: editor, window: window, host: host, source: initialSource, output: options.output)
        memoryStages.append(["stage": "richBlocks", "footprintBytes": processFootprint()])
        checks.append("native table and local image have reserved geometry without source mutation")
        if options.calendarOnly {
            try exerciseCalendar(window: window, host: host, controller: controller, now: now, output: options.output, checks: &checks)
        }
        if options.exercise && !options.linksOnly && !options.calendarOnly {
            do {
                try exerciseRapidInput(editor: editor, window: window, host: host, controller: controller, original: today, output: options.output, checks: &checks)
                try exercise(editor: editor, window: window, host: host, controller: controller, original: today, checks: &checks)
            } catch {
                try? snapshot(host, to: options.output.appendingPathComponent("input-failure.png"))
                throw error
            }
            try snapshot(host, to: options.output.appendingPathComponent("after-edit.png"))
            let edited = editor.string
            let selection = editor.selectedRange()
            workspace.sourceMode = true
            settle(window)
            try require(editor.string == edited && editor.selectedRange() == selection, "Source mode changed text or selection")
            try snapshot(host, to: options.output.appendingPathComponent("source-mode.png"))
            workspace.sourceMode = false
            workspace.appearance = options.dark ? .light : .dark
            settle(window)
            try require(editor.string == edited, "Changing appearance changed Markdown source")
            try require(editors(in: host).contains(where: { $0 === editor }), "Mode or appearance change recreated the active editor")
            try requireConcealedRichSource(editor)
            try snapshot(host, to: options.output.appendingPathComponent("alternate-appearance.png"))
            checks.append("source mode and appearance preserved text, selection, and editor")
            try exerciseWorkspace(window: window, host: host, controller: controller, workspace: workspace,
                                  dailyStream: stream, reviewStream: reviewStream, today: today, now: now,
                                  output: options.output, checks: &checks)
            try exerciseStreamCreation(window: window, host: host, controller: controller, dailyStream: stream,
                                       output: options.output, checks: &checks)
            try exerciseNativeSidebar(window: window, host: host, controller: controller, dailyStream: stream, checks: &checks)
            if options.historyDays == 21 {
                try exerciseEmptyHistory(window: window, host: host, controller: controller, output: options.output, checks: &checks)
            }
            try exerciseStreamLinks(window: window, host: host, controller: controller, dailyStream: stream,
                                    reviewStream: reviewStream, output: options.output, checks: &checks)
        }
        if options.linksOnly {
            try exerciseStreamLinks(window: window, host: host, controller: controller, dailyStream: stream,
                                    reviewStream: reviewStream, output: options.output, checks: &checks)
        }
        var scrollSamples: [[String: Any]] = []
        var focusHeightSample: [String: Any] = [:]
        if options.stress {
            scrollSamples = try exerciseLongScroll(window: window, host: host, controller: controller, original: today,
                                                   minimumLines: options.stressLines, output: options.output, checks: &checks)
            focusHeightSample = try exerciseFocusHeightChange(window: window, host: host, controller: controller,
                                                              workspace: workspace, checks: &checks)
            memoryStages.append(["stage": "scrollAndHeight", "footprintBytes": processFootprint()])
        }
        var historySamples: [[String: Any]] = []
        if options.historyDays > 21 {
            historySamples = try exerciseHistoryPaging(window: window, host: host, controller: controller,
                                                      dayCount: options.historyDays, output: options.output, checks: &checks)
        }
        if options.exercise {
            try checkSidebarWidthPersistence(window: window, host: host, controller: controller,
                                             configuration: configuration, defaults: defaults, checks: &checks)
        }
        let report: [String: Any] = [
            "buildConfiguration": buildConfiguration,
            "mode": options.live ? "real-window" : "offscreen-window",
            "appearance": options.dark ? "dark" : "light",
            "library": library.path,
            "note": today.fileURL.path,
            "checks": checks,
            "stressScrollSamples": scrollSamples,
            "focusHeightSample": focusHeightSample,
            "historyPagingSamples": historySamples,
            "nativeInputTiming": nativeInputTiming,
            "memoryStages": memoryStages,
            "capturesDiagnosticImages": capturesImages,
            "validationElapsedSeconds": Date().timeIntervalSince(started),
            "processFootprintBytes": processFootprint(),
            "windowPoints": [host.bounds.width, host.bounds.height],
            "nativeWindow": nativeWindowGeometry(window),
            "initialShellGeometry": initialShellGeometry,
            "sceneLimitations": sceneLimitations,
            "editors": editors(in: host).map { geometry($0, in: host) },
            "limitations": "Synthetic fixture, native input smoke checks, accessibility actions, and controller-to-mounted-view transitions. Bitmap images are editor diagnostics, not compositor captures of macOS26 glass or titlebar. Use --hold plus an actual window screenshot for shell review. The probe does not install the app's keyboard menus; completion methods do not verify dropdown keyboard behavior. Not a frame-rate measurement, complete accessibility audit, or full IME test."
        ]
        try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
            .write(to: options.output.appendingPathComponent("geometry.json"), options: .atomic)
        print("CurrentUIProbe passed \(checks.count) checks; artifacts: \(options.output.path)")
        print("Isolated library: \(library.path)")
        if options.hold {
            let delegate = LiveProbeDelegate()
            app.delegate = delegate
            window.makeKeyAndOrderFront(nil)
            app.activate(ignoringOtherApps: true)
            withExtendedLifetime(delegate) { app.run() }
        }
    }

    @MainActor
    final class LiveProbeDelegate: NSObject, NSApplicationDelegate {
        func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    }

    @MainActor
    static func exerciseWindowRestoration(_ options: Options) throws {
        let fixture = FileManager.default.temporaryDirectory.appendingPathComponent("current-restore-probe-\(UUID())")
        let library = fixture.appendingPathComponent("library")
        let configURL = fixture.appendingPathComponent("config/current/config.current")
        try FileManager.default.createDirectory(at: configURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: options.output, withIntermediateDirectories: true)
        let configPrefix = "library-root = \(library.path)\nautosave-delay = 0.1\n"
        try configPrefix.write(to: configURL, atomically: true, encoding: .utf8)
        let locations = CurrentConfigurationLocations(environment: ["XDG_CONFIG_HOME": fixture.appendingPathComponent("config").path],
            homeDirectory: fixture, applicationSupportDirectory: fixture.appendingPathComponent("support"))
        let configuration = CurrentConfigurationStore(locations: locations, homeDirectory: fixture)
        let store = StreamStore(libraryRoot: library)
        let now = Date()
        var stream = try store.defaultStream()
        stream.createdAt = Calendar.current.date(byAdding: .day, value: -7, to: now)!
        try store.saveLibrary(streams: [stream], folders: [])
        let source = "# Reopening a long note\n\n" + (0..<360).map { index in
            "Paragraph \(index): Maya is reviewing the renewal terms with finance. Keep the liability discussion attached to this source paragraph as the window becomes narrower and the writing size changes.\n\n"
        }.joined()
        var note = try store.loadDay(now, in: stream, createIfMissing: true)
        note.text = source
        note.isDirty = true
        try store.saveDay(note)
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: now)!
        var older = try store.loadDay(yesterday, in: stream, createIfMissing: true)
        older.text = "Review the renewal notes before the next meeting.\n"
        older.isDirty = true
        try store.saveDay(older)
        let controller = TimelineController(store: store, now: now)
        controller.apply(configuration: configuration.configuration)
        controller.bootstrapIfNeeded(now: now)
        controller.toggleDayMinimized(yesterday)

        let defaultsName = "CurrentUIProbe.Restoration.\(UUID())"
        guard let defaults = UserDefaults(suiteName: defaultsName) else { throw ProbeError("Cannot create restoration preferences") }
        defer { defaults.removePersistentDomain(forName: defaultsName) }
        var checks: [String] = []
        var samples: [[String: Any]] = []
        var completed = false
        defer {
            let report: [String: Any] = ["completed": completed, "checks": checks, "samples": samples,
                "library": library.path, "buildConfiguration": buildConfiguration,
                "limitations": "Native windows and hosts are recreated, then a fresh controller reads the saved library session. This is one process; it does not simulate OS termination or clear the native editor session cache."]
            if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
                try? data.write(to: options.output.appendingPathComponent("restoration.json"), options: .atomic)
            }
        }

        func mount(_ current: TimelineController, configuration: CurrentConfigurationStore, width: CGFloat) -> (NSWindow, NSHostingView<AnyView>) {
            autoreleasepool {
                NSApplication.shared.activate(ignoringOtherApps: true)
                let workspace = WorkspaceViewState(defaults: defaults)
                workspace.appearance = options.dark ? .dark : .light
                let origin = options.live ? NSPoint(x: 80, y: 80) : NSPoint(x: -10000, y: -10000)
                let window = NSWindow(contentRect: NSRect(origin: origin, size: NSSize(width: width, height: options.height)),
                    styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
                window.title = "Current · isolated restoration validation"
                window.titleVisibility = .hidden
                window.toolbarStyle = .unified
                window.isReleasedWhenClosed = false
                let host = NSHostingView(rootView: AnyView(ContentView(controller: current, configurationStore: configuration, workspace: workspace)))
                host.frame = NSRect(x: 0, y: 0, width: width, height: options.height)
                window.contentView = host
                window.makeKeyAndOrderFront(nil)
                window.makeKey()
                settle(window)
                window.setFrame(NSRect(origin: origin, size: NSSize(width: width, height: options.height)), display: true)
                settle(window)
                return (window, host)
            }
        }
        func close(_ window: NSWindow, host: NSHostingView<AnyView>) {
            // Exercise willClose/dismantle capture, without manually flushing the controller.
            window.close()
            host.rootView = AnyView(EmptyView())
            window.contentView = nil
            settle(window)
        }
        func nativeParts(_ host: NSView) throws -> (NSTextView, NSCollectionView, NSScrollView) {
            guard let editor = editors(in: host).first(where: { $0.string == source }),
                  let collection = descendants(in: host).compactMap({ $0 as? NSCollectionView }).first,
                  let scroll = collection.enclosingScrollView else { throw ProbeError("Restoration fixture did not mount its editor and collection") }
            return (editor, collection, scroll)
        }
        func sourceLineY(_ location: Int, editor: NSTextView, collection: NSCollectionView) throws -> CGFloat {
            guard let layout = editor.layoutManager, let container = editor.textContainer,
                  location >= 0, location < editor.string.utf16.count else { throw ProbeError("Reading source location is invalid") }
            layout.ensureLayout(for: container)
            let glyph = layout.glyphIndexForCharacter(at: location)
            let line = layout.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
            return editor.convert(NSPoint(x: editor.textContainerOrigin.x, y: editor.textContainerOrigin.y + line.minY), to: collection).y
        }
        let (firstWindow, firstHost) = mount(controller, configuration: configuration, width: options.width)
        defer { firstWindow.close() }
        let (firstEditor, firstCollection, firstScroll) = try nativeParts(firstHost)
        let selection = (source as NSString).range(of: "Paragraph 10:")
        try require(selection.location != NSNotFound, "Caret fixture is missing")
        firstWindow.makeFirstResponder(firstEditor)
        firstEditor.setSelectedRange(selection)
        settle(firstWindow)
        firstWindow.makeFirstResponder(nil)
        let target = (source as NSString).range(of: "Paragraph 180:").location
        let targetY = try sourceLineY(target, editor: firstEditor, collection: firstCollection) + 7.5
        firstScroll.contentView.scroll(to: NSPoint(x: 0, y: targetY))
        firstScroll.reflectScrolledClipView(firstScroll.contentView)
        settle(firstWindow)
        let saved = controller.currentViewState
        guard let anchor = saved.readingAnchor else { throw ProbeError("Mid-note scroll did not publish a source reading anchor") }
        try require(anchor.sourceLocation > source.utf16.count / 3 && anchor.sourceLocation < source.utf16.count * 2 / 3,
                    "Reading anchor is not in the middle of the long fixture: \(anchor.sourceLocation)")
        try require(saved.selectionLocation == selection.location && saved.selectionLength == selection.length,
                    "Reading displaced the stored caret selection")
        try require(saved.editorHadFocus == false, "Reading fixture still has editing focus")
        try require(saved.minimizedDayKeys.contains(older.dayKey), "Collapsed historical date was not stored")
        checks.append("mid-note source anchor, offscreen caret selection, and collapsed date captured while reading")

        func verify(_ name: String, window: NSWindow, host: NSView, controller current: TimelineController) throws {
            let (editor, collection, scroll) = try nativeParts(host)
            let location = anchor.resolvedSourceLocation(in: editor.string)
            let actualOffset = scroll.contentView.bounds.minY - (try sourceLineY(location, editor: editor, collection: collection))
            let difference = abs(actualOffset - anchor.lineOffset)
            samples.append(["stage": name, "sourceLocation": location, "expectedLineOffset": anchor.lineOffset,
                "actualLineOffset": actualOffset, "offsetErrorPoints": difference, "viewportY": scroll.contentView.bounds.minY,
                "editorWidth": editor.bounds.width, "selection": [editor.selectedRange().location, editor.selectedRange().length],
                "editorHasFocus": window.firstResponder is NSTextView])
            try require(location == anchor.sourceLocation && editor.string == source, "\(name): source context changed")
            try require(difference < 2, "\(name): reading line moved \(difference)pt (expected offset \(anchor.lineOffset), actual \(actualOffset))")
            try require(editor.selectedRange() == selection, "\(name): caret selection was not restored")
            try require(!(window.firstResponder is NSTextView), "\(name): reopening stole editing focus while reading")
            try require(current.minimizedDayIDs.contains(current.dayID(for: yesterday)), "\(name): collapsed date expanded")
            try require(current.currentViewState.scrollDayKey == saved.scrollDayKey, "\(name): visible date changed")
            try require(collection.alphaValue > 0.99 && editor.visibleRect.height > 0, "\(name): restored content remains hidden")
            checks.append("\(name): source context within 2pt, selection, collapsed date, visible date, and reading focus preserved")
        }
        try verify("before close", window: firstWindow, host: firstHost, controller: controller)
        close(firstWindow, host: firstHost)
        let (sameWindow, sameHost) = mount(controller, configuration: configuration, width: options.width)
        defer { sameWindow.close() }
        try verify("same controller reopen", window: sameWindow, host: sameHost, controller: controller)
        close(sameWindow, host: sameHost)

        try (configPrefix + "font-size = 18\nline-height = 28\n").write(to: configURL, atomically: true, encoding: .utf8)
        let changedConfiguration = CurrentConfigurationStore(locations: locations, homeDirectory: fixture)
        let fresh = TimelineController(store: StreamStore(libraryRoot: library), now: now)
        fresh.apply(configuration: changedConfiguration.configuration)
        fresh.bootstrapIfNeeded(now: now)
        let persisted = fresh.currentViewState
        try require(persisted.readingAnchor?.sourceLocation == anchor.sourceLocation
                    && persisted.readingAnchor?.context == anchor.context
                    && abs((persisted.readingAnchor?.lineOffset ?? .infinity) - anchor.lineOffset) < 2
                    && persisted.selectionLocation == saved.selectionLocation
                    && persisted.selectionLength == saved.selectionLength && persisted.minimizedDayKeys == saved.minimizedDayKeys
                    && persisted.editorHadFocus == false, "Fresh controller did not read the persisted workspace state")
        checks.append("fresh controller loaded source anchor, selection, collapsed dates, and reading focus from disk")
        let changedWidth: CGFloat = options.width >= 1000 ? 820 : 1200
        let (freshWindow, freshHost) = mount(fresh, configuration: changedConfiguration, width: changedWidth)
        defer { freshWindow.close() }
        try verify("fresh controller with changed width and text size", window: freshWindow, host: freshHost, controller: fresh)

        // Reading restoration must stay unfocused, while reopening an actively
        // edited note must reacquire its native responder after layout settles.
        let (editingEditor, editingCollection, editingScroll) = try nativeParts(freshHost)
        let editingLocation = (source as NSString).range(of: "Paragraph 181:").location
        try require(editingLocation != NSNotFound, "Editing caret fixture is missing")
        let editingSelection = NSRange(location: editingLocation + 14, length: 0)
        try require(freshWindow.makeFirstResponder(editingEditor), "Could not focus the editing fixture")
        editingEditor.setSelectedRange(editingSelection)
        let editingY = try sourceLineY(editingSelection.location, editor: editingEditor, collection: editingCollection)
        editingScroll.contentView.scroll(to: NSPoint(x: 0, y: editingY - editingScroll.contentView.bounds.height * 0.4))
        editingScroll.reflectScrolledClipView(editingScroll.contentView)
        settle(freshWindow)
        let editingState = fresh.currentViewState
        guard let editingAnchor = editingState.readingAnchor else { throw ProbeError("Editing fixture did not capture a source anchor") }
        try require(editingState.editorHadFocus == true && editingState.selectionLocation == editingSelection.location
                    && editingState.selectionLength == 0, "Editing focus or caret was not captured before close")

        func verifyEditing(_ name: String, window: NSWindow, host: NSView, controller current: TimelineController) throws {
            try require(window.isKeyWindow, "\(name): editing-restoration fixture is not the key window (application active=\(NSApplication.shared.isActive))")
            let (editor, collection, scroll) = try nativeParts(host)
            let location = editingAnchor.resolvedSourceLocation(in: editor.string)
            let actualOffset = scroll.contentView.bounds.minY - (try sourceLineY(location, editor: editor, collection: collection))
            let difference = abs(actualOffset - editingAnchor.lineOffset)
            let caretY = try sourceLineY(editingSelection.location, editor: editor, collection: collection)
            guard let layout = editor.layoutManager else { throw ProbeError("Editing restoration lost its layout manager") }
            let caretGlyph = layout.glyphIndexForCharacter(at: editingSelection.location)
            let caretLineHeight = layout.lineFragmentRect(forGlyphAt: caretGlyph, effectiveRange: nil).height
            let viewport = scroll.contentView.bounds
            let caretVisible = caretY >= viewport.minY && caretY + caretLineHeight <= viewport.maxY
            samples.append(["stage": name, "sourceLocation": location, "expectedLineOffset": editingAnchor.lineOffset,
                "actualLineOffset": actualOffset, "offsetErrorPoints": difference, "viewportY": viewport.minY,
                "selection": [editor.selectedRange().location, editor.selectedRange().length],
                "editorHasFocus": window.firstResponder === editor, "caretVisible": caretVisible])
            try require(editor.string == source && location == editingAnchor.sourceLocation, "\(name): editing source context changed")
            try require(difference < 2, "\(name): editing reading line moved \(difference)pt")
            try require(editor.selectedRange() == editingSelection, "\(name): editing caret selection was not restored")
            try require(window.firstResponder === editor, "\(name): saved editing focus was not restored to the note")
            try require(caretVisible, "\(name): editing caret line is outside the viewport")
            try require(current.minimizedDayIDs.contains(current.dayID(for: yesterday)), "\(name): collapsed date expanded")
            try require(current.currentViewState.scrollDayKey == editingState.scrollDayKey, "\(name): visible editing date changed")
            try require(collection.alphaValue > 0.99 && editor.visibleRect.height > 0, "\(name): editing content remains hidden")
            checks.append("\(name): editing first responder, visible caret, selection, and source context within 2pt restored")
        }
        try verifyEditing("editing before close", window: freshWindow, host: freshHost, controller: fresh)
        close(freshWindow, host: freshHost)
        let (editingWindow, editingHost) = mount(fresh, configuration: changedConfiguration, width: changedWidth)
        defer { editingWindow.close() }
        try verifyEditing("editing same controller reopen", window: editingWindow, host: editingHost, controller: fresh)
        close(editingWindow, host: editingHost)

        let editingFresh = TimelineController(store: StreamStore(libraryRoot: library), now: now)
        editingFresh.apply(configuration: changedConfiguration.configuration)
        editingFresh.bootstrapIfNeeded(now: now)
        let persistedEditing = editingFresh.currentViewState
        try require(persistedEditing.editorHadFocus == true
                    && persistedEditing.selectionLocation == editingSelection.location && persistedEditing.selectionLength == 0
                    && persistedEditing.readingAnchor?.sourceLocation == editingAnchor.sourceLocation
                    && abs((persistedEditing.readingAnchor?.lineOffset ?? .infinity) - editingAnchor.lineOffset) < 2,
                    "Fresh controller did not load editing focus, caret, and source anchor from disk")
        let (editingFreshWindow, editingFreshHost) = mount(editingFresh, configuration: changedConfiguration, width: changedWidth)
        defer { editingFreshWindow.close() }
        try verifyEditing("editing fresh controller reopen", window: editingFreshWindow, host: editingFreshHost, controller: editingFresh)
        completed = true
        print("CurrentUIProbe restoration passed \(checks.count) checks; artifacts: \(options.output.path)")
    }

    @MainActor
    static func checkRichBlocks(editor: NSTextView, window: NSWindow, host: NSView, source: String, output: URL) throws {
        guard let storage = editor.textStorage else { throw ProbeError("Editor has no text storage") }
        for marker in ["| Owner |", "![Queue sketch]"] {
            let range = (editor.string as NSString).range(of: marker)
            try require(range.location != NSNotFound, "Missing rich block fixture")
            let widget = storage.attribute(NSAttributedString.Key("current.richBlock"), at: range.location, effectiveRange: nil)
            let height = storage.attribute(NSAttributedString.Key("current.richBlockHeight"), at: range.location, effectiveRange: nil) as? CGFloat
            try require(widget != nil && (height ?? 0) > 40, "Rich block did not reserve visible geometry: \(marker)")
            guard let layout = editor.layoutManager, let container = editor.textContainer else { throw ProbeError("Missing rich block layout") }
            layout.ensureLayout(for: container)
            let fragment = layout.lineFragmentRect(forGlyphAt: layout.glyphIndexForCharacter(at: range.location), effectiveRange: nil)
            try require(fragment.height >= (height ?? 0) - 1, "Rich block has attributes but no drawable line fragment: \(marker)")
        }
        let image = (editor.string as NSString).range(of: "![Queue sketch]")
        editor.scrollRangeToVisible(image)
        settle(window)
        try snapshot(host, to: output.appendingPathComponent("rich-blocks.png"))
        let originalSelection = editor.selectedRange()
        for marker in ["Maya |", "![Queue sketch]"] {
            let range = (editor.string as NSString).range(of: marker)
            editor.setSelectedRange(NSRange(location: range.location + 1, length: 0))
            settle(window)
            try require(storage.attribute(NSAttributedString.Key("current.richBlockHeight"), at: range.location, effectiveRange: nil) == nil,
                        "Placing a caret inside a rich block did not reveal editable source")
            try require(editor.string == source, "Revealing a rich block changed source")
        }
        editor.setSelectedRange(originalSelection)
        settle(window)
        editor.scrollRangeToVisible(NSRange(location: 0, length: 0))
        settle(window)
        try require(editor.string == source, "Drawing rich blocks mutated source")
    }

    @MainActor
    static func exerciseLongScroll(window: NSWindow, host: NSView, controller: TimelineController,
                                   original: DayDocument, minimumLines: Int, output: URL, checks: inout [String]) throws -> [[String: Any]] {
        guard let collection = descendants(in: host).compactMap({ $0 as? NSCollectionView }).first,
              let scroll = collection.enclosingScrollView,
              let firstEditor = editors(in: host).first(where: { $0.string.contains("Payments sync") }) else {
            throw ProbeError("Stress fixture has no mounted timeline/editor")
        }
        let exactSource = firstEditor.string
        let lineCount = exactSource.components(separatedBy: "\n").count
        try require(lineCount >= minimumLines, "Stress fixture is shorter than requested")
        var samples: [[String: Any]] = []
        for (index, fraction) in [0.0, 0.25, 0.5, 0.75, 1.0, 0.75, 0.5, 0.25, 0.0].enumerated() {
            let maximum = max(0, collection.bounds.height - scroll.contentView.bounds.height)
            scroll.contentView.scroll(to: NSPoint(x: 0, y: maximum * fraction))
            scroll.reflectScrolledClipView(scroll.contentView)
            settle(window)
            let mounted = editors(in: host)
            let sources = Set(controller.days.map(\.text))
            // AppKit keeps recycled item subtrees attached with an empty visibleRect;
            // only displayed editors must belong to the controller's current window.
            let unmatched = mounted.filter { $0.visibleRect.width > 0 && $0.visibleRect.height > 0 && !sources.contains($0.string) }
            if !unmatched.isEmpty {
                try? snapshot(host, to: output.appendingPathComponent("stress-source-failure.png"))
                let details = unmatched.map { "\(String(describing: type(of: $0))) \(($0.string as NSString).length) chars, visible=\($0.visibleRect), prefix=\($0.string.prefix(120))" }.joined(separator: "; ")
                throw ProbeError("Long scroll step\(index) mounted unmatched source: \(details); allowed lengths \(sources.map { $0.utf16.count })")
            }
            if let current = mounted.first(where: { $0.string == exactSource }) {
                try require(current === firstEditor, "Long scroll replaced the current document's editor session")
            }
            var visibleLayouts = 0
            for view in mounted where !view.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                try requireConcealedRichSource(view)
                let visible = view.visibleRect
                guard visible.height > 200, visible.width > 100,
                      let manager = view.layoutManager, let container = view.textContainer else { continue }
                manager.ensureLayout(for: container)
                let textRect = visible.offsetBy(dx: -view.textContainerOrigin.x, dy: -view.textContainerOrigin.y)
                let glyphs = manager.glyphRange(forBoundingRect: textRect, in: container)
                try require(glyphs.length > 0 && NSMaxRange(glyphs) <= manager.numberOfGlyphs, "Large visible editor region contains no laid-out glyphs")
                visibleLayouts += 1
            }
            try require(!collection.visibleItems().isEmpty, "Large scroll distance produced an empty timeline viewport")
            samples.append(["fraction": fraction, "offset": scroll.contentView.bounds.minY,
                            "contentHeight": collection.bounds.height, "mountedEditors": mounted.count,
                            "visibleTextLayouts": visibleLayouts, "footprintBytes": processFootprint()])
            if [0, 2, 4, 8].contains(index) {
                try snapshot(host, to: output.appendingPathComponent("stress-scroll-\(index).png"))
            }
        }
        controller.jumpToToday()
        settle(window)
        try require(editors(in: host).contains(where: { $0 === firstEditor && $0.string == exactSource }), "Returning from distant history lost the active source/session")
        try require(controller.flushAllSaves(), "Stress fixture has pending failed saves")
        try require(try String(contentsOf: original.fileURL, encoding: .utf8) == exactSource, "Long scroll changed source on disk")
        checks.append("\(lineCount)-line mixed note retained source and editor session across large bidirectional scroll distances")
        return samples
    }

    static func stressWatchdog() -> DispatchSourceTimer {
        let started = Date()
        let timer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        timer.schedule(deadline: .now() + 1, repeating: 1)
        timer.setEventHandler {
            let footprint = processFootprint()
            if footprint > 2 * 1024 * 1024 * 1024 || Date().timeIntervalSince(started) > 120 {
                FileHandle.standardError.write(Data("CurrentUIProbe stress limit exceeded: footprint=\(footprint) bytes, elapsed=\(Date().timeIntervalSince(started))s\n".utf8))
                exit(2)
            }
        }
        timer.resume()
        return timer
    }

    @MainActor
    static func exerciseHistoryPaging(window: NSWindow, host: NSView, controller: TimelineController,
                                      dayCount: Int, output: URL, checks: inout [String]) throws -> [[String: Any]] {
        controller.jumpToToday()
        settle(window)
        window.makeFirstResponder(nil)
        guard let collection = descendants(in: host).compactMap({ $0 as? NSCollectionView }).first,
              let scroll = collection.enclosingScrollView else { throw ProbeError("Missing native history timeline") }
        var samples: [[String: Any]] = []
        var reachedTopSpacer = false
        var reachedBottomSpacer = false
        for (phase, older) in [true, false, true].enumerated() {
            var transitions = 0
            for _ in 0..<40 {
                if older ? !controller.canLoadOlderDays : controller.topSpacerHeight <= 0 { break }
                let beforeIDs = controller.days.map(\.id)
                let first = controller.topSpacerHeight > 0 ? 1 : 0
                let index = older ? collection.numberOfItems(inSection: 0) - 1 - (controller.bottomSpacerHeight > 0 ? 1 : 0) : first
                guard index >= 0, let edge = collection.layoutAttributesForItem(at: IndexPath(item: index, section: 0)) else {
                    throw ProbeError("History paging has no retained boundary row")
                }
                let target = older ? edge.frame.maxY - scroll.contentView.bounds.height + 2 : edge.frame.minY - 2
                scroll.contentView.scroll(to: NSPoint(x: 0, y: max(0, target)))
                scroll.reflectScrolledClipView(scroll.contentView)
                settle(window)
                if controller.days.map(\.id) == beforeIDs { settle(window) }
                if controller.days.map(\.id) == beforeIDs && !(older && !controller.canLoadOlderDays) {
                    try? snapshot(host, to: output.appendingPathComponent("history-paging-failure.png"))
                }
                try require(controller.days.map(\.id) != beforeIDs || (older && !controller.canLoadOlderDays),
                            "Native history paging stalled in phase \(phase), top spacer \(controller.topSpacerHeight), bottom spacer \(controller.bottomSpacerHeight), days=\(controller.days.count) \(controller.days.first?.dayKey ?? "nil")..\(controller.days.last?.dayKey ?? "nil"), target=\(target), actual=\(scroll.contentView.bounds), row=\(edge.frame), content=\(collection.bounds), responder=\(String(describing: window.firstResponder))")
                transitions += 1
                reachedTopSpacer = reachedTopSpacer || controller.topSpacerHeight > 0
                reachedBottomSpacer = reachedBottomSpacer || controller.bottomSpacerHeight > 0
                let known = Set(controller.days.map(\.text))
                let visible = editors(in: host).filter { $0.visibleRect.width > 0 && $0.visibleRect.height > 0 }
                try require(visible.allSatisfy { known.contains($0.string) }, "Native history paging displayed source outside retained window")
                let hasRealRow = collection.visibleItems().contains {
                    String(describing: type(of: $0)).contains("TimelineDayCollectionItem") && $0.view.visibleRect.height > 0
                }
                try require(hasRealRow, "Native history paging left the viewport in a blank spacer")
                samples.append(["phase": phase, "direction": older ? "older" : "newer", "days": controller.days.count,
                                "firstDay": controller.days.first?.dayKey ?? "", "lastDay": controller.days.last?.dayKey ?? "",
                                "topSpacer": controller.topSpacerHeight, "bottomSpacer": controller.bottomSpacerHeight,
                                "offset": scroll.contentView.bounds.minY])
            }
            try require(transitions > 0, "Native history paging did not exercise phase \(phase)")
            try require(older ? !controller.canLoadOlderDays : controller.topSpacerHeight <= 0,
                        "Native history paging did not reach the expected boundary in phase \(phase)")
            try snapshot(host, to: output.appendingPathComponent("history-phase-\(phase).png"))
        }
        try require(reachedTopSpacer && reachedBottomSpacer, "History fixture did not cross both retained-window boundaries")
        controller.jumpToToday()
        settle(window)
        try require(editors(in: host).contains(where: { $0.string.contains("Payments sync") && $0.visibleRect.height > 0 }),
                    "Returning from deep history did not display today's source")
        checks.append("\(dayCount)-day native history scrolled older, newer, and older through both spacer boundaries without a blank viewport")
        return samples
    }

    static func processFootprint() -> UInt64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? info.phys_footprint : 0
    }

    @MainActor
    static func exerciseWorkspace(window: NSWindow, host: NSView, controller: TimelineController,
                                  workspace: WorkspaceViewState, dailyStream: CurrentFeature.Stream, reviewStream: CurrentFeature.Stream,
                                  today: DayDocument, now: Date, output: URL, checks: inout [String]) throws {
        guard let originalEditor = editors(in: host).first(where: { $0.string.contains("Payments sync") && $0.window === window && $0.visibleRect.height > 0 }) else {
            throw ProbeError("Daily editor missing before workspace transitions")
        }
        let text = originalEditor.string
        let documentUndo = originalEditor.undoManager
        let selection = (text as NSString).range(of: "retry behavior")
        originalEditor.setSelectedRange(selection)
        originalEditor.scrollRangeToVisible(selection)
        window.makeFirstResponder(originalEditor)
        settle(window)
        workspace.showsTabs = true
        settle(window)
        let tabsBeforeNavigation = controller.openStreamIDs
        // Opening a palette resigns the editor before selection changes the stream.
        window.makeFirstResponder(nil)
        settle(window)
        controller.selectStream(reviewStream.id)
        settle(window)
        try require(controller.stream?.id == reviewStream.id, "Stream switch did not change active stream")
        try require(editors(in: host).contains(where: { $0.string.contains("Vendor review") }), "Stream switch did not mount its document")
        controller.selectStream(dailyStream.id)
        settle(window)
        try require(controller.openStreamIDs == tabsBeforeNavigation, "Ordinary stream navigation opened persistent tabs")
        guard let restored = editors(in: host).first(where: { $0.string == text && $0.window === window && $0.visibleRect.height > 0 }) else { throw ProbeError("Returning to a stream lost editor source") }
        try require(restored.selectedRange() == selection, "Returning to a stream did not restore its selection")
        checks.append("stream switching restored source and selection in mounted editor")

        for _ in 0..<6 {
            window.makeFirstResponder(nil)
            settle(window)
            controller.selectStream(reviewStream.id)
            settle(window)
            controller.selectStream(dailyStream.id)
            settle(window)
            try require(editors(in: host).contains(where: { $0.string == text }), "Repeated stream switching lost current source")
        }
        checks.append("repeated stream switches after editor resignation retained rendered source")
        guard let current = editors(in: host).first(where: { $0.string == text && $0.window === window && $0.visibleRect.height > 0 }),
              let documentUndo else { throw ProbeError("Returning to the stream lost its undo session") }
        try require(current.undoManager === documentUndo && documentUndo.canUndo, "Repeated stream switches replaced the document's undo history")
        documentUndo.undo()
        settle(window)
        try require(current.string != text && documentUndo.canRedo, "Undo after stream switching did not restore a prior document revision")
        try require(controller.activeDocument?.text == current.string, "Undo did not update the canonical document; delegate=\(String(describing: current.delegate)), firstResponderMatches=\(window.firstResponder === current)")
        try require(controller.flushAllSaves(), "Undo after stream switching did not save")
        try require(try String(contentsOf: today.fileURL, encoding: .utf8) == current.string, "Undo after stream switching did not save exact source")
        documentUndo.redo()
        settle(window)
        try require(current.string == text, "Redo after stream switching did not restore exact source")
        try require(controller.activeDocument?.text == current.string, "Redo did not update the canonical document; delegate=\(String(describing: current.delegate)), firstResponderMatches=\(window.firstResponder === current)")
        try require(controller.flushAllSaves(), "Redo after stream switching did not save")
        try require(try String(contentsOf: today.fileURL, encoding: .utf8) == current.string, "Redo after stream switching did not save exact source")
        checks.append("undo and redo survived repeated stream switching")

        controller.openStreamTab(reviewStream.id)
        settle(window)
        controller.openStreamTab(dailyStream.id)
        workspace.showsTabs = true
        settle(window)
        try require(controller.openStreamIDs.contains(dailyStream.id) && controller.openStreamIDs.contains(reviewStream.id), "Explicitly opened streams missing from tabs")
        try snapshot(host, to: output.appendingPathComponent("stream-tabs.png"))
        guard let focusEditor = editors(in: host).first(where: { $0.string == text && $0.window === window && $0.visibleRect.height > 0 }) else {
            throw ProbeError("No current editor before focus mode")
        }
        workspace.focusMode = true
        settle(window)
        try require(!descendants(in: host).compactMap { $0 as? NSTableView }.contains {
            !$0.isHiddenOrHasHiddenAncestor && $0.visibleRect.width > 10 && $0.visibleRect.height > 10
        }, "Focus mode retained the native sidebar list")
        try require(editors(in: host).contains(where: { $0 === focusEditor }), "Focus mode recreated the active editor")
        try require(focusEditor.string == text, "Focus mode changed editor source: expected \(text.utf16.count) chars, got \(focusEditor.string.utf16.count), prefix=\(focusEditor.string.prefix(100)); active stream=\(controller.stream?.name ?? "none"), modelMatches=\(controller.days.contains { $0.text == text })")
        let focusedNodes = accessibilityNodes(in: host)
        try snapshot(host, to: output.appendingPathComponent("focus-mode.png"))
        try require(focusedNodes.contains { $0.accessibilityIdentifier() == "workspace.leaveFocus" }, "Focus mode has no accessible exit control; nodes=\(focusedNodes.map { "\(type(of: $0))/\($0.accessibilityIdentifier() ?? "nil")/\($0.accessibilityLabel() ?? "nil")" })")
        let toolbarActions: Set<String> = ["workspace.streamSwitcher", "workspace.today", "workspace.calendar", "workspace.search", "workspace.newStream", "workspace.options"]
        if focusedNodes.contains(where: { $0.accessibilityIdentifier().map(toolbarActions.contains) == true }) {
            sceneLimitations.append("Bare NSHostingView does not apply window-scene toolbar visibility; actual WindowGroup focus chrome must be verified in the running app.")
        }
        workspace.focusMode = false
        settle(window)
        for label in ["Close TPRM tab", "Close Daily tab"] {
            guard let close = accessibilityNodes(in: host).first(where: { $0.accessibilityLabel() == label }) else {
                throw ProbeError("Explicit stream tab has no accessible close control")
            }
            try require(close.accessibilityPerformPress(), "Stream tab rejected native close press")
            settle(window)
        }
        try require(controller.openStreamIDs.isEmpty && !workspace.showsTabs, "Closing the last explicit tab left an unclosable tab strip")
        try require(controller.stream?.id == dailyStream.id && editors(in: host).contains { $0.string == text }, "Closing the last tab lost selected document content")
        checks.append("ordinary navigation left tabs unchanged; explicit tabs and focus mode retained active document")

        let historyDate = Calendar.current.date(byAdding: .day, value: -7, to: now)!
        controller.jumpToDate(historyDate)
        settle(window)
        try require(editors(in: host).contains(where: { $0.string.contains("7 days ago") }), "Date jump did not mount the requested day's note")
        checks.append("direct date jump mounted historical note")

        controller.toggleDayMinimized(historyDate)
        settle(window)
        let collapsed = accessibilityNodes(in: host).first {
            $0.accessibilityIdentifier() == "timeline.collapsedExcerpt"
                || (($0.accessibilityValue() as? String) == "Collapsed" && $0.accessibilityLabel()?.contains("Renewal follow-up") == true)
        }
        try require(collapsed != nil, "Collapsed populated day has no accessible excerpt")
        try require(collapsed?.accessibilityLabel()?.contains("##") != true, "Collapsed excerpt leaked heading Markdown")
        try snapshot(host, to: output.appendingPathComponent("collapsed-day.png"))
        controller.toggleDayMinimized(historyDate)
        settle(window)
        checks.append("collapsed populated day retained a visible excerpt")

        try exerciseCalendar(window: window, host: host, controller: controller, now: now, output: output, checks: &checks)

        controller.searchHistory("14 days ago")
        for _ in 0..<20 where controller.isSearching { settle(window) }
        guard !controller.isSearching, let result = controller.searchResults.first else { throw ProbeError("History search did not finish with the fixture match") }
        controller.openSearchResult(result)
        settle(window)
        guard let found = editors(in: host).first(where: { $0.string.contains("14 days ago") }) else { throw ProbeError("Search did not mount matched historical note") }
        let match = found.selectedRange()
        try require(NSMaxRange(match) <= (found.string as NSString).length && (found.string as NSString).substring(with: match) == "14 days ago",
                    "Search result did not select the matching source range")
        try snapshot(host, to: output.appendingPathComponent("history-search-result.png"))
        checks.append("full-history search mounted and selected matching text")
        controller.jumpToToday()
        settle(window)
        try require(editors(in: host).contains(where: { $0.string == text }), "Returning to today lost current document")
        try require(try String(contentsOf: today.fileURL, encoding: .utf8) == text, "Workspace transitions changed saved source")
    }

    @MainActor
    static func exerciseStreamLinks(window: NSWindow, host: NSView, controller: TimelineController,
                                    dailyStream: CurrentFeature.Stream, reviewStream: CurrentFeature.Stream,
                                    output: URL, checks: inout [String]) throws {
        let tabs = controller.openStreamIDs
        controller.selectStream(reviewStream.id)
        settle(window)
        guard let editor = editors(in: host).first(where: { $0.string.contains("Vendor review") && $0.visibleRect.height > 0 }) else {
            throw ProbeError("Stream-link fixture has no visible native editor")
        }
        let before = editor.string
        let partial = before + "\n\n[[Da"
        window.makeFirstResponder(editor)
        editor.setSelectedRange(NSRange(location: before.utf16.count, length: 0))
        revealSelection(editor, in: host)
        settle(window)
        editor.breakUndoCoalescing()
        editor.insertText("\n\n[[Da", replacementRange: editor.selectedRange())
        settle(window)
        try require(editor.string == partial, "Stream completion preview changed source before confirmation")
        // A command-line AppKit process has no reliable key-window activation.
        // Exercise the mounted native completion methods here; the dropdown's
        // actual keyboard interaction is a separate real-app check.
        var selectedCandidate = -1
        let completionRange = editor.rangeForUserCompletion
        let candidates = editor.completions(forPartialWordRange: completionRange, indexOfSelectedItem: &selectedCandidate)
        try require(candidates?.contains("[[Daily]]") == true, "Mounted editor did not offer the existing stream")
        editor.insertCompletion("[[Daily]]", forPartialWordRange: completionRange, movement: NSTextMovement.down.rawValue, isFinal: false)
        try require(editor.string == partial, "Native completion preview altered source")
        editor.insertCompletion("[[Daily]]", forPartialWordRange: completionRange, movement: NSTextMovement.return.rawValue, isFinal: true)
        settle(window)
        let completed = before + "\n\n[[Daily]]"
        try require(editor.string == completed, "Native stream completion did not insert exactly one resolved link: suffix=\(editor.string.suffix(100))")
        let linkRange = (editor.string as NSString).range(of: "[[Daily]]", options: .backwards)
        guard let link = editor.textStorage?.attribute(.link, at: linkRange.location + 2, effectiveRange: nil) else {
            throw ProbeError("Completed stream link has no native click target")
        }
        try require(editor.delegate?.textView?(editor, clickedOnLink: link, at: linkRange.location + 2) == true,
                    "Mounted stream link delegate rejected its resolved target")
        settle(window)
        try require(controller.stream?.id == dailyStream.id && controller.openStreamIDs == tabs, "Stream link opened the wrong target or added an unrequested tab")
        try require(editors(in: host).contains { $0.string.contains("Payments sync") && $0.visibleRect.height > 0 },
                    "Stream link changed selection without displaying its target editor")
        controller.selectStream(reviewStream.id)
        settle(window)
        guard let restored = editors(in: host).first(where: { $0.string == completed && $0.visibleRect.height > 0 }),
              let undo = restored.undoManager else { throw ProbeError("Stream link navigation lost its source session") }
        undo.undo()
        settle(window)
        try require(restored.string == partial, "Stream completion was not one native undo action")
        undo.undo()
        settle(window)
        try require(restored.string == before, "Stream-link prefix undo did not restore original source")
        window.makeFirstResponder(restored)
        restored.setSelectedRange(NSRange(location: before.utf16.count, length: 0))
        restored.breakUndoCoalescing()
        restored.insertText("\n\n[[Da", replacementRange: restored.selectedRange())
        settle(window)
        let cancelledRange = restored.rangeForUserCompletion
        _ = restored.completions(forPartialWordRange: cancelledRange, indexOfSelectedItem: &selectedCandidate)
        restored.insertCompletion("[[Daily]]", forPartialWordRange: cancelledRange, movement: NSTextMovement.cancel.rawValue, isFinal: true)
        settle(window)
        try require(restored.string == partial, "Cancelling stream completion changed source")
        undo.undo()
        settle(window)
        try require(restored.string == before && controller.activeDocument?.text == before, "Cancelled link input did not undo to the canonical source")
        controller.selectStream(dailyStream.id)
        settle(window)
        checks.append("mounted native completion methods preserved source and undo; resolved link delegate opened the existing stream without adding a tab")
    }

    @MainActor
    static func exerciseStreamCreation(window: NSWindow, host: NSView, controller: TimelineController,
                                       dailyStream: CurrentFeature.Stream, output: URL, checks: inout [String]) throws {
        guard let trigger = accessibilityNodes(in: host).first(where: { $0.accessibilityIdentifier() == "workspace.streamSwitcher" }) else {
            throw ProbeError("Stream switcher is not accessible")
        }
        if trigger.object is NSPopUpButtonCell {
            sceneLimitations.append("Skipped stream-creation interaction: native toolbar menus require out-of-process UI interaction; in-process AXPress can enter menu tracking. Verify menu opening and Switch Stream… in the separately launched app.")
            return
        }
        let tabs = controller.openStreamIDs
        let expectedFolder = controller.stream?.folderID
        _ = trigger.accessibilityPerformPress()
        settle(window)
        guard let sheet = window.attachedSheet, let content = sheet.contentView,
              let field = sheet.firstResponder as? NSTextView, field.isFieldEditor else {
            throw ProbeError("Stream switcher did not focus its native query field")
        }
        field.selectAll(nil)
        field.insertText("  TPRM  ", replacementRange: field.selectedRange())
        settle(window)
        let existingLabels = accessibilityNodes(in: content).compactMap { $0.accessibilityLabel() }.joined(separator: " ")
        try require(existingLabels.contains("TPRM") && existingLabels.contains("Work"), "Stream switcher dropped existing folder context")
        try require(!existingLabels.contains("Create “TPRM”"), "Whitespace around an existing stream offered duplicate creation")
        try snapshot(content, to: output.appendingPathComponent("stream-switcher-existing.png"))
        field.selectAll(nil)
        field.insertText("  Weekend planning  ", replacementRange: field.selectedRange())
        settle(window)
        try require(accessibilityNodes(in: content).contains { $0.accessibilityLabel()?.contains("Create “Weekend planning”") == true },
                    "Unmatched stream query retained a stale result instead of Create")
        try snapshot(content, to: output.appendingPathComponent("stream-switcher-create.png"))
        field.insertNewline(nil)
        settle(window)
        try require(controller.stream?.name == "Weekend planning" && controller.streams.contains { $0.name == "Weekend planning" },
                    "Return on unmatched stream query did not create and select that stream")
        try require(controller.stream?.folderID == expectedFolder, "Stream creation lost the current folder destination")
        try require(controller.openStreamIDs == tabs, "Ordinary stream creation opened an unrequested tab")
        controller.selectStream(dailyStream.id)
        settle(window)
        checks.append("breadcrumb menu action opened the stream switcher, which preserved folder context and created an unmatched query through Return")
    }

    @MainActor
    static func exerciseNativeSidebar(window: NSWindow, host: NSView, controller: TimelineController,
                                      dailyStream: CurrentFeature.Stream, checks: inout [String]) throws {
        controller.selectStream(dailyStream.id)
        controller.jumpToToday()
        settle(window)
        guard let editor = editors(in: host).first(where: { $0.string.contains("Payments sync") && $0.visibleRect.height > 0 }),
              let fileURL = controller.activeDocument?.fileURL,
              let list = descendants(in: host).compactMap({ $0 as? NSTableView }).first(where: { $0.visibleRect.width > 10 }) else {
            throw ProbeError("Native sidebar fixture has no editor and list")
        }
        let before = editor.string
        let tabs = controller.openStreamIDs
        window.makeFirstResponder(editor)
        editor.breakUndoCoalescing()
        editor.setSelectedRange(NSRange(location: before.utf16.count, length: 0))
        editor.insertText("\nSidebar navigation check", replacementRange: editor.selectedRange())
        editor.breakUndoCoalescing()
        let edited = editor.string
        try require(window.makeFirstResponder(list), "Native sidebar cannot receive keyboard focus")
        var selectedStreams = Set<UUID>()
        for _ in 0..<min(list.numberOfRows + 2, 12) {
            guard let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                              windowNumber: window.windowNumber, context: nil, characters: "\u{F701}",
                                              charactersIgnoringModifiers: "\u{F701}", isARepeat: false, keyCode: 125) else {
                throw ProbeError("Cannot construct sidebar arrow input")
            }
            list.keyDown(with: event)
            settle(window)
            let focusedView = window.firstResponder as? NSView
            try require(window.firstResponder === list || focusedView?.isDescendant(of: list) == true,
                        "Selecting a stream stole keyboard focus from the sidebar after a Down arrow")
            if let id = controller.stream?.id, id != dailyStream.id { selectedStreams.insert(id) }
            if selectedStreams.count >= 3 { break }
        }
        try require(selectedStreams.count >= 3, "Repeated sidebar Down arrows did not select three different streams")
        try require(controller.openStreamIDs == tabs, "Sidebar selection created unrequested persistent tabs")
        try require(try String(contentsOf: fileURL, encoding: .utf8) == edited, "Sidebar stream change did not save the previous document")
        controller.selectStream(dailyStream.id)
        settle(window)
        guard let restored = editors(in: host).first(where: { $0.string == edited && $0.visibleRect.height > 0 }),
              let undo = restored.undoManager else { throw ProbeError("Sidebar traversal lost the edited document session") }
        undo.undo()
        settle(window)
        try require(restored.string == before && controller.activeDocument?.text == before, "Sidebar traversal lost native undo or canonical source")
        try require(controller.flushAllSaves(), "Sidebar fixture cleanup did not save")
        checks.append("repeated native sidebar arrow selection retained list focus, saved the previous note, and preserved undo without adding tabs")
    }

    @MainActor
    static func exerciseFocusHeightChange(window: NSWindow, host: NSView, controller: TimelineController,
                                         workspace: WorkspaceViewState, checks: inout [String]) throws -> [String: Any] {
        let sidebarWasVisible = workspace.sidebarVisible
        let tabsWereVisible = workspace.showsTabs
        workspace.sidebarVisible = false
        workspace.showsTabs = false
        settle(window)
        guard let collection = descendants(in: host).compactMap({ $0 as? NSCollectionView }).first,
              let clip = collection.enclosingScrollView?.contentView,
              let editor = editors(in: host).first(where: { $0.string.contains("Payments sync") && $0.visibleRect.height > 0 }),
              let undo = editor.undoManager else { throw ProbeError("Height-only focus fixture has no active long note") }
        let source = editor.string
        window.makeFirstResponder(editor)
        editor.setSelectedRange(NSRange(location: source.utf16.count, length: 0))
        revealSelection(editor, in: host)
        settle(window)
        func requireCaret(_ stage: String) throws {
            let rect = editor.convert(window.convertFromScreen(editor.firstRect(forCharacterRange: editor.selectedRange(), actualRange: nil)), from: nil)
            try require(window.firstResponder === editor && editor.window === window,
                        "Height-only focus \(stage) lost the active editor")
            try require(rect.height > 0 && editor.visibleRect.insetBy(dx: -2, dy: -2).intersects(rect),
                        "Height-only focus \(stage) left the caret outside the viewport: caret=\(rect), visible=\(editor.visibleRect)")
        }
        try requireCaret("before entry")
        let beforeSize = clip.bounds.size
        let originalFrame = window.frame
        workspace.focusMode = true
        settle(window)
        try require(abs(clip.bounds.width - beforeSize.width) < 1, "Focus fixture changed width despite the sidebar already being hidden")
        let nativeFocusChangedHeight = abs(clip.bounds.height - beforeSize.height) > 1
        if !nativeFocusChangedHeight {
            // WindowGroup owns toolbar visibility, which bare hosting omits.
            // Still exercise the same height-only editor/timeline response.
            var taller = originalFrame
            taller.size.height += 80
            window.setFrame(taller, display: true)
            settle(window)
        }
        try require(abs(clip.bounds.height - beforeSize.height) > 1, "Fixture did not exercise a viewport-height change")
        let focusSize = clip.bounds.size
        try requireCaret("on entry")
        editor.breakUndoCoalescing()
        editor.insertText("Focus typing check", replacementRange: editor.selectedRange())
        editor.breakUndoCoalescing()
        settle(window)
        try requireCaret("after typing")
        undo.undo()
        settle(window)
        try require(editor.string == source && controller.activeDocument?.text == source, "Height-only focus lost exact undo or model content")
        workspace.focusMode = false
        if !nativeFocusChangedHeight { window.setFrame(originalFrame, display: true) }
        settle(window)
        try requireCaret("on exit")
        try require(abs(clip.bounds.width - beforeSize.width) < 1, "Leaving focus changed width in the height-only fixture")
        workspace.sidebarVisible = sidebarWasVisible
        workspace.showsTabs = tabsWereVisible
        settle(window)
        try require(editor.string == source && controller.flushAllSaves(), "Focus-height fixture changed saved source")
        checks.append("height-only viewport changes with sidebar hidden retained bottom-of-note caret, typing, and undo")
        return ["beforeViewport": [beforeSize.width, beforeSize.height], "focusViewport": [focusSize.width, focusSize.height],
                "nativeFocusChangedHeight": nativeFocusChangedHeight,
                "method": nativeFocusChangedHeight ? "Window toolbar visibility" : "Explicit native window resize; WindowGroup toolbar visibility requires real-app QA"]
    }

    @MainActor
    static func exerciseEmptyHistory(window: NSWindow, host: NSView, controller: TimelineController,
                                     output: URL, checks: inout [String]) throws {
        controller.jumpToToday()
        settle(window)
        window.makeFirstResponder(nil)
        guard let collection = descendants(in: host).compactMap({ $0 as? NSCollectionView }).first,
              let scroll = collection.enclosingScrollView else { throw ProbeError("Missing empty-history timeline") }
        scroll.contentView.scroll(to: NSPoint(x: 0, y: max(0, collection.bounds.height - scroll.contentView.bounds.height)))
        scroll.reflectScrolledClipView(scroll.contentView)
        settle(window)
        guard let button = descendants(in: host).compactMap({ $0 as? NSButton }).first(where: {
            $0.accessibilityIdentifier() == "timeline.emptyDays" && $0.visibleRect.height > 0
        }) else { throw ProbeError("Consecutive empty historical days did not form an expandable group") }
        try snapshot(host, to: output.appendingPathComponent("empty-history-group.png"))
        let count = collection.numberOfItems(inSection: 0)
        let days = controller.days.map(\.id)
        button.performClick(nil)
        settle(window)
        try require(collection.numberOfItems(inSection: 0) > count, "Expanding empty-history group did not reveal its date rows")
        try require(controller.days.map(\.id) == days, "Expanding empty-history group changed retained document identity")
        try snapshot(host, to: output.appendingPathComponent("empty-history-expanded.png"))
        controller.jumpToToday()
        settle(window)
        try require(editors(in: host).contains { $0.string.contains("Payments sync") && $0.visibleRect.height > 0 }, "Returning from empty history lost today's editor")
        checks.append("consecutive empty days expanded into date rows without changing document identity")
    }

    @MainActor
    static func exerciseCalendar(window: NSWindow, host: NSView, controller: TimelineController, now: Date,
                                 output: URL, checks: inout [String]) throws {
        guard let button = accessibilityNodes(in: host).first(where: { $0.accessibilityLabel() == "Jump to date" }) else {
            throw ProbeError("Calendar control is not accessible")
        }
        // Native toolbar viewers may return false after dispatching the action.
        // The visible popover is the success criterion.
        _ = button.accessibilityPerformPress()
        settle(window)
        guard let popover = NSApplication.shared.windows.first(where: { candidate in
            candidate !== window && candidate.isVisible && candidate.contentView.map {
                accessibilityNodes(in: $0).contains { $0.accessibilityLabel()?.contains(", contains writing") == true }
            } == true
        }), let content = popover.contentView else { throw ProbeError("Calendar did not display written-day indicators") }
        let nodes = accessibilityNodes(in: content)
        let writtenKeys = controller.writtenDayKeys(inMonth: now)
        let month = Calendar.current.dateInterval(of: .month, for: now)!.start
        for day in Calendar.current.range(of: .day, in: .month, for: month)! {
            let date = Calendar.current.date(byAdding: .day, value: day - 1, to: month)!
            let label = date.formatted(date: .complete, time: .omitted)
            guard let node = nodes.first(where: { $0.accessibilityLabel()?.hasPrefix(label) == true }) else {
                throw ProbeError("Calendar omitted accessible date \(label)")
            }
            let key = DayFormatting.dayKey(for: date)
            let hasDot = node.accessibilityLabel()?.contains(", contains writing") == true
            try require(hasDot == writtenKeys.contains(key), "Calendar writing indicator differs from document content for \(key)")
        }
        try snapshot(content, to: output.appendingPathComponent("calendar.png"))
        if let blank = controller.days.last(where: {
            $0.text.isEmpty && $0.date >= month && $0.date < Calendar.current.startOfDay(for: now)
                && !FileManager.default.fileExists(atPath: $0.fileURL.path)
        }) {
            let externalLabel = blank.date.formatted(date: .complete, time: .omitted)
            try "External meeting update\n".write(to: blank.fileURL, atomically: true, encoding: .utf8)
            defer { try? FileManager.default.removeItem(at: blank.fileURL) }
            for _ in 0..<20 {
                settle(window)
                if accessibilityNodes(in: content).contains(where: {
                    $0.accessibilityLabel()?.hasPrefix(externalLabel) == true
                        && $0.accessibilityLabel()?.contains(", contains writing") == true
                }) { break }
            }
            try require(accessibilityNodes(in: content).contains {
                $0.accessibilityLabel()?.hasPrefix(externalLabel) == true
                    && $0.accessibilityLabel()?.contains(", contains writing") == true
            }, "Calendar did not refresh its writing dot after an external file change while open")
            try FileManager.default.removeItem(at: blank.fileURL)
            for _ in 0..<20 {
                settle(window)
                if accessibilityNodes(in: content).contains(where: {
                    $0.accessibilityLabel()?.hasPrefix(externalLabel) == true
                        && $0.accessibilityLabel()?.contains(", empty") == true
                }) { break }
            }
            try require(accessibilityNodes(in: content).contains {
                $0.accessibilityLabel()?.hasPrefix(externalLabel) == true
                    && $0.accessibilityLabel()?.contains(", empty") == true
            }, "Calendar retained a stale writing dot after an external file removal")
            checks.append("open calendar refreshed writing indicators after external file creation and removal")
        }
        let date = Calendar.current.date(byAdding: .day, value: -7, to: now)!
        let label = date.formatted(date: .complete, time: .omitted)
        guard let target = accessibilityNodes(in: content).first(where: { $0.accessibilityLabel()?.hasPrefix(label) == true }) else { throw ProbeError("Missing fixture calendar date") }
        try require(target.accessibilityPerformPress(), "Calendar date rejected a native press")
        settle(window)
        try require(editors(in: host).contains { $0.string.contains("7 days ago") }, "Calendar date did not mount the requested note")
        try require((window.firstResponder as? NSTextView)?.string.contains("7 days ago") == true, "Calendar date did not focus its requested existing editor")
        let historicalToolbarNodes = accessibilityNodes(in: host)
        let toolbarIDs = historicalToolbarNodes.compactMap { $0.accessibilityIdentifier() }.filter { $0.hasPrefix("workspace.") }.sorted()
        let dateValue = historicalToolbarNodes.first { $0.accessibilityIdentifier() == "workspace.calendar" }?.accessibilityValue()
        let historicalCollection = descendants(in: host).compactMap { $0 as? NSCollectionView }.first
        let viewport = historicalCollection?.enclosingScrollView?.contentView.bounds
        let visibleEditorDates = editors(in: host).filter { $0.visibleRect.height > 0 }.map { editor in
            controller.days.first { $0.text == editor.string }?.dayKey ?? "unmatched source"
        }
        try require(historicalToolbarNodes.contains { $0.accessibilityIdentifier() == "workspace.today" },
                    "Historical reading has no return-to-Today action; visibleDay=\(controller.currentViewState.scrollDayKey ?? "nil"), activeDay=\(controller.activeDocument?.dayKey ?? "nil"), request=\(String(describing: controller.scrollRequest)), dateValue=\(String(describing: dateValue)), toolbarIDs=\(toolbarIDs), nativeItems=\(window.toolbar?.items.map { $0.itemIdentifier.rawValue } ?? []), viewport=\(String(describing: viewport)), visibleEditors=\(visibleEditorDates)")
        let emptyDate = Calendar.current.range(of: .day, in: .month, for: month)!.reversed().compactMap {
            Calendar.current.date(byAdding: .day, value: $0 - 1, to: month)
        }.first { $0 < Calendar.current.startOfDay(for: now) && !writtenKeys.contains(DayFormatting.dayKey(for: $0)) }
        if let emptyDate {
            guard let open = accessibilityNodes(in: host).first(where: { $0.accessibilityLabel() == "Jump to date" }) else { throw ProbeError("Calendar control disappeared") }
            _ = open.accessibilityPerformPress()
            settle(window)
            let emptyLabel = emptyDate.formatted(date: .complete, time: .omitted)
            let emptyNode = NSApplication.shared.windows.filter { $0 !== window && $0.isVisible }.compactMap(\.contentView)
                .flatMap { accessibilityNodes(in: $0) }.first { $0.accessibilityLabel()?.hasPrefix(emptyLabel) == true }
            guard let emptyNode else { throw ProbeError("Calendar omitted its blank date") }
            try require(emptyNode.accessibilityLabel()?.contains(", empty") == true && emptyNode.accessibilityPerformPress(), "Blank calendar date is not actionable")
            settle(window)
            guard let emptyDocument = controller.activeDocument else { throw ProbeError("Blank date did not become active") }
            try require(emptyDocument.dayKey == DayFormatting.dayKey(for: emptyDate) && emptyDocument.text.isEmpty,
                        "Blank date opened the wrong document: expected=\(DayFormatting.dayKey(for: emptyDate)), actual=\(emptyDocument.dayKey), active=\(String(describing: controller.activeDate)), source=\(emptyDocument.text.prefix(80))")
            try require((window.firstResponder as? NSTextView)?.string.isEmpty == true, "Blank calendar date did not focus an editable empty buffer")
            try require(!FileManager.default.fileExists(atPath: emptyDocument.fileURL.path), "Viewing a blank historical date created a Markdown file")
            try snapshot(host, to: output.appendingPathComponent("empty-date.png"))
            checks.append("blank calendar date opened for editing without creating an empty file")
        }
        checks.append("calendar writing indicators matched note content and native date press opened the note")
    }

    @MainActor
    static func imageFixture(at url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 640, pixelsHigh: 180,
                                            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: bitmap) else { throw ProbeError("Cannot create local image fixture") }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        NSColor(calibratedRed: 0.14, green: 0.24, blue: 0.25, alpha: 1).setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: 640, height: 180)).fill()
        NSColor(calibratedRed: 0.66, green: 0.8, blue: 0.65, alpha: 1).setFill()
        for index in 0..<7 {
            NSBezierPath(roundedRect: NSRect(x: 32 + index * 84, y: 30 + index * 8, width: 60, height: 40 + index * 10), xRadius: 6, yRadius: 6).fill()
        }
        NSGraphicsContext.restoreGraphicsState()
        guard let png = bitmap.representation(using: .png, properties: [:]) else { throw ProbeError("Cannot encode local image fixture") }
        try png.write(to: url, options: .atomic)
    }

    @MainActor
    static func exerciseRapidInput(editor: NSTextView, window: NSWindow, host: NSView, controller: TimelineController,
                                   original: DayDocument, output: URL, checks: inout [String]) throws {
        let before = editor.string
        window.makeFirstResponder(editor)
        editor.setSelectedRange(NSRange(location: before.utf16.count, length: 0))
        revealSelection(editor, in: host)
        settle(window)
        editor.breakUndoCoalescing()
        guard let undo = editor.undoManager else { throw ProbeError("Rapid-input fixture has no native undo manager") }
        undo.beginUndoGrouping()
        var strokeMilliseconds: [Double] = []
        var inputAndLayoutMilliseconds: [Double] = []
        func typeBurst(_ text: String) throws {
            for character in text {
                try autoreleasepool {
                    let selection = editor.selectedRange()
                    let inserted = String(character)
                    let expected = (editor.string as NSString).replacingCharacters(in: selection, with: inserted)
                    let start = ProcessInfo.processInfo.systemUptime
                    editor.insertText(inserted, replacementRange: selection)
                    strokeMilliseconds.append((ProcessInfo.processInfo.systemUptime - start) * 1000)
                    if let container = editor.textContainer { editor.layoutManager?.ensureLayout(for: container) }
                    inputAndLayoutMilliseconds.append((ProcessInfo.processInfo.systemUptime - start) * 1000)
                    try require(editor.string == expected && editor.selectedRange() == NSRange(location: selection.location + inserted.utf16.count, length: 0),
                                "Rapid native input changed source or moved the caret after \(inserted.debugDescription)")
                }
            }
        }
        // No run-loop waits between these edits: the same mounted editor must redraw
        // newly pasted syntax and character-by-character fence/heading transitions.
        try typeBurst("\n\n## On-call handoff\n\n")
        let pasted = """
        Evan: keep the previous error until the next attempt completes. The customer should see why we're waiting, not just a spinner.

        ```python
        def retry_allowed(code, attempt):
            return code in {429, 502, 503} and attempt < 3
        ```

        - [ ] Check this against yesterday's trace
        """
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        pasteboard.setString(pasted, forType: .string)
        let pasteStart = ProcessInfo.processInfo.systemUptime
        let pastedSuccessfully = autoreleasepool { editor.readSelection(from: pasteboard, type: .string) }
        let pasteMilliseconds = (ProcessInfo.processInfo.systemUptime - pasteStart) * 1000
        try require(pastedSuccessfully, "Native pasteboard read rejected the text fixture")
        let functionName = (editor.string as NSString).range(of: "retry_allowed")
        try require(functionName.location != NSNotFound, "Multiline paste dropped the code block")
        editor.setSelectedRange(functionName)
        editor.insertText("should_retry", replacementRange: editor.selectedRange())
        let codeEnd = (editor.string as NSString).range(of: "attempt < 3", options: .backwards)
        editor.setSelectedRange(NSRange(location: NSMaxRange(codeEnd), length: 0))
        try typeBurst(" and code != 504")
        undo.endUndoGrouping()
        let sorted = strokeMilliseconds.sorted()
        let withLayout = inputAndLayoutMilliseconds.sorted()
        nativeInputTiming = [
            "buildConfiguration": buildConfiguration,
            "documentLinesBefore": before.components(separatedBy: "\n").count,
            "documentUTF16Before": before.utf16.count,
            "nativeInsertCalls": sorted.count,
            "medianInsertCallMilliseconds": sorted[sorted.count / 2],
            "p95InsertCallMilliseconds": sorted[min(sorted.count - 1, Int(Double(sorted.count) * 0.95))],
            "maxInsertCallMilliseconds": sorted.last ?? 0,
            "medianInputAndLayoutMilliseconds": withLayout[withLayout.count / 2],
            "p95InputAndLayoutMilliseconds": withLayout[min(withLayout.count - 1, Int(Double(withLayout.count) * 0.95))],
            "maxInputAndLayoutMilliseconds": withLayout.last ?? 0,
            "nativePasteCallMilliseconds": pasteMilliseconds,
            "footprintAfterBurstBytes": processFootprint(),
            "scope": "Synchronous native input method and forced TextKit layout durations; excludes subsequent run-loop view layout/display, not input-to-screen latency or frame rate."
        ]
        try JSONSerialization.data(withJSONObject: nativeInputTiming, options: [.prettyPrinted, .sortedKeys])
            .write(to: output.appendingPathComponent("native-input-timing.json"), options: .atomic)
        editor.scrollRangeToVisible(editor.selectedRange())
        window.contentView?.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        try requireNonoverlappingLines(editor)
        try snapshot(host, to: output.appendingPathComponent("rapid-paste-immediate.png"))
        settle(window)
        revealSelection(editor, in: host)
        settle(window)
        let after = editor.string
        try require(after.hasPrefix(before) && after.contains("def should_retry(code, attempt):") && after.contains("attempt < 3 and code != 504"), "Rapid typing lost or reordered source")
        try require(controller.activeDocument?.text == after, "Rapid input disagrees with canonical document")
        try require(editors(in: host).contains { $0 === editor }, "Rapid input replaced the native editor")
        try requireNonoverlappingLines(editor)
        let visibleCaret = editor.convert(window.convertFromScreen(editor.firstRect(forCharacterRange: editor.selectedRange(), actualRange: nil)), from: nil)
        try require(editor.visibleRect.intersects(visibleCaret), "Rapid-input screenshot does not include the edited code caret")
        try snapshot(host, to: output.appendingPathComponent("rapid-paste-settled.png"))
        try require(controller.flushAllSaves(), "Rapid input did not save")
        try require(try String(contentsOf: original.fileURL, encoding: .utf8) == after, "Rapid input saved different source")
        undo.undo()
        settle(window)
        try require(editor.string == before && controller.activeDocument?.text == before, "Rapid-input undo did not restore source and model")
        undo.redo()
        settle(window)
        try require(editor.string == after && controller.activeDocument?.text == after, "Rapid-input redo did not restore source and model")
        try requireNonoverlappingLines(editor)
        undo.undo()
        settle(window)
        try require(editor.string == before, "Rapid-input cleanup did not restore the fixture")
        editor.setSelectedRange(NSRange(location: 0, length: 0))
        editor.scrollRangeToVisible(editor.selectedRange())
        if let collection = descendants(in: host).compactMap({ $0 as? NSCollectionView }).first,
           let scroll = collection.enclosingScrollView {
            scroll.contentView.scroll(to: .zero)
            scroll.reflectScrolledClipView(scroll.contentView)
        }
        settle(window)
        checks.append("rapid native paste, heading/fence typing, code edits, and undo/redo retained source without overlapping line fragments")
    }

    @MainActor
    static func revealSelection(_ editor: NSTextView, in host: NSView) {
        guard let collection = descendants(in: host).compactMap({ $0 as? NSCollectionView }).first,
              let scroll = collection.enclosingScrollView, let manager = editor.layoutManager, let container = editor.textContainer,
              manager.numberOfGlyphs > 0 else { return }
        manager.ensureLayout(for: container)
        let character = min(editor.selectedRange().location, max(0, editor.string.utf16.count - 1))
        let glyph = manager.glyphIndexForCharacter(at: character)
        let fragment = manager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
            .offsetBy(dx: editor.textContainerOrigin.x, dy: editor.textContainerOrigin.y)
        let target = editor.convert(fragment, to: collection)
        scroll.contentView.scroll(to: NSPoint(x: 0, y: max(0, target.midY - scroll.contentView.bounds.height * 0.55)))
        scroll.reflectScrolledClipView(scroll.contentView)
    }

    @MainActor
    static func requireNonoverlappingLines(_ editor: NSTextView) throws {
        guard let layout = editor.layoutManager, let container = editor.textContainer else { throw ProbeError("No native line layout") }
        layout.ensureLayout(for: container)
        var bottom: CGFloat = 0
        var overlap: NSRect?
        layout.enumerateLineFragments(forGlyphRange: NSRange(location: 0, length: layout.numberOfGlyphs)) { rect, _, _, _, stop in
            if !rect.minY.isFinite || !rect.height.isFinite || rect.minY < bottom - 0.5 {
                overlap = rect
                stop.pointee = true
            }
            bottom = rect.maxY
        }
        try require(overlap == nil, "Native line fragments overlap after rapid input: \(String(describing: overlap))")
    }

    @MainActor
    static func exercise(editor: NSTextView, window: NSWindow, host: NSView, controller: TimelineController,
                         original: DayDocument, checks: inout [String]) throws {
        window.makeFirstResponder(editor)
        let before = editor.string
        let target = (before as NSString).range(of: "Payments sync")
        try require(target.location != NSNotFound, "Missing edit target")
        editor.setSelectedRange(NSRange(location: NSMaxRange(target), length: 0))
        editor.insertText(" — saved locally", replacementRange: editor.selectedRange())
        settle(window)
        try require(editor.string.contains("Payments sync — saved locally"), "Native typing did not reach the document")
        try require(editors(in: host).contains(where: { $0 === editor }), "Typing recreated the active editor")
        try require(controller.days.contains(where: { $0.text == editor.string }), "View and document model disagree after typing")
        checks.append("native edit preserved editor identity and updated document")

        guard let undo = editor.undoManager, undo.canUndo else { throw ProbeError("Native edit has no undo action") }
        undo.undo()
        settle(window)
        try require(editor.string == before, "Undo did not restore exact source")
        undo.redo()
        settle(window)
        try require(editor.string.contains(" — saved locally"), "Redo did not restore edit")
        checks.append("native undo and redo preserved exact source")

        editor.setMarkedText("に", selectedRange: NSRange(location: 1, length: 0), replacementRange: editor.selectedRange())
        settle(window)
        try require(editor.hasMarkedText(), "Marked-text composition was discarded before commit")
        editor.setMarkedText("日本", selectedRange: NSRange(location: 2, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        editor.insertText("日本語", replacementRange: NSRange(location: NSNotFound, length: 0))
        settle(window)
        try require(!editor.hasMarkedText() && editor.string.contains("日本語"), "Marked-text commit did not preserve composed text")
        checks.append("marked-text API composition and commit retained input")

        let selection = editor.selectedRange()
        editor.insertNewline(nil)
        settle(window)
        try require(editor.selectedRange().location <= (editor.string as NSString).length, "Return left selection outside source")
        let caret = editor.firstRect(forCharacterRange: editor.selectedRange(), actualRange: nil)
        var caretDetails = ""
        if caret.height <= 0, let manager = editor.layoutManager, let container = editor.textContainer {
            manager.ensureLayout(for: container)
            let glyph = manager.glyphIndexForCharacter(at: min(editor.selectedRange().location, max(0, editor.string.utf16.count - 1)))
            caretDetails = " glyph=\(glyph), fragment=\(manager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)), glyphLocation=\(manager.location(forGlyphAt: glyph)), extra=\(manager.extraLineFragmentRect), used=\(manager.usedRect(for: container)), editor=\(editor.frame), visible=\(editor.visibleRect), container=\(container.containerSize), attached=\(editor.window === window)"
        }
        try require(caret.minX.isFinite && caret.minY.isFinite && caret.height > 0,
                    "Return produced invalid caret geometry: rect=\(caret), selection=\(editor.selectedRange()), responder=\(window.firstResponder === editor), prefix=\(editor.string.prefix(130))\(caretDetails)")
        try require(editor.selectedRange().location >= selection.location, "Return unexpectedly moved the caret backwards")
        checks.append("Return retained valid caret and selection")

        editor.setSelectedRange(NSRange(location: (editor.string as NSString).length, length: 0))
        editor.scrollRangeToVisible(editor.selectedRange())
        settle(window)
        try require(editor.window === window && editors(in: host).contains(where: { $0 === editor }), "Scrolling to document end detached the active editor")
        for index in 1...4 {
            editor.insertNewline(nil)
            settle(window)
            try require(editor.window === window && editors(in: host).contains(where: { $0 === editor }), "Return \(index) at document end detached the active editor")
            let screenCaret = editor.firstRect(forCharacterRange: editor.selectedRange(), actualRange: nil)
            let localCaret = editor.convert(window.convertFromScreen(screenCaret), from: nil)
            try require(editor.visibleRect.insetBy(dx: -2, dy: -2).intersects(localCaret),
                        "Return \(index) at document end moved caret \(localCaret) outside viewport \(editor.visibleRect); editor frame \(editor.frame), selection \(editor.selectedRange())/\((editor.string as NSString).length), extra line \(String(describing: editor.layoutManager?.extraLineFragmentRect)), first responder \(window.firstResponder === editor)")
        }
        checks.append("repeated Return at document end kept caret visible")

        let edited = editor.string
        controller.flushSaves()
        try require(controller.notice == nil, "Save reported an error: \(controller.notice?.message ?? "")")
        try require(try String(contentsOf: original.fileURL, encoding: .utf8) == edited, "Saved bytes differ from editor source")
        checks.append("flush and disk reread match edited source")

        let oldSize = host.bounds.size
        resizeDiagnostic("before narrowing", editor: editor, window: window, host: host, controller: controller)
        window.setContentSize(NSSize(width: 900, height: 700))
        settle(window)
        resizeDiagnostic("after narrowing", editor: editor, window: window, host: host, controller: controller)
        try require(editor.string == edited, "Resizing changed source")
        try require(editor.bounds.width > 100 && editor.bounds.height > 20, "Resizing collapsed the editor")
        try require(editors(in: host).contains(where: { $0 === editor }), "Resizing recreated the active editor")
        try requireConcealedRichSource(editor)
        checks.append("window resize retained source and active editor")
        window.setContentSize(oldSize)
        resizeDiagnostic("immediately after widening", editor: editor, window: window, host: host, controller: controller)
        settle(window)
        resizeDiagnostic("after widening settled", editor: editor, window: window, host: host, controller: controller)
        try require(editors(in: host).contains(where: { $0 === editor }),
                    "Restoring window width detached the active editor: old attached=\(editor.window === window), visible=\(editor.visibleRect); matching=\(editors(in: host).filter { $0.string == edited }.map { "\(ObjectIdentifier($0))/\($0.visibleRect)" })")
        try require(window.firstResponder === editor, "Restoring window width lost the editing responder")
        let restoredCaret = editor.convert(window.convertFromScreen(editor.firstRect(forCharacterRange: editor.selectedRange(), actualRange: nil)), from: nil)
        try require(editor.visibleRect.insetBy(dx: -2, dy: -2).intersects(restoredCaret), "Restoring window width moved the editing caret outside the viewport")
    }

    @MainActor
    static func resizeDiagnostic(_ stage: String, editor: NSTextView, window: NSWindow, host: NSView, controller: TimelineController) {
        guard ProcessInfo.processInfo.environment["CURRENT_PROBE_TRACE"] == "1",
              let collection = descendants(in: host).compactMap({ $0 as? NSCollectionView }).first,
              let scroll = collection.enclosingScrollView else { return }
        let rows = collection.indexPathsForVisibleItems().sorted { $0.item < $1.item }.map { path in
            "\(path.item):\(String(describing: collection.layoutAttributesForItem(at: path)?.frame))"
        }
        let caretInWindow = window.convertFromScreen(editor.firstRect(forCharacterRange: editor.selectedRange(), actualRange: nil))
        let caretInCollection = collection.convert(caretInWindow, from: nil)
        let message = "RESIZE \(stage): outer=\(scroll.contentView.bounds), editor=\(editor.frame), visible=\(editor.visibleRect), caret=\(caretInCollection), attached=\(editor.window === window), responder=\(window.firstResponder === editor), selection=\(editor.selectedRange()), active=\(controller.activeDocument?.dayKey ?? "nil"), rows=\(rows)\n"
        FileHandle.standardError.write(Data(message.utf8))
    }

    @MainActor
    static func requireConcealedRichSource(_ editor: NSTextView) throws {
        guard let storage = editor.textStorage else { throw ProbeError("Missing rich source storage") }
        var visibleAnchor: Int?
        storage.enumerateAttribute(NSAttributedString.Key("current.richBlockHeight"), in: NSRange(location: 0, length: storage.length)) { value, range, stop in
            guard value != nil else { return }
            let color = storage.attribute(.foregroundColor, at: range.location, effectiveRange: nil) as? NSColor
            if color?.alphaComponent != 0 { visibleAnchor = range.location; stop.pointee = true }
        }
        try require(visibleAnchor == nil, "Rendered rich block leaked a source glyph at \(visibleAnchor ?? -1) after view updates")
    }

    @MainActor
    static func settle(_ window: NSWindow) {
        // Pump native/SwiftUI updates in a bounded interval, including delayed autosave.
        for _ in 0..<12 {
            // Match NSApplication's per-event autorelease lifetime instead of retaining
            // native drawing temporaries across the entire synthetic session.
            autoreleasepool {
                RunLoop.main.run(until: Date().addingTimeInterval(0.025))
                window.contentView?.layoutSubtreeIfNeeded()
                window.displayIfNeeded()
            }
        }
    }

    @MainActor
    static func editors(in view: NSView) -> [NSTextView] {
        (view as? NSTextView).map { [$0] } ?? view.subviews.flatMap { editors(in: $0) }
    }

    @MainActor
    static func descendants(in view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap { descendants(in: $0) }
    }

    @MainActor
    struct AccessibleNode {
        let object: NSObject
        func accessibilityIdentifier() -> String? { (object as AnyObject).accessibilityIdentifier?() ?? nil }
        func accessibilityLabel() -> String? { (object as AnyObject).accessibilityLabel?() ?? nil }
        func accessibilityPerformPress() -> Bool { (object as AnyObject).accessibilityPerformPress?() ?? false }
        func accessibilityChildren() -> [Any] { (object as AnyObject).accessibilityChildren?() ?? [] }
        func accessibilityValue() -> Any? {
            let selector = NSSelectorFromString("accessibilityValue")
            return object.responds(to: selector) ? object.perform(selector)?.takeUnretainedValue() : nil
        }
    }

    @MainActor
    static func accessibilityNodes(in view: NSView) -> [AccessibleNode] {
        var result: [AccessibleNode] = []
        var visited = Set<ObjectIdentifier>()
        func visit(_ value: Any, depth: Int) {
            guard depth < 40, let object = value as? NSObject,
                  visited.insert(ObjectIdentifier(object)).inserted else { return }
            // SwiftUI's virtual AccessibilityNode responds to the public ObjC
            // accessors but does not declare NSAccessibilityProtocol conformance.
            let node = AccessibleNode(object: object)
            result.append(node)
            for child in node.accessibilityChildren() { visit(child, depth: depth + 1) }
        }
        // Native SwiftUI toolbars live beside the content hosting view in the
        // window frame. Search that public view hierarchy as well as the body.
        visit(view.window?.contentView?.superview ?? view, depth: 0)
        return result
    }

    @MainActor
    static func activateAccessibility() {
        // SwiftUI builds its virtual tree lazily when an accessibility client
        // requests it. Query this probe's own process while its main loop runs.
        let completed = DispatchGroup()
        completed.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            let application = AXUIElementCreateApplication(getpid())
            AXUIElementSetMessagingTimeout(application, 0.5)
            AXUIElementSetAttributeValue(application, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
            var windows: CFTypeRef?
            AXUIElementCopyAttributeValue(application, kAXWindowsAttribute as CFString, &windows)
            completed.leave()
        }
        let deadline = Date().addingTimeInterval(2)
        while completed.wait(timeout: .now()) != .success && Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.025))
        }
    }

    @MainActor
    static func geometry(_ editor: NSTextView, in host: NSView) -> [String: Any] {
        let rect = editor.convert(editor.bounds, to: host)
        let selection = editor.selectedRange()
        return [
            "class": String(describing: type(of: editor)),
            "frame": [rect.minX, rect.minY, rect.width, rect.height],
            "visible": [editor.visibleRect.minX, editor.visibleRect.minY, editor.visibleRect.width, editor.visibleRect.height],
            "sourceUTF16Count": (editor.string as NSString).length,
            "selection": [selection.location, selection.length],
            "textKit": editor.textLayoutManager == nil ? 1 : 2
        ]
    }

    @MainActor
    static func nativeWindowGeometry(_ window: NSWindow) -> [String: Any] {
        func rect(_ value: NSRect) -> [CGFloat] { [value.minX, value.minY, value.width, value.height] }
        let frameView = window.contentView?.superview
        let views = frameView.map(descendants(in:)) ?? []
        let trafficLights = [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton].compactMap { kind -> [String: Any]? in
            guard let button = window.standardWindowButton(kind) else { return nil }
            return ["type": kind.rawValue, "visible": !button.isHidden, "frameInWindow": rect(button.convert(button.bounds, to: nil))]
        }
        return [
            "number": window.windowNumber,
            "frameOnScreen": rect(window.frame),
            "contentLayoutRect": rect(window.contentLayoutRect),
            "toolbarStyle": window.toolbarStyle.rawValue,
            "toolbarVisible": window.toolbar?.isVisible ?? false,
            "toolbarItems": window.toolbar?.items.map(\.itemIdentifier.rawValue) ?? [],
            "trafficLights": trafficLights,
            "splitViews": views.compactMap { $0 as? NSSplitView }.map { rect($0.convert($0.bounds, to: nil)) },
            "nativeLists": views.compactMap { $0 as? NSTableView }.map { rect($0.convert($0.bounds, to: nil)) }
        ]
    }

    @MainActor
    static func checkSidebarWidthPersistence(window: NSWindow, host: NSHostingView<AnyView>, controller: TimelineController,
                                             configuration: CurrentConfigurationStore, defaults: UserDefaults, checks: inout [String]) throws {
        guard let split = descendants(in: host).compactMap({ $0 as? NSSplitView }).first(where: \.isVertical),
              let sidebar = split.arrangedSubviews.first else { throw ProbeError("Native sidebar split view disappeared") }
        let originalWidth = sidebar.bounds.width
        split.setPosition(260, ofDividerAt: 0)
        settle(window)
        let resizedWidth = sidebar.bounds.width
        let savedWidth = defaults.double(forKey: "workspace.sidebarWidth")
        try require(abs(resizedWidth - originalWidth) > 10, "Native divider did not resize the sidebar")
        try require((200...320).contains(savedWidth), "Native sidebar resize did not save a valid column width")
        // SwiftUI measures column content; AppKit's divider includes system
        // insets. Verify restoration through the same native geometry API.
        host.rootView = AnyView(ContentView(controller: controller, configurationStore: configuration,
                                           workspace: WorkspaceViewState(defaults: defaults)).id(UUID()))
        settle(window)
        guard let restored = descendants(in: host).compactMap({ $0 as? NSSplitView }).first(where: \.isVertical),
              let restoredSidebar = restored.arrangedSubviews.first else { throw ProbeError("Restored native sidebar disappeared") }
        try require(abs(restoredSidebar.bounds.width - resizedWidth) <= 1,
                    "Native sidebar width drifted on restored preferences: before=\(resizedWidth), after=\(restoredSidebar.bounds.width), saved=\(savedWidth)")
        restored.setPosition(originalWidth, ofDividerAt: 0)
        settle(window)
        checks.append("native sidebar divider width survived restoring workspace preferences")
    }

    @MainActor
    static func checkNativeShell(window: NSWindow, host: NSView, inspectAccessibility: Bool, checks: inout [String]) throws -> [String: Any] {
        guard let toolbar = window.toolbar, toolbar.isVisible else { throw ProbeError("Shell did not install a visible native window toolbar") }
        let views = descendants(in: host)
        guard let split = views.compactMap({ $0 as? NSSplitView }).first(where: \.isVertical),
              let sidebar = split.arrangedSubviews.first else { throw ProbeError("Sidebar is not hosted in a native split view") }
        let sidebarWidth = sidebar.bounds.width
        try require((199...321).contains(sidebarWidth), "First-launch native sidebar width \(sidebarWidth)pt falls outside its configured 200–320pt bounds")
        try require(views.contains { $0 is NSTableView }, "Sidebar does not contain a native list")
        try require([NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton].allSatisfy {
            window.standardWindowButton($0)?.isHidden == false
        }, "Native window controls are missing")
        if inspectAccessibility {
            let identifiers = Set(accessibilityNodes(in: host).compactMap { $0.accessibilityIdentifier() })
            for identifier in ["workspace.streamSwitcher", "workspace.calendar", "workspace.search", "workspace.newStream", "workspace.options"] {
                try require(identifiers.contains(identifier), "Native toolbar has no accessible \(identifier) control")
            }
        }
        guard let collection = views.compactMap({ $0 as? NSCollectionView }).first,
              let clip = collection.enclosingScrollView?.contentView,
              let first = collection.layoutAttributesForItem(at: IndexPath(item: 0, section: 0)) else {
            throw ProbeError("Native shell has no initial day layout")
        }
        let rowGap = first.frame.minY - clip.bounds.minY
        try require(abs(rowGap - 8) <= 1, "First-day inset is \(rowGap)pt; expected 8pt from the detail viewport")
        let clipRect = clip.convert(clip.bounds, to: nil)
        let rowRect = collection.convert(first.frame, to: nil)
        let firstEditor = editors(in: host).filter { $0.visibleRect.height > 0 }
            .sorted { $0.convert($0.bounds, to: collection).minY < $1.convert($1.bounds, to: collection).minY }.first
        var result: [String: Any] = [
            "sidebarWidth": sidebarWidth,
            "firstDayInsetFromClip": rowGap,
            "clipTopFromWindowContentLayout": window.contentLayoutRect.maxY - clipRect.maxY,
            "firstDayTopFromWindowContentLayout": window.contentLayoutRect.maxY - rowRect.maxY
        ]
        if let editor = firstEditor {
            let editorRect = editor.convert(editor.bounds, to: nil)
            result["firstEditorTopFromWindowContentLayout"] = window.contentLayoutRect.maxY - editorRect.maxY
            if let manager = editor.layoutManager, let container = editor.textContainer, manager.numberOfGlyphs > 0 {
                manager.ensureLayout(for: container)
                let fragment = manager.lineFragmentRect(forGlyphAt: 0, effectiveRange: nil)
                    .offsetBy(dx: editor.textContainerOrigin.x, dy: editor.textContainerOrigin.y)
                let fragmentInWindow = editor.convert(fragment, to: nil)
                result["firstTextFragmentTopFromWindowContentLayout"] = window.contentLayoutRect.maxY - fragmentInWindow.maxY
            }
        }
        checks.append("native toolbar, split view, sidebar list, and window controls mounted with 8pt first-day inset")
        return result
    }

    @MainActor
    static func snapshot(_ view: NSView, to url: URL) throws {
        guard capturesImages else { return }
        try autoreleasepool {
            guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
                throw ProbeError("Could not create snapshot bitmap")
            }
            view.cacheDisplay(in: view.bounds, to: bitmap)
            guard let png = bitmap.representation(using: .png, properties: [:]) else { throw ProbeError("Could not encode snapshot") }
            try png.write(to: url, options: .atomic)
        }
    }

    static func require(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
        if try !condition() { throw ProbeError(message) }
    }

    static let sampleNote = """
    # Payments sync

    09:30 with Maya and Evan. We agreed to keep **retry behavior** behind the existing flag for one more week. The failures in yesterday's sample were mostly expired bank details, so another automatic attempt would add noise without helping the customer. Need to separate those from temporary gateway errors before changing the default.

    ## Follow-ups

    - [ ] Ask support for three failed-payment examples
    - [x] Send Evan the rollout query
    - Retry owner is still unclear

    > Only retry when the failure could resolve without customer action.

    | Owner | Status |
    | :--- | ---: |
    | Maya | Waiting |
    | Evan | **Done** |

    ![Queue sketch](attachments/probe.png)

    ## Retry notes

    The `idempotency_key` must survive each attempt. The worker currently creates it after the queue message is read, which probably explains the duplicate in Tuesday's trace. Check the [incident notes](https://example.com/incidents/retry-queue) before moving that code; the older handler may share the same helper.

    ```python
    def should_retry(status_code, attempt):
        temporary = status_code in {429, 502, 503}
        return temporary and attempt < 3
    ```

    ---

    Not sure about the manual override yet. If an admin retries while the worker is asleep, do we cancel the scheduled attempt or let the key reject it? Need to ask
    """

    static func stressAppendix(minimumLines: Int) -> String {
        var appendix = ""
        var index = 0
        while (sampleNote + appendix).components(separatedBy: "\n").count < minimumLines {
            appendix += """


            ## Queue review \(index)

            Evan checked another batch of **delayed attempts** after the deploy. The gateway returned `503` for a few seconds, then recovered; the queue kept the original key and the second attempt succeeded. We still need the *customer-visible status* to distinguish a scheduled retry from a payment that needs updated bank details.
            - [ ] Compare batch \(index) with the support export
            - [x] Check the original request key
            > Support wants the previous error visible until the retry finishes.

            | Attempt | Result |
            | --- | --- |
            | \(index) | Queued |

            Maybe keep the old error alongside the new status until we have a cleaner explanation.

            """
            index += 1
        }
        return appendix
    }
}
