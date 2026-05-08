import Foundation
import CurrentFeature

@main
struct CurrentFeatureChecks {
    static func main() async throws {
        try configurationLocationsPreferXDGConfig()
        try configurationParserAppliesGhosttySyntax()
        try configurationParserKeepsLastValidValueAndSupportsEmptyResets()
        try configurationParserSupportsIncludesOptionalIncludesAndCycles()
        try configurationStoreCreatesEditableTemplateOnDemand()
        try configurationAffectsLayoutAndEditorMetrics()
        try dayPathsUseTransparentDailyMarkdownLayout()
        try bootstrapCreatesDailyStreamAndTodayFile()
        try timelineControllerAppliesConfigurationBeforeBootstrap()
        try timelineControllerUsesConfiguredLibraryRootBeforeBootstrap()
        try loadOlderDaysAppendsPastBelowToday()
        try loadOlderDaysDoesNotCreateMissingDayFiles()
        try loadOlderDaysStopsAtStreamCreation()
        try hideEmptyWeekendsConfigurationControlsTimeline()
        try loadOlderDaysKeepsRenderedHistoryBounded()
        try loadOlderDaysKeepsOlderActualFilesReachable()
        try loadNewerWindowRestoresTrimmedTopHistory()
        try loadNewerWindowReloadsCleanTrimmedDocuments()
        try dirtyOffWindowDocumentsStayCachedAndSave()
        try timelineControllerTogglesHistoricalDayMinimization()
        try timelineControllerIgnoresTodayMinimization()
        try rowHeightCalculatorKeepsEmptyCollapsedRowsStable()
        try rowHeightCalculatorExpandsActiveEmptyRows()
        try rowHeightCalculatorCollapsesMinimizedHistoricalTextRows()
        try rowHeightCalculatorKeepsTodayExpandedWhenMinimized()
        try rowHeightCalculatorUsesLargeMinimumForEmptyToday()
        try rowHeightCalculatorGrowsForMultilineText()
        try rowHeightCalculatorUsesRenderedMarkdownMetrics()
        try timelineLayoutMetricsCenterTheWritingColumn()
        try timelineLayoutMetricsPreventWideViewportWrapping()
        try markdownListEditingContinuesCommonLists()
        try markdownListBackspaceExitsEmptyItems()
        try markdownTaskEditingTogglesCurrentLine()
        try markdownInlineFormattingWrapsSelectedText()
        try markdownInlineFormattingLeavesCollapsedSelectionToTypingMarks()
        try markdownInlineFormattingUsesModifierSetSemantics()
        try markdownInlineFormattingExcludesStructuralListPrefixes()
        try markdownInlineFormattingExcludesStructuralHeadingPrefixes()
        try markdownInlineFormattingPreservesComposedCharacters()
        try markdownInlineFormattingLinksSelectedTextWithClipboardURL()
        try markdownInlineRenderingFindsHiddenSyntaxRanges()
        try markdownRenderedContentIgnoresEmptyStructuralMarkers()
        try markdownHeadingRenderingTracksNotionLikeShortcuts()
        try markdownHeadingSelectionKeepsCollapsedCaretsForLiveMode()
        try markdownHeadingBackspaceExitsBlock()
        try markdownHorizontalRuleRenderingTracksShortcuts()
        try markdownHorizontalRuleDisplayStateTracksCommittedLines()
        try markdownHorizontalRuleBackspaceExitsBlock()
        try markdownInlineBackspaceHandlesHiddenMarkers()
        try await autosaveWritesOnlyTheEditedDay()
        try rolloverCreatesANewTodayAndKeepsHistoryVisible()
        try streamStoreDetectsExternalConflictsBeforeOverwrite()
        try dayCacheEvictsCleanDocumentsButPinsDirtyAndToday()
        print("CurrentFeatureChecks passed")
    }

    static func configurationLocationsPreferXDGConfig() throws {
        let root = try temporaryDirectory()
        let home = root.appendingPathComponent("home", isDirectory: true)
        let xdgRoot = root.appendingPathComponent("xdg", isDirectory: true)
        let appSupport = root.appendingPathComponent("app-support/com.raj.current", isDirectory: true)
        let locations = CurrentConfigurationLocations(
            environment: ["XDG_CONFIG_HOME": xdgRoot.path],
            homeDirectory: home,
            applicationSupportDirectory: appSupport
        )

        try check(
            locations.primaryEditableURL.path.hasSuffix("/xdg/current/config.current"),
            "Primary editable config should be the XDG config.current path"
        )

        try writeText("recent-days = 9", to: appSupport.appendingPathComponent("config.current"))
        try writeText("recent-days = 4", to: xdgRoot.appendingPathComponent("current/config"))

        let store = CurrentConfigurationStore(locations: locations, homeDirectory: home)

        try check(store.configuration.recentDays == 4, "XDG config should win before Application Support")
        try check(
            store.loadedRootURL?.path.hasSuffix("/xdg/current/config") == true,
            "Expected XDG config fallback to be the loaded root"
        )
    }

    static func configurationParserAppliesGhosttySyntax() throws {
        let store = try configurationStore(
            rootConfig: """
            # Current ignores whole-line comments.
            library-root = "~/notes/current"
            font-family = "JetBrains Mono"
            font-size = 15
            line-height = 24
            content-width = 760
            recent-days = 10
            history-batch-days = 8
            history-window-days = 90
            autosave-delay = 1.25
            hide-empty-weekends = true
            markdown-marker-visibility = muted
            unknown-key = sure
            this is not valid
            """
        )
        let configuration = store.configuration

        try check(configuration.libraryRoot?.path.hasSuffix("/home/notes/current") == true, "Quoted library-root did not parse")
        try check(configuration.fontFamily == "JetBrains Mono", "Quoted font-family did not parse")
        try check(configuration.fontSize == 15, "font-size did not parse")
        try check(configuration.lineHeight == 24, "line-height did not parse")
        try check(configuration.contentWidth == 760, "content-width did not parse")
        try check(configuration.recentDays == 10, "recent-days did not parse")
        try check(configuration.historyBatchDays == 8, "history-batch-days did not parse")
        try check(configuration.historyWindowDays == 90, "history-window-days did not parse")
        try check(configuration.autosaveDelay == 1.25, "autosave-delay did not parse")
        try check(configuration.hideEmptyWeekends == true, "hide-empty-weekends did not parse")
        try check(configuration.markdownMarkerVisibility == .hidden, "muted marker visibility should parse as hidden")
        try check(store.diagnostics.count == 2, "Expected diagnostics for unknown and malformed lines")
    }

    static func configurationParserKeepsLastValidValueAndSupportsEmptyResets() throws {
        let store = try configurationStore(
            rootConfig: """
            font-size = 16
            font-size = no
            line-height = 26
            line-height =
            recent-days = 3
            recent-days = -1
            content-width = 900
            content-width =
            hide-empty-weekends = yes
            hide-empty-weekends = maybe
            hide-empty-weekends =
            markdown-marker-visibility = visible
            """
        )
        let configuration = store.configuration

        try check(configuration.fontSize == 16, "Invalid font-size should keep the last valid value")
        try check(configuration.lineHeight == CurrentConfiguration.default.lineHeight, "Empty line-height should reset to default")
        try check(configuration.recentDays == 3, "Invalid recent-days should keep the last valid value")
        try check(configuration.contentWidth == CurrentConfiguration.default.contentWidth, "Empty content-width should reset to default")
        try check(configuration.hideEmptyWeekends == CurrentConfiguration.default.hideEmptyWeekends, "Empty hide-empty-weekends should reset to default")
        try check(configuration.markdownMarkerVisibility == .hidden, "Invalid marker visibility should keep the default")
        try check(store.diagnostics.count == 4, "Expected diagnostics for invalid numeric, boolean, and marker values")
    }

    static func configurationParserSupportsIncludesOptionalIncludesAndCycles() throws {
        let root = try temporaryDirectory()
        let home = root.appendingPathComponent("home", isDirectory: true)
        let xdgRoot = root.appendingPathComponent("xdg", isDirectory: true)
        let appSupport = root.appendingPathComponent("app-support/com.raj.current", isDirectory: true)
        let configRoot = xdgRoot.appendingPathComponent("current", isDirectory: true)
        let rootConfig = configRoot.appendingPathComponent("config.current")
        let included = configRoot.appendingPathComponent("nested/machine.current")
        let loop = configRoot.appendingPathComponent("loop.current")

        try writeText(
            """
            font-size = 14
            content-width = 650
            config-file = nested/machine.current
            config-file = ?missing.current
            config-file = loop.current
            line-height = 21
            """,
            to: rootConfig
        )
        try writeText(
            """
            font-size = 16
            content-width =
            recent-days = 11
            """,
            to: included
        )
        try writeText("config-file = config.current", to: loop)

        let locations = CurrentConfigurationLocations(
            environment: ["XDG_CONFIG_HOME": xdgRoot.path],
            homeDirectory: home,
            applicationSupportDirectory: appSupport
        )
        let store = CurrentConfigurationStore(locations: locations, homeDirectory: home)

        try check(store.configuration.fontSize == 16, "Included file should override the containing file")
        try check(store.configuration.contentWidth == CurrentConfiguration.default.contentWidth, "Included empty value should reset to default")
        try check(store.configuration.lineHeight == 21, "Containing file values without include overrides should remain")
        try check(store.configuration.recentDays == 11, "Included recent-days did not apply")
        try check(
            store.diagnostics.contains { $0.message.contains("cyclic") },
            "Expected a cycle diagnostic for repeated config-file includes"
        )
        try check(
            !store.diagnostics.contains { $0.message.contains("missing.current") },
            "Optional missing includes should not produce diagnostics"
        )
    }

    static func configurationStoreCreatesEditableTemplateOnDemand() throws {
        let root = try temporaryDirectory()
        let home = root.appendingPathComponent("home", isDirectory: true)
        let xdgRoot = root.appendingPathComponent("xdg", isDirectory: true)
        let appSupport = root.appendingPathComponent("app-support/com.raj.current", isDirectory: true)
        let locations = CurrentConfigurationLocations(
            environment: ["XDG_CONFIG_HOME": xdgRoot.path],
            homeDirectory: home,
            applicationSupportDirectory: appSupport
        )
        let store = CurrentConfigurationStore(locations: locations, homeDirectory: home)

        try check(store.loadedRootURL == nil, "No config should be loaded before one exists")

        let url = try store.ensureEditableConfigurationFile()
        let text = try String(contentsOf: url, encoding: .utf8)

        try check(url == locations.primaryEditableURL, "Edit Settings should create the primary XDG config.current")
        try check(text.contains("# Current configuration"), "Editable template should contain commented defaults")
        try check(text.contains("# library-root = ~/Documents/current"), "Editable template should document the library root")
        try check(text.contains("# hide-empty-weekends = false"), "Editable template should document weekend hiding")
        try check(text.contains("# markdown-marker-visibility = hidden"), "Editable template should document marker visibility")
        try check(CurrentConfigurationStore(locations: locations, homeDirectory: home).diagnostics.isEmpty, "Comment-only template should parse cleanly")
    }

    static func configurationAffectsLayoutAndEditorMetrics() throws {
        let configuration = CurrentConfiguration(fontSize: 18, lineHeight: 30, contentWidth: 640)
        let defaultHeight = TimelineRowHeightCalculator.measuredEditorHeight(
            text: "A configured editor line",
            width: 640,
            minimumHeight: 0
        )
        let configuredHeight = TimelineRowHeightCalculator.measuredEditorHeight(
            text: "A configured editor line",
            width: 640,
            minimumHeight: 0,
            configuration: configuration
        )

        try check(
            TimelineLayoutMetrics.itemWidth(availableWidth: 820, configuration: configuration) == 640,
            "Configured content width should control timeline item width"
        )
        try check(
            TimelineLayoutMetrics.horizontalInset(availableWidth: 820, configuration: configuration) == 90,
            "Configured content width should recenter the writing column"
        )
        try check(configuredHeight > defaultHeight, "Configured editor font/line metrics should affect measured height")
    }

    static func dayPathsUseTransparentDailyMarkdownLayout() throws {
        let root = try temporaryRoot()
        let calendar = fixedCalendar()
        let store = StreamStore(libraryRoot: root, calendar: calendar)
        let stream = try store.defaultStream()
        let date = try require(calendar.date(from: DateComponents(year: 2026, month: 4, day: 29)))

        let url = store.dayURL(for: date, in: stream)

        try check(url.path.hasSuffix("/current/streams/daily/2026/04/2026-04-29.md"), "Unexpected day path: \(url.path)")
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
        try check(controller.days.map(\.id) == ["2026-04-29"], "Bootstrap should not render blank days before stream creation")
        try check(
            FileManager.default.fileExists(atPath: root.appendingPathComponent("streams/daily/2026/04/2026-04-29.md").path),
            "Today file was not created"
        )
    }

    @MainActor
    static func timelineControllerAppliesConfigurationBeforeBootstrap() throws {
        let root = try temporaryRoot()
        let calendar = fixedCalendar()
        let now = try require(calendar.date(from: DateComponents(year: 2026, month: 4, day: 29, hour: 9)))
        let createdAt = try require(calendar.date(from: DateComponents(year: 2026, month: 4, day: 23, hour: 9)))
        let store = try storeWithDefaultStreamCreatedAt(createdAt, root: root, calendar: calendar)
        let controller = TimelineController(
            store: store,
            cache: DayCache(calendar: calendar),
            now: now
        )

        controller.apply(configuration: CurrentConfiguration(
            recentDays: 3,
            historyBatchDays: 4,
            historyWindowDays: 9,
            autosaveDelay: 1.2
        ))
        controller.bootstrapIfNeeded(now: now)
        controller.loadOlderDays()

        try check(controller.recentDayCount == 3, "Controller did not apply configured recent days")
        try check(controller.historyBatchSize == 4, "Controller did not apply configured batch size")
        try check(controller.historyWindowDayCount == 9, "Controller did not apply configured history window size")
        try check(controller.autosaveDelay == 1.2, "Controller did not apply configured autosave delay")
        try check(
            controller.days.map(\.id) == ["2026-04-29", "2026-04-28", "2026-04-27", "2026-04-26", "2026-04-25", "2026-04-24", "2026-04-23"],
            "Configured recent and batch day counts should drive launch and older history, got \(controller.days.map(\.id))"
        )
    }

    @MainActor
    static func timelineControllerUsesConfiguredLibraryRootBeforeBootstrap() throws {
        let root = try temporaryRoot()
        let configuredRoot = try temporaryDirectory().appendingPathComponent("notes/current", isDirectory: true)
        let calendar = fixedCalendar()
        let now = try require(calendar.date(from: DateComponents(year: 2026, month: 4, day: 29, hour: 9)))
        let controller = TimelineController(
            store: StreamStore(libraryRoot: root, calendar: calendar),
            cache: DayCache(calendar: calendar),
            now: now
        )

        controller.apply(configuration: CurrentConfiguration(libraryRoot: configuredRoot, recentDays: 1))
        controller.bootstrapIfNeeded(now: now)

        try check(controller.store.libraryRoot == configuredRoot.standardizedFileURL, "Controller did not apply configured library root")
        try check(
            FileManager.default.fileExists(atPath: configuredRoot.appendingPathComponent("streams/daily/2026/04/2026-04-29.md").path),
            "Configured library root did not receive today's file"
        )
        try check(
            !FileManager.default.fileExists(atPath: root.appendingPathComponent("streams/daily/2026/04/2026-04-29.md").path),
            "Fallback library root should stay untouched when library-root is configured"
        )
    }

    @MainActor
    static func loadOlderDaysAppendsPastBelowToday() throws {
        let root = try temporaryRoot()
        let calendar = fixedCalendar()
        let now = try require(calendar.date(from: DateComponents(year: 2026, month: 4, day: 29, hour: 9)))
        let createdAt = try require(calendar.date(from: DateComponents(year: 2026, month: 4, day: 25, hour: 9)))
        let store = try storeWithDefaultStreamCreatedAt(createdAt, root: root, calendar: calendar)
        let controller = TimelineController(
            store: store,
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
        let createdAt = try require(calendar.date(from: DateComponents(year: 2026, month: 4, day: 23, hour: 9)))
        let store = try storeWithDefaultStreamCreatedAt(createdAt, root: root, calendar: calendar)
        let controller = TimelineController(
            store: store,
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
            !FileManager.default.fileExists(atPath: root.appendingPathComponent("streams/daily/2026/04/2026-04-27.md").path),
            "Scrolling history should not create missing day files"
        )
    }

    @MainActor
    static func loadOlderDaysStopsAtStreamCreation() throws {
        let root = try temporaryRoot()
        let calendar = fixedCalendar()
        let now = try require(calendar.date(from: DateComponents(year: 2026, month: 4, day: 29, hour: 9)))
        let createdAt = try require(calendar.date(from: DateComponents(year: 2026, month: 4, day: 26, hour: 9)))
        let store = try storeWithDefaultStreamCreatedAt(createdAt, root: root, calendar: calendar)
        let controller = TimelineController(
            store: store,
            cache: DayCache(calendar: calendar),
            recentDayCount: 2,
            historyBatchSize: 5,
            now: now
        )
        controller.bootstrapIfNeeded(now: now)

        controller.loadOlderDays()
        controller.loadOlderDays()

        try check(
            controller.days.map(\.id) == ["2026-04-29", "2026-04-28", "2026-04-27", "2026-04-26"],
            "Blank placeholder history should stop at the stream creation day"
        )
        try check(controller.canLoadOlderDays == false, "History loader should stop when there are no older blanks or files")
        try check(
            !FileManager.default.fileExists(atPath: root.appendingPathComponent("streams/daily/2026/04/2026-04-25.md").path),
            "Blank history days should stay in memory until edited"
        )
    }

    @MainActor
    static func hideEmptyWeekendsConfigurationControlsTimeline() throws {
        let root = try temporaryRoot()
        let calendar = fixedCalendar()
        let now = try require(calendar.date(from: DateComponents(year: 2026, month: 5, day: 4, hour: 9)))
        let createdAt = try require(calendar.date(from: DateComponents(year: 2026, month: 5, day: 1, hour: 9)))
        let store = try storeWithDefaultStreamCreatedAt(createdAt, root: root, calendar: calendar)
        let stream = try store.defaultStream()
        let saturday = try require(calendar.date(from: DateComponents(year: 2026, month: 5, day: 2, hour: 9)))
        try writeDay(saturday, text: "Weekend note", stream: stream, store: store)

        let controller = TimelineController(
            store: store,
            cache: DayCache(calendar: calendar),
            recentDayCount: 4,
            now: now
        )
        controller.apply(configuration: CurrentConfiguration(hideEmptyWeekends: true))
        controller.bootstrapIfNeeded(now: now)

        try check(
            controller.days.map(\.id) == ["2026-05-04", "2026-05-02", "2026-05-01"],
            "Empty Sundays should hide, but weekend notes and weekdays should stay visible"
        )
        try check(
            controller.days.first { $0.id == "2026-05-02" }?.text == "Weekend note",
            "Weekend notes should remain loaded when empty weekends are hidden"
        )
    }

    @MainActor
    static func loadOlderDaysKeepsRenderedHistoryBounded() throws {
        let root = try temporaryRoot()
        let calendar = fixedCalendar()
        let now = try require(calendar.date(from: DateComponents(year: 2026, month: 4, day: 29, hour: 9)))
        let createdAt = try require(calendar.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: 9)))
        let store = try storeWithDefaultStreamCreatedAt(createdAt, root: root, calendar: calendar)
        let controller = TimelineController(
            store: store,
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
        let createdAt = try require(calendar.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: 9)))
        let store = try storeWithDefaultStreamCreatedAt(createdAt, root: root, calendar: calendar)
        let controller = TimelineController(
            store: store,
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
        let createdAt = try require(calendar.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: 9)))
        let store = try storeWithDefaultStreamCreatedAt(createdAt, root: root, calendar: calendar)
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
        let createdAt = try require(calendar.date(from: DateComponents(year: 2026, month: 4, day: 1, hour: 9)))
        let store = try storeWithDefaultStreamCreatedAt(createdAt, root: root, calendar: calendar)
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

        let todayPath = root.appendingPathComponent("streams/daily/2026/04/2026-04-29.md")
        let savedText = try String(contentsOf: todayPath, encoding: .utf8)
        try check(savedText == "Pinned dirty note", "Dirty off-window document did not save correctly")
        try check(controller.cache[now]?.isDirty == false, "Saved off-window document should be clean")
    }

    @MainActor
    static func timelineControllerTogglesHistoricalDayMinimization() throws {
        let root = try temporaryRoot()
        let calendar = fixedCalendar()
        let now = try require(calendar.date(from: DateComponents(year: 2026, month: 4, day: 29, hour: 9)))
        let yesterday = calendar.addingDays(-1, to: now)
        let store = try storeWithDefaultStreamCreatedAt(yesterday, root: root, calendar: calendar)
        let stream = try store.defaultStream()
        try writeDay(yesterday, text: "Yesterday notes", stream: stream, store: store)
        let controller = TimelineController(
            store: store,
            cache: DayCache(calendar: calendar),
            recentDayCount: 2,
            now: now
        )

        controller.bootstrapIfNeeded(now: now)
        controller.setActiveDate(yesterday)

        try check(controller.activeDayID == "2026-04-28", "Historical day should become active before minimizing")

        controller.toggleDayMinimized(yesterday)

        try check(controller.isDayMinimized(yesterday), "Historical text day should be minimized")
        try check(controller.minimizedDayIDs == Set(["2026-04-28"]), "Minimized day IDs should contain the historical day")
        try check(controller.activeDayID == nil, "Minimized active day should stop being treated as active")

        controller.toggleDayMinimized(yesterday)

        try check(!controller.isDayMinimized(yesterday), "Second toggle should expand the historical day")
        try check(controller.activeDayID == nil, "Expanding a minimized day should not make it active")

        controller.toggleDayMinimized(yesterday)
        controller.apply(configuration: CurrentConfiguration(
            libraryRoot: try temporaryDirectory().appendingPathComponent("new-current", isDirectory: true),
            recentDays: 1
        ))

        try check(controller.minimizedDayIDs.isEmpty, "Changing stream storage should clear session-only minimized state")
    }

    @MainActor
    static func timelineControllerIgnoresTodayMinimization() throws {
        let root = try temporaryRoot()
        let calendar = fixedCalendar()
        let now = try require(calendar.date(from: DateComponents(year: 2026, month: 4, day: 29, hour: 9)))
        let controller = TimelineController(
            store: StreamStore(libraryRoot: root, calendar: calendar),
            cache: DayCache(calendar: calendar),
            now: now
        )

        controller.bootstrapIfNeeded(now: now)
        controller.toggleDayMinimized(now)

        try check(controller.minimizedDayIDs.isEmpty, "Today should not be minimizable")
        try check(!controller.isDayMinimized(now), "Today should never report as minimized")
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

    static func rowHeightCalculatorCollapsesMinimizedHistoricalTextRows() throws {
        let calendar = fixedCalendar()
        let date = try require(calendar.date(from: DateComponents(year: 2026, month: 4, day: 28)))
        let document = DayDocument(streamID: UUID(), date: date, fileURL: URL(fileURLWithPath: "/tmp/text.md"), text: "Notes from yesterday")

        let expandedHeight = TimelineRowHeightCalculator.height(for: document, isToday: false, width: 700)
        let minimizedHeight = TimelineRowHeightCalculator.height(for: document, isToday: false, isMinimized: true, width: 700)

        try check(expandedHeight > TimelineRowHeightCalculator.collapsedEmptyDayHeight, "Text rows should normally expand")
        try check(
            minimizedHeight == TimelineRowHeightCalculator.collapsedEmptyDayHeight,
            "Minimized historical text rows should use collapsed height"
        )
    }

    static func rowHeightCalculatorKeepsTodayExpandedWhenMinimized() throws {
        let calendar = fixedCalendar()
        let date = try require(calendar.date(from: DateComponents(year: 2026, month: 4, day: 29)))
        let document = DayDocument(streamID: UUID(), date: date, fileURL: URL(fileURLWithPath: "/tmp/today-text.md"), text: "Today notes")

        let expandedHeight = TimelineRowHeightCalculator.height(for: document, isToday: true, width: 700)
        let minimizedHeight = TimelineRowHeightCalculator.height(for: document, isToday: true, isMinimized: true, width: 700)

        try check(minimizedHeight == expandedHeight, "Today should ignore minimized row-height state")
        try check(minimizedHeight > TimelineRowHeightCalculator.collapsedEmptyDayHeight, "Today should remain expanded")
    }

    static func rowHeightCalculatorUsesLargeMinimumForEmptyToday() throws {
        let calendar = fixedCalendar()
        let date = try require(calendar.date(from: DateComponents(year: 2026, month: 4, day: 29)))
        let document = DayDocument(streamID: UUID(), date: date, fileURL: URL(fileURLWithPath: "/tmp/today.md"), text: "")
        let emptyHeading = DayDocument(streamID: UUID(), date: date, fileURL: URL(fileURLWithPath: "/tmp/today-heading.md"), text: "## ")
        let firstLetter = DayDocument(streamID: UUID(), date: date, fileURL: URL(fileURLWithPath: "/tmp/today-first-letter.md"), text: "A")

        let height = TimelineRowHeightCalculator.height(for: document, isToday: true, width: 700)
        let emptyHeadingHeight = TimelineRowHeightCalculator.height(for: emptyHeading, isToday: true, width: 700)
        let firstLetterHeight = TimelineRowHeightCalculator.height(for: firstLetter, isToday: true, width: 700)

        try check(height >= 320, "Today empty row should reserve the large editor minimum")
        try check(emptyHeadingHeight == height, "Empty heading markers should keep the same Today breathing room as an empty note")
        try check(firstLetterHeight == height, "Typing the first letter should not shrink Today's editor")
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

    static func rowHeightCalculatorUsesRenderedMarkdownMetrics() throws {
        let plainHeight = TimelineRowHeightCalculator.measuredEditorHeight(
            text: "Heading",
            width: 700,
            minimumHeight: 0
        )
        let headingHeight = TimelineRowHeightCalculator.measuredEditorHeight(
            text: "# Heading",
            width: 700,
            minimumHeight: 0
        )
        let wrappedPlainHeight = TimelineRowHeightCalculator.measuredEditorHeight(
            text: String(repeating: "x", count: 10),
            width: 80,
            minimumHeight: 0
        )
        let wrappedHiddenSyntaxHeight = TimelineRowHeightCalculator.measuredEditorHeight(
            text: "**\(String(repeating: "x", count: 10))**",
            width: 80,
            minimumHeight: 0
        )
        let horizontalRuleHeight = TimelineRowHeightCalculator.measuredEditorHeight(
            text: "Before\n---\nAfter",
            width: 700,
            minimumHeight: 0
        )
        let committedRuleHeight = TimelineRowHeightCalculator.measuredEditorHeight(
            text: "---\n",
            width: 700,
            minimumHeight: 0
        )
        let typingNextLineHeight = TimelineRowHeightCalculator.measuredEditorHeight(
            text: "---\nA",
            width: 700,
            minimumHeight: 0
        )
        let threeLineHeight = TimelineRowHeightCalculator.measuredEditorHeight(
            text: "Before\n \nAfter",
            width: 700,
            minimumHeight: 0
        )

        try check(headingHeight > plainHeight, "Heading Markdown should measure with rendered heading metrics")
        try check(
            wrappedHiddenSyntaxHeight == wrappedPlainHeight,
            "Hidden inline markers should not add wrapping height"
        )
        try check(
            abs(horizontalRuleHeight - threeLineHeight) <= 1,
            "Horizontal rules should measure as rendered divider lines instead of visible marker text"
        )
        try check(
            abs(committedRuleHeight - typingNextLineHeight) <= 1,
            "Typing on the line after a committed divider should not remeasure the divider block"
        )
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

    static func markdownListBackspaceExitsEmptyItems() throws {
        let bullet = try require(MarkdownListEditing.emptyItemBackspaceEdit(
            in: "- ",
            selectedRange: NSRange(location: 2, length: 0)
        ))
        try check(bullet.range == NSRange(location: 0, length: 2), "Backspace should remove empty bullet marker")
        try check(bullet.replacement == "", "Backspace should exit empty bullet item")
        try check(bullet.selectedRangeAfterEdit == NSRange(location: 0, length: 0), "Cursor should return to the list line start")

        let ordered = try require(MarkdownListEditing.emptyItemBackspaceEdit(
            in: "1. ",
            selectedRange: NSRange(location: 3, length: 0)
        ))
        try check(ordered.range == NSRange(location: 0, length: 3), "Backspace should remove empty ordered marker")

        let task = try require(MarkdownListEditing.emptyItemBackspaceEdit(
            in: "- [ ] ",
            selectedRange: NSRange(location: 6, length: 0)
        ))
        try check(task.range == NSRange(location: 0, length: 6), "Backspace should remove empty task marker")

        let orderedTask = try require(MarkdownListEditing.emptyItemBackspaceEdit(
            in: "1. [x] ",
            selectedRange: NSRange(location: 7, length: 0)
        ))
        try check(orderedTask.range == NSRange(location: 0, length: 7), "Backspace should remove empty ordered task marker")

        let indentedText = "Before\n  - \nAfter"
        let indented = try require(MarkdownListEditing.emptyItemBackspaceEdit(
            in: indentedText,
            selectedRange: NSRange(location: "Before\n  - ".utf16.count, length: 0)
        ))
        try check(indented.range == NSRange(location: "Before\n".utf16.count, length: "  - ".utf16.count), "Backspace should remove only the current empty indented item")

        try check(MarkdownListEditing.emptyItemBackspaceEdit(
            in: "- item",
            selectedRange: NSRange(location: 2, length: 0)
        ) == nil, "Backspace should not exit non-empty bullet items")
        try check(MarkdownListEditing.emptyItemBackspaceEdit(
            in: "1. item",
            selectedRange: NSRange(location: 3, length: 0)
        ) == nil, "Backspace should not exit non-empty ordered items")

        let fenced = "```\n- \n```"
        try check(MarkdownListEditing.emptyItemBackspaceEdit(
            in: fenced,
            selectedRange: NSRange(location: "```\n- ".utf16.count, length: 0)
        ) == nil, "Backspace should not exit lists inside fenced code")
    }

    static func markdownTaskEditingTogglesCurrentLine() throws {
        let unchecked = "- [ ] Follow up"
        let uncheckedEdit = try require(MarkdownListEditing.taskToggleEdit(
            in: unchecked,
            selectedRange: NSRange(location: unchecked.utf16.count, length: 0)
        ))
        try check(uncheckedEdit.range == NSRange(location: 3, length: 1), "Unchecked task should replace only the checkbox state")
        try check(uncheckedEdit.replacement == "x", "Unchecked task should become checked")
        try check(uncheckedEdit.selectedRangeAfterEdit == NSRange(location: unchecked.utf16.count, length: 0), "Task toggle should preserve selection")

        let checked = "Before\n1. [x] Done\nAfter"
        let checkedEdit = try require(MarkdownListEditing.taskToggleEdit(
            in: checked,
            selectedRange: NSRange(location: "Before\n1. [x]".utf16.count, length: 0)
        ))
        try check(checkedEdit.replacement == " ", "Checked ordered task should become unchecked")

        let plain = MarkdownListEditing.taskToggleEdit(
            in: "- ordinary item",
            selectedRange: NSRange(location: 3, length: 0)
        )
        try check(plain == nil, "Non-task list items should not toggle")

        let fenced = "```\n- [ ] code\n```"
        let fencedEdit = MarkdownListEditing.taskToggleEdit(
            in: fenced,
            selectedRange: NSRange(location: "```\n- [ ]".utf16.count, length: 0)
        )
        try check(fencedEdit == nil, "Tasks should not toggle inside fenced code")
    }

    static func markdownInlineFormattingWrapsSelectedText() throws {
        try checkInlineFormatting(kind: .bold, markerOpen: "**", markerClose: "**")
        try checkInlineFormatting(kind: .italic, markerOpen: "_", markerClose: "_")
        try checkInlineFormatting(kind: .underline, markerOpen: "<u>", markerClose: "</u>")
        try checkInlineFormatting(kind: .strikethrough, markerOpen: "~~", markerClose: "~~")
        try checkInlineFormatting(kind: .inlineCode, markerOpen: "`", markerClose: "`")
    }

    static func markdownInlineFormattingLeavesCollapsedSelectionToTypingMarks() throws {
        let text = "One two"
        let edit = MarkdownInlineFormatting.formattingEdit(
            kind: .underline,
            in: text,
            selectedRange: NSRange(location: 3, length: 0)
        )

        try check(edit == nil, "Collapsed formatting should be handled as pending typing marks, not empty marker insertion")
    }

    static func markdownInlineFormattingLinksSelectedTextWithClipboardURL() throws {
        let text = "Read docs today"
        let edit = try require(MarkdownInlineFormatting.linkEdit(
            in: text,
            selectedRange: NSRange(location: 5, length: 4),
            urlString: " https://example.com/docs "
        ))

        try check(edit.range == NSRange(location: 5, length: 4), "Link edit should replace only selected text")
        try check(edit.replacement == "[docs](https://example.com/docs)", "Link edit should use the trimmed URL")
        try check(edit.selectedRangeAfterEdit == NSRange(location: 37, length: 0), "Cursor should land after the inserted link")

        let invalidURL = MarkdownInlineFormatting.linkEdit(
            in: text,
            selectedRange: NSRange(location: 5, length: 4),
            urlString: "not a url"
        )
        try check(invalidURL == nil, "Invalid clipboard URL should not produce a link edit")

        let emptySelection = MarkdownInlineFormatting.linkEdit(
            in: text,
            selectedRange: NSRange(location: 5, length: 0),
            urlString: "https://example.com/docs"
        )
        try check(emptySelection == nil, "Link shortcut should require selected text")

        try check(
            MarkdownInlineFormatting.validLinkURLString(from: "mailto:hello@example.com") == "mailto:hello@example.com",
            "Mailto links should be accepted"
        )
    }

    static func markdownInlineFormattingUsesModifierSetSemantics() throws {
        let bold = try require(MarkdownInlineFormatting.formattingEdit(
            kind: .bold,
            in: "Format me",
            selectedRange: NSRange(location: 7, length: 2)
        ))
        try check(bold.range == NSRange(location: 0, length: 9), "Formatting should rewrite the affected line")
        try check(bold.replacement == "Format **me**", "Bold should wrap selected text once")
        try check(bold.selectedRangeAfterEdit == NSRange(location: 9, length: 2), "Selection should stay on visible bold text")

        let unbold = try require(MarkdownInlineFormatting.formattingEdit(
            kind: .bold,
            in: bold.replacement,
            selectedRange: bold.selectedRangeAfterEdit
        ))
        try check(unbold.replacement == "Format me", "Applying bold again should remove bold instead of adding markers")
        try check(unbold.selectedRangeAfterEdit == NSRange(location: 7, length: 2), "Unbold should keep the visible text selected")

        let collapsedBold = try require(MarkdownInlineFormatting.formattingEdit(
            kind: .bold,
            in: "3. ****item****",
            selectedRange: NSRange(location: 7, length: 4)
        ))
        try check(collapsedBold.replacement == "3. item", "Repeated same-kind markers should collapse when toggled")

        let underlineBold = try require(MarkdownInlineFormatting.formattingEdit(
            kind: .underline,
            in: "**me**",
            selectedRange: NSRange(location: 2, length: 2)
        ))
        try check(underlineBold.replacement == "**<u>me</u>**", "Different modifiers should be additive")

        let removeBoldOnly = try require(MarkdownInlineFormatting.formattingEdit(
            kind: .bold,
            in: "**<u>me</u>**",
            selectedRange: NSRange(location: 5, length: 2)
        ))
        try check(removeBoldOnly.replacement == "<u>me</u>", "Removing bold should preserve underline")

        let codeClearsMarks = try require(MarkdownInlineFormatting.formattingEdit(
            kind: .inlineCode,
            in: "**<u>me</u>**",
            selectedRange: NSRange(location: 5, length: 2)
        ))
        try check(codeClearsMarks.replacement == "`me`", "Inline code should replace text marks")

        let textMarkInsideCode = MarkdownInlineFormatting.formattingEdit(
            kind: .bold,
            in: "`me`",
            selectedRange: NSRange(location: 1, length: 2)
        )
        try check(textMarkInsideCode == nil, "Text marks should not apply inside inline code")
    }

    static func markdownInlineFormattingExcludesStructuralListPrefixes() throws {
        let ordered = "3. item"
        let normalized = MarkdownSelectionNormalization.normalizedVisibleSelection(
            in: ordered,
            selectedRange: NSRange(location: 0, length: ordered.utf16.count)
        )
        try check(normalized == NSRange(location: 3, length: 4), "Single-line selection should exclude ordered-list prefix")

        let orderedBold = try require(MarkdownInlineFormatting.formattingEdit(
            kind: .bold,
            in: ordered,
            selectedRange: NSRange(location: 0, length: ordered.utf16.count)
        ))
        try check(orderedBold.replacement == "3. **item**", "Formatting should preserve ordered-list prefix outside markers")
        try check(orderedBold.selectedRangeAfterEdit == NSRange(location: 5, length: 4), "Selection should stay on list item text")

        let task = "- [ ] item"
        let taskBold = try require(MarkdownInlineFormatting.formattingEdit(
            kind: .bold,
            in: task,
            selectedRange: NSRange(location: 0, length: task.utf16.count)
        ))
        try check(taskBold.replacement == "- [ ] **item**", "Formatting should preserve task-list prefix outside markers")

        let multiline = "1. one\n2. two"
        let multilineBold = try require(MarkdownInlineFormatting.formattingEdit(
            kind: .bold,
            in: multiline,
            selectedRange: NSRange(location: 0, length: multiline.utf16.count)
        ))
        try check(multilineBold.replacement == "1. **one**\n2. **two**", "Multiline formatting should preserve each list prefix outside markers")
    }

    static func markdownInlineFormattingExcludesStructuralHeadingPrefixes() throws {
        let heading = "## Heading"
        let boldHeading = try require(MarkdownInlineFormatting.formattingEdit(
            kind: .bold,
            in: heading,
            selectedRange: NSRange(location: 0, length: heading.utf16.count)
        ))
        try check(boldHeading.replacement == "## **Heading**", "Formatting should preserve heading prefix outside markers")
        try check(boldHeading.selectedRangeAfterEdit == NSRange(location: 5, length: 7), "Selection should stay on heading text")
    }

    static func markdownInlineFormattingPreservesComposedCharacters() throws {
        let text = "Hi 👨‍👩‍👧‍👦 cafe\u{301}"
        let nsText = text as NSString
        let emojiRange = nsText.range(of: "👨‍👩‍👧‍👦")
        let accentRange = nsText.range(of: "e\u{301}")

        let emojiBold = try require(MarkdownInlineFormatting.formattingEdit(
            kind: .bold,
            in: text,
            selectedRange: emojiRange
        ))
        try check(emojiBold.replacement == "Hi **👨‍👩‍👧‍👦** cafe\u{301}", "Formatting should preserve multi-scalar emoji")
        try check(emojiBold.selectedRangeAfterEdit == NSRange(location: emojiRange.location + 2, length: emojiRange.length), "Emoji selection should keep the composed character selected")

        let accentItalic = try require(MarkdownInlineFormatting.formattingEdit(
            kind: .italic,
            in: text,
            selectedRange: accentRange
        ))
        try check(accentItalic.replacement == "Hi 👨‍👩‍👧‍👦 caf_e\u{301}_", "Formatting should preserve composed accented characters")
        try check(accentItalic.selectedRangeAfterEdit == NSRange(location: accentRange.location + 1, length: accentRange.length), "Accent selection should keep the composed character selected")
    }

    static func markdownInlineRenderingFindsHiddenSyntaxRanges() throws {
        let text = "A **bold** and <u>under</u> and [site](https://example.com)"
        let spans = MarkdownInlineRendering.spans(in: text)

        let bold = try require(spans.first { $0.kind == .bold }, "Expected bold span")
        try check((text as NSString).substring(with: bold.contentRange) == "bold", "Bold content range should exclude markers")
        try check(bold.syntaxRanges == [
            NSRange(location: 2, length: 2),
            NSRange(location: 8, length: 2)
        ], "Bold syntax ranges should track both marker pairs")

        let underline = try require(spans.first { $0.kind == .underline }, "Expected underline span")
        try check((text as NSString).substring(with: underline.contentRange) == "under", "Underline content should exclude tags")

        let link = try require(spans.first { $0.kind == .link }, "Expected link span")
        try check((text as NSString).substring(with: link.contentRange) == "site", "Link content should be visible text only")
        try check(link.syntaxRanges.count == 2, "Link should hide the opening bracket and destination syntax")

        let nestedText = "**_important_**"
        let nestedSpans = MarkdownInlineRendering.spans(in: nestedText)
        let nestedBold = try require(nestedSpans.first { $0.kind == .bold }, "Expected nested bold span")
        let nestedItalic = try require(nestedSpans.first { $0.kind == .italic }, "Expected nested italic span")
        try check((nestedText as NSString).substring(with: nestedBold.contentRange) == "_important_", "Outer nested span should preserve its content range")
        try check((nestedText as NSString).substring(with: nestedItalic.contentRange) == "important", "Inner nested span should be parsed instead of rejected")
    }

    static func checkContinuation(_ text: String, replacement: String) throws {
        let edit = try require(MarkdownListEditing.continuationEdit(
            in: text,
            selectedRange: NSRange(location: text.utf16.count, length: 0)
        ))
        try check(edit.range == NSRange(location: text.utf16.count, length: 0), "Continuation should insert at cursor")
        try check(edit.replacement == replacement, "Unexpected continuation replacement: \(edit.replacement)")
    }

    static func checkInlineFormatting(
        kind: MarkdownInlineFormatting.Kind,
        markerOpen: String,
        markerClose: String
    ) throws {
        let text = "Format me"
        let edit = try require(MarkdownInlineFormatting.formattingEdit(
            kind: kind,
            in: text,
            selectedRange: NSRange(location: 7, length: 2)
        ))

        try check(edit.range == NSRange(location: 0, length: text.utf16.count), "Inline formatting should rewrite the affected line")
        try check(edit.replacement == "Format \(markerOpen)me\(markerClose)", "Unexpected inline formatting replacement")
        try check(
            edit.selectedRangeAfterEdit == NSRange(location: 7 + markerOpen.utf16.count, length: 2),
            "Inline formatting should keep the original content selected inside the markers"
        )
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

    static func markdownHeadingSelectionKeepsCollapsedCaretsForLiveMode() throws {
        try check(
            MarkdownSelectionNormalization.normalizedVisibleSelection(
                in: "## Heading",
                selectedRange: NSRange(location: 0, length: 0)
            ) == NSRange(location: 0, length: 0),
            "Live mode should keep collapsed carets inside revealed heading markers"
        )
        try check(
            MarkdownSelectionNormalization.normalizedVisibleSelection(
                in: "## Heading",
                selectedRange: NSRange(location: 2, length: 0)
            ) == NSRange(location: 2, length: 0),
            "Live mode should keep collapsed carets inside heading whitespace"
        )
        try check(
            MarkdownSelectionNormalization.normalizedVisibleSelection(
                in: "## Heading",
                selectedRange: NSRange(location: 3, length: 0)
            ) == NSRange(location: 3, length: 0),
            "Carets already at visible heading text should stay put"
        )
    }

    static func markdownRenderedContentIgnoresEmptyStructuralMarkers() throws {
        try check(MarkdownBlockRendering.hasRenderedContent(in: "#"), "A bare heading marker should count as rendered text")
        try check(!MarkdownBlockRendering.hasRenderedContent(in: "## "), "An empty H2 block should not count as rendered content")
        try check(MarkdownBlockRendering.hasRenderedContent(in: "- [ ]"), "An incomplete task marker should count as rendered text")
        try check(MarkdownBlockRendering.hasRenderedContent(in: "## Title"), "Heading text should count as rendered content")
        try check(MarkdownBlockRendering.hasRenderedContent(in: "---"), "A rendered horizontal rule should count as content")
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

        let visibleStartEdit = try require(MarkdownBlockEditing.headingBackspaceEdit(
            in: "## Title",
            selectedRange: NSRange(location: 0, length: 0)
        ))
        try check(visibleStartEdit.range == NSRange(location: 0, length: 3), "Backspace at visible heading start should remove the hidden prefix")

        let midContentEdit = MarkdownBlockEditing.headingBackspaceEdit(
            in: "## Title",
            selectedRange: NSRange(location: 5, length: 0)
        )
        try check(midContentEdit == nil, "Backspace inside heading content should keep normal character deletion")
    }

    static func markdownHorizontalRuleRenderingTracksShortcuts() throws {
        let rule = try require(MarkdownBlockRendering.horizontalRuleLine(in: "---", at: 3))
        try check(rule.markerRange == NSRange(location: 0, length: 3), "A standalone --- should parse as a horizontal rule marker")

        let spacedRule = try require(MarkdownBlockRendering.horizontalRuleLine(in: "  * * *  ", at: 5))
        try check(spacedRule.markerRange == NSRange(location: 0, length: 9), "Spaced rule markers should be included in the hidden range")

        let fenced = "```\n---\n```"
        let fencedRule = MarkdownBlockRendering.horizontalRuleLine(in: fenced, at: 5)
        try check(fencedRule == nil, "Horizontal rules should not render inside fenced code")
    }

    static func markdownHorizontalRuleDisplayStateTracksCommittedLines() throws {
        let editing = try require(MarkdownBlockRendering.horizontalRuleDisplayState(in: "---", at: 3))
        switch editing {
        case .editingMarker(let rule):
            try check(rule.markerRange == NSRange(location: 0, length: 3), "EOF --- should stay an editable marker until Return")
        case .committedDivider:
            throw CheckFailure("EOF --- should not be committed before Return")
        }

        let committed = try require(MarkdownBlockRendering.horizontalRuleDisplayState(in: "---\n", at: 3))
        switch committed {
        case .committedDivider(let rule):
            try check(rule.lineRange == NSRange(location: 0, length: 4), "Return should commit --- into a divider line")
        case .editingMarker:
            throw CheckFailure("--- followed by a newline should be a committed divider")
        }

        let typingAfterCommitted = try require(MarkdownBlockRendering.horizontalRuleDisplayState(in: "---\nA", at: 0))
        switch typingAfterCommitted {
        case .committedDivider(let rule):
            try check(rule.lineRange == NSRange(location: 0, length: 4), "Typing after Return should keep the original divider line committed")
        case .editingMarker:
            throw CheckFailure("Typing after a committed divider should not make the divider editable again")
        }
    }

    static func markdownHorizontalRuleBackspaceExitsBlock() throws {
        let edit = try require(MarkdownBlockEditing.horizontalRuleBackspaceEdit(
            in: "Before\n---\nAfter",
            selectedRange: NSRange(location: "Before\n---".utf16.count, length: 0)
        ))

        try check(edit.range == NSRange(location: "Before\n".utf16.count, length: 3), "Backspace on a rule should remove the marker text")
        try check(edit.replacement == "", "Rule backspace should leave an empty line")
        try check(edit.selectedRangeAfterEdit == NSRange(location: "Before\n".utf16.count, length: 0), "Cursor should return to the rule line start")

        let committedStartEdit = try require(MarkdownBlockEditing.horizontalRuleBackspaceEdit(
            in: "---\n",
            selectedRange: NSRange(location: 0, length: 0)
        ))
        try check(committedStartEdit.range == NSRange(location: 0, length: 3), "Backspace at committed rule start should remove the hidden marker")

        let uncommittedEndEdit = MarkdownBlockEditing.horizontalRuleBackspaceEdit(
            in: "---",
            selectedRange: NSRange(location: 3, length: 0)
        )
        try check(uncommittedEndEdit == nil, "Backspace at visible EOF --- should fall through to normal character deletion")
    }

    static func markdownInlineBackspaceHandlesHiddenMarkers() throws {
        let unwrap = try require(MarkdownInlineFormatting.backspaceEdit(
            in: "**Bold**",
            selectedRange: NSRange(location: 2, length: 0)
        ))
        try check(unwrap.range == NSRange(location: 0, length: 8), "Backspace at visible content start should unwrap formatting")
        try check(unwrap.replacement == "Bold", "Unwrapping should preserve visible content")

        let trailingDelete = try require(MarkdownInlineFormatting.backspaceEdit(
            in: "**Bold**",
            selectedRange: NSRange(location: 8, length: 0)
        ))
        try check(trailingDelete.range == NSRange(location: 5, length: 1), "Backspace after hidden closing marker should delete the previous visible character")
        try check(trailingDelete.replacement == "", "Trailing hidden marker backspace should delete one visible character")

        let emptyWrapper = try require(MarkdownInlineFormatting.backspaceEdit(
            in: "<u></u>",
            selectedRange: NSRange(location: 3, length: 0)
        ))
        try check(emptyWrapper.range == NSRange(location: 0, length: 7), "Backspace inside an empty wrapper should remove both tags")
        try check(emptyWrapper.replacement == "", "Empty wrapper deletion should leave no text")
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

        let todayPath = root.appendingPathComponent("streams/daily/2026/04/2026-04-29.md")
        let yesterdayPath = root.appendingPathComponent("streams/daily/2026/04/2026-04-28.md")
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
        let store = try storeWithDefaultStreamCreatedAt(april29, root: root, calendar: calendar)
        let controller = TimelineController(
            store: store,
            cache: DayCache(calendar: calendar),
            recentDayCount: 2,
            now: april29
        )
        controller.bootstrapIfNeeded(now: april29)

        controller.handleDayRollover(now: april30)

        try check(controller.today == calendar.startOfDay(for: april30), "Today did not roll forward")
        try check(controller.days.map(\.id).first == "2026-04-30", "New today is not at the top")
        try check(controller.days.map(\.id).contains("2026-04-29"), "Rollover should keep post-creation history visible")
        try check(
            FileManager.default.fileExists(atPath: root.appendingPathComponent("streams/daily/2026/04/2026-04-30.md").path),
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

    static func configurationStore(rootConfig: String) throws -> CurrentConfigurationStore {
        let root = try temporaryDirectory()
        let home = root.appendingPathComponent("home", isDirectory: true)
        let xdgRoot = root.appendingPathComponent("xdg", isDirectory: true)
        let appSupport = root.appendingPathComponent("app-support/com.raj.current", isDirectory: true)
        let locations = CurrentConfigurationLocations(
            environment: ["XDG_CONFIG_HOME": xdgRoot.path],
            homeDirectory: home,
            applicationSupportDirectory: appSupport
        )

        try writeText(rootConfig, to: locations.primaryEditableURL)
        return CurrentConfigurationStore(locations: locations, homeDirectory: home)
    }

    static func writeText(_ text: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    static func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("CurrentChecks-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func temporaryRoot() throws -> URL {
        try temporaryDirectory().appendingPathComponent("current", isDirectory: true)
    }

    static func storeWithDefaultStreamCreatedAt(_ createdAt: Date, root: URL, calendar: Calendar) throws -> StreamStore {
        let store = StreamStore(libraryRoot: root, calendar: calendar)
        var stream = try store.defaultStream()
        stream.createdAt = createdAt
        let metadataURL = stream.rootURL.appendingPathComponent(".current-stream.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(stream).write(to: metadataURL, options: [.atomic])
        return store
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
