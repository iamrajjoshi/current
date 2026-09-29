import Combine
import CoreGraphics
import Foundation

public struct TimelineNotice: Identifiable, Equatable {
    public enum Kind: Equatable {
        case info
        case saveError
        case conflict
    }

    public let id = UUID()
    public var kind: Kind
    public var title: String
    public var message: String
}

public struct TimelineScrollRequest: Equatable, Identifiable {
    public enum Target: Equatable {
        case today(String)
        case searchMatch(String)
    }

    public let id: UUID
    public var target: Target
    public var offset: CGFloat? = nil
    public var selectionRange: NSRange? = nil
    public var readingAnchor: MarkdownReadingAnchor? = nil
    public var shouldFocusEditor = true

    public var dayID: String {
        switch target {
        case .today(let dayID), .searchMatch(let dayID):
            return dayID
        }
    }

    public static func today(_ dayID: String) -> TimelineScrollRequest {
        TimelineScrollRequest(id: UUID(), target: .today(dayID))
    }

    public static func searchMatch(_ dayID: String) -> TimelineScrollRequest {
        TimelineScrollRequest(id: UUID(), target: .searchMatch(dayID))
    }
}

public struct TimelineWindowState: Equatable {
    public private(set) var dates: [Date] = []
    public private(set) var topSpacerHeight: CGFloat = 0
    public private(set) var bottomSpacerHeight: CGFloat = 0
    // Keep the heights that actually created each spacer. Re-measuring after a
    // width, focus or source change can otherwise consume it before all days return.
    private var omittedHeights: [Date: CGFloat] = [:]
    public var retainedDayCount: Int
    public var batchSize: Int

    public init(
        dates: [Date] = [],
        topSpacerHeight: CGFloat = 0,
        bottomSpacerHeight: CGFloat = 0,
        retainedDayCount: Int = 180,
        batchSize: Int = 14
    ) {
        self.dates = dates
        self.topSpacerHeight = max(0, topSpacerHeight)
        self.bottomSpacerHeight = max(0, bottomSpacerHeight)
        self.retainedDayCount = max(1, retainedDayCount)
        self.batchSize = max(1, batchSize)
    }

    mutating func reset(to dates: [Date]) {
        self.dates = dates
        topSpacerHeight = 0
        bottomSpacerHeight = 0
        omittedHeights.removeAll()
    }

    mutating func replaceDatesPreservingSpacers(_ dates: [Date]) {
        self.dates = dates
    }

    mutating func clearTopSpacer() {
        topSpacerHeight = 0
    }

    mutating func clearBottomSpacer() {
        bottomSpacerHeight = 0
    }

    mutating func mergeDates(_ additions: [Date], anchor: Date?, heightForDate: (Date) -> CGFloat) {
        let merged = Array(Set(dates + additions)).sorted(by: >)
        guard merged.count > retainedDayCount else { dates = merged; return }
        let anchorIndex = anchor.flatMap { merged.firstIndex(of: $0) } ?? 0
        let start = max(0, min(anchorIndex - retainedDayCount / 2, merged.count - retainedDayCount))
        let end = start + retainedDayCount
        for date in merged[..<start] {
            let height = max(1, heightForDate(date))
            omittedHeights[date] = height
            topSpacerHeight += height
        }
        for date in merged[end...] {
            let height = max(1, heightForDate(date))
            omittedHeights[date] = height
            bottomSpacerHeight += height
        }
        dates = Array(merged[start..<end])
    }

    @discardableResult
    mutating func appendOlderDates(
        _ olderDates: [Date],
        heightForDate: (Date) -> CGFloat
    ) -> TimelineWindowMutation {
        let uniqueDates = olderDates.filter { !dates.contains($0) }
        guard !uniqueDates.isEmpty else {
            return TimelineWindowMutation()
        }

        dates.append(contentsOf: uniqueDates)

        if bottomSpacerHeight > 0 {
            let restoredHeight = uniqueDates.reduce(CGFloat(0)) {
                $0 + (omittedHeights.removeValue(forKey: $1) ?? max(1, heightForDate($1)))
            }
            bottomSpacerHeight = max(0, bottomSpacerHeight - restoredHeight)
        }

        var trimmedDates: [Date] = []
        if dates.count > retainedDayCount {
            let overflow = dates.count - retainedDayCount
            trimmedDates = Array(dates.prefix(overflow))
            for date in trimmedDates {
                let height = max(1, heightForDate(date))
                omittedHeights[date] = height
                topSpacerHeight += height
            }
            dates.removeFirst(overflow)
        }

        return TimelineWindowMutation(addedDates: uniqueDates, trimmedDates: trimmedDates)
    }

    @discardableResult
    mutating func prependNewerDates(
        _ newerDates: [Date],
        heightForDate: (Date) -> CGFloat
    ) -> TimelineWindowMutation {
        let uniqueDates = newerDates.filter { !dates.contains($0) }
        guard !uniqueDates.isEmpty else {
            return TimelineWindowMutation()
        }

        dates.insert(contentsOf: uniqueDates, at: 0)

        let restoredHeight = uniqueDates.reduce(CGFloat(0)) {
            $0 + (omittedHeights.removeValue(forKey: $1) ?? max(1, heightForDate($1)))
        }
        topSpacerHeight = max(0, topSpacerHeight - restoredHeight)

        var trimmedDates: [Date] = []
        if dates.count > retainedDayCount {
            let overflow = dates.count - retainedDayCount
            trimmedDates = Array(dates.suffix(overflow))
            for date in trimmedDates {
                let height = max(1, heightForDate(date))
                omittedHeights[date] = height
                bottomSpacerHeight += height
            }
            dates.removeLast(overflow)
        }

        return TimelineWindowMutation(addedDates: uniqueDates, trimmedDates: trimmedDates)
    }
}

struct TimelineWindowMutation: Equatable {
    var addedDates: [Date] = []
    var trimmedDates: [Date] = []
}

@MainActor
public final class TimelineController: ObservableObject {
    @Published public private(set) var stream: Stream?
    @Published public private(set) var streams: [Stream] = []
    @Published public private(set) var folders: [StreamFolder] = []
    @Published public private(set) var openStreamIDs: [UUID] = []
    @Published public private(set) var searchResults: [LibrarySearchResult] = []
    @Published public private(set) var isSearching = false
    @Published public private(set) var conflicts: [DocumentConflict] = []
    @Published public private(set) var days: [DayDocument] = []
    @Published public private(set) var libraryContentRevision = 0
    @Published public private(set) var today: Date
    @Published public private(set) var isBootstrapped = false
    @Published public private(set) var scrollRequest: TimelineScrollRequest?
    @Published public private(set) var activeDate: Date?
    @Published public private(set) var canLoadOlderDays = true
    @Published public private(set) var topSpacerHeight: CGFloat = 0
    @Published public private(set) var bottomSpacerHeight: CGFloat = 0
    @Published public private(set) var minimizedDayIDs: Set<String> = []
    @Published public var searchQuery = ""
    @Published public var notice: TimelineNotice?

    public private(set) var store: StreamStore
    public var cache: DayCache
    public var recentDayCount: Int
    public var historyBatchSize: Int
    public var historyWindowDayCount: Int
    public var estimatedCollapsedDayHeight: CGFloat
    public var autosaveDelay: TimeInterval

    private var windowState: TimelineWindowState
    private var pendingSaves: [DocumentID: DispatchWorkItem] = [:]
    private let calendar: Calendar
    private let fallbackLibraryRoot: URL
    private var configuration: CurrentConfiguration = .default
    private var session = LibrarySession()
    private var streamWindows: [UUID: TimelineWindowState] = [:]
    private var searchTask: Task<Void, Never>?
    private var searchGeneration = UUID()
    private var pendingSessionSave: DispatchWorkItem?
    private var pendingRecovery: [DocumentID: DispatchWorkItem] = [:]
    private let recoveryQueue = DispatchQueue(label: "com.raj.current.recovery", qos: .utility)
    private var fileWatcher: LibraryFileWatcher?

    public init(
        store: StreamStore = StreamStore(),
        cache: DayCache = DayCache(),
        recentDayCount: Int = 7,
        historyBatchSize: Int = 14,
        historyWindowDayCount: Int = 180,
        estimatedCollapsedDayHeight: CGFloat = TimelineRowHeightCalculator.collapsedEmptyDayHeight,
        autosaveDelay: TimeInterval = 0.55,
        now: Date = Date()
    ) {
        self.store = store
        self.cache = cache
        self.cache.calendar = store.calendar
        self.recentDayCount = recentDayCount
        self.historyBatchSize = historyBatchSize
        self.historyWindowDayCount = historyWindowDayCount
        self.estimatedCollapsedDayHeight = estimatedCollapsedDayHeight
        self.autosaveDelay = autosaveDelay
        self.calendar = store.calendar
        self.fallbackLibraryRoot = store.libraryRoot.standardizedFileURL
        self.today = store.calendar.startOfDay(for: now)
        self.windowState = TimelineWindowState(
            retainedDayCount: historyWindowDayCount,
            batchSize: historyBatchSize
        )
    }

    public func bootstrapIfNeeded(now: Date = Date()) {
        guard !isBootstrapped else {
            handleDayRollover(now: now)
            restoreCurrentViewPosition()
            return
        }

        do {
            let library = try store.loadLibrary()
            streams = library.streams
            folders = library.folders
            session = store.loadSession()
            for document in store.recoveredDocuments(in: streams) { cache.insert(document) }
            let available = streams.filter { !$0.isArchived }
            openStreamIDs = session.openStreamIDs.filter { id in streams.contains { $0.id == id } }
            today = calendar.startOfDay(for: now)
            isBootstrapped = true
            if let selected = streams.first(where: { $0.id == session.selectedStreamID }) ?? available.first ?? streams.first {
                let saved = session.views[selected.id]
                selectStream(selected.id, focusEditor: saved == nil || saved?.editorHadFocus == true)
            }
            startWatchingLibrary()
        } catch {
            notice = TimelineNotice(
                kind: .saveError,
                title: "Current could not open the library",
                message: error.localizedDescription
            )
        }
    }

    public func apply(configuration: CurrentConfiguration) {
        let wasBootstrapped = isBootstrapped
        self.configuration = configuration
        let libraryRootChanged = applyLibraryRoot(configuration.libraryRoot)
        recentDayCount = max(1, configuration.recentDays)
        historyBatchSize = max(1, configuration.historyBatchDays)
        historyWindowDayCount = max(1, configuration.historyWindowDays)
        autosaveDelay = max(0, configuration.autosaveDelay)
        syncWindowConfiguration()
        if libraryRootChanged, wasBootstrapped {
            bootstrapIfNeeded(now: today)
        } else if isBootstrapped {
            publishDays()
        }
    }

    @discardableResult
    public func loadOlderWindow() -> Bool {
        syncWindowConfiguration()
        guard let stream else { return false }
        guard let oldest = windowState.dates.last else { return false }

        let olderDates = nextOlderDates(before: oldest, in: stream)
        guard !olderDates.isEmpty else {
            canLoadOlderDays = false
            windowState.clearBottomSpacer()
            publishDays()
            return false
        }

        windowState.appendOlderDates(olderDates) { [weak self] date in
            self?.spacerHeight(for: date) ?? self?.estimatedCollapsedDayHeight ?? TimelineRowHeightCalculator.collapsedEmptyDayHeight
        }
        publishDays()
        canLoadOlderDays = hasOlderDates(before: windowState.dates.last, in: stream)
        return true
    }

    @discardableResult
    public func loadNewerWindow() -> Bool {
        syncWindowConfiguration()
        guard let stream else { return false }
        guard let newest = windowState.dates.first else { return false }

        let newerDates = nextNewerDates(after: newest, in: stream)
        guard !newerDates.isEmpty else {
            windowState.clearTopSpacer()
            publishDays()
            return false
        }

        windowState.prependNewerDates(newerDates) { [weak self] date in
            self?.spacerHeight(for: date) ?? self?.estimatedCollapsedDayHeight ?? TimelineRowHeightCalculator.collapsedEmptyDayHeight
        }
        publishDays()
        canLoadOlderDays = hasOlderDates(before: windowState.dates.last, in: stream)
        return true
    }

    @discardableResult
    public func loadOlderDays(measuredHeightForDayID: (String) -> CGFloat? = { _ in nil }) -> Bool {
        loadOlderWindow()
    }

    public func updateText(for date: Date, text: String) {
        guard let stream else { return }
        updateText(for: documentID(for: date, in: stream), text: text)
    }

    public func updateText(for date: Date, streamID: UUID, libraryID: String? = nil, text: String) {
        let id = DocumentID(libraryID: libraryID ?? store.libraryID, streamID: streamID,
                            dayKey: DayFormatting.dayKey(for: date, calendar: calendar))
        updateText(for: id, text: text)
    }

    public func updateText(for id: DocumentID, text: String) {
        guard id.libraryID == store.libraryID,
              let document = cache.updateText(for: id, text: text) else { return }
        scheduleRecovery(document)
        if document.streamID == stream?.id, activeDate != document.date {
            activeDate = document.date
        }
        publishDays()
        scheduleAutosave(for: document.documentID)
    }

    public func setActiveDate(_ date: Date) {
        let key = calendar.startOfDay(for: date)
        // A direct interaction with a day ends passive sidebar navigation.
        if scrollRequest?.shouldFocusEditor == false { scrollRequest?.shouldFocusEditor = true }
        guard activeDate != key else { return }
        activeDate = key
    }

    public func isDayMinimized(_ date: Date) -> Bool {
        let key = calendar.startOfDay(for: date)
        guard !calendar.isDate(key, inSameDayAs: today) else { return false }
        return minimizedDayIDs.contains(dayID(for: key))
    }

    public func toggleDayMinimized(_ date: Date) {
        let key = calendar.startOfDay(for: date)
        guard !calendar.isDate(key, inSameDayAs: today),
              let document = cache[key],
              !document.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        let dayID = dayID(for: key)
        var nextMinimizedDayIDs = minimizedDayIDs
        if nextMinimizedDayIDs.contains(dayID) {
            nextMinimizedDayIDs.remove(dayID)
            minimizedDayIDs = nextMinimizedDayIDs
        } else {
            nextMinimizedDayIDs.insert(dayID)
            minimizedDayIDs = nextMinimizedDayIDs
            if activeDate == key {
                activeDate = nil
            }
        }
        rememberCurrentView()
    }

    public var activeDocument: DayDocument? {
        cache[activeDate ?? today] ?? cache[today]
    }

    public var activeDayID: String? {
        guard let activeDate else { return nil }
        let dayID = dayID(for: activeDate)
        guard !minimizedDayIDs.contains(dayID) else { return nil }
        return dayID
    }

    public func save(_ date: Date) {
        guard let document = cache[date] else { return }
        saveDocument(document.documentID)
    }

    private func saveDocument(_ id: DocumentID) {
        pendingSaves[id]?.cancel()
        pendingSaves.removeValue(forKey: id)
        guard let document = cache[id] else { return }
        pendingRecovery.removeValue(forKey: id)?.cancel()
        recoveryQueue.sync {}
        guard document.isDirty else { store.removeRecovery(for: document); return }
        do {
            try store.writeRecovery(document)
            let saved = try store.saveDay(document)
            cache.replace(saved)
            conflicts.removeAll { $0.document.documentID == id }
            publishDays()
        } catch StreamStoreError.diskChanged(let url, let diskText) {
            if recordConflict(document, diskText: diskText) { notice = TimelineNotice(
                kind: .conflict,
                title: "External edit detected",
                message: "\(url.lastPathComponent) changed on disk. Current kept your in-app edits open instead of overwriting the file. Disk version: \(diskText.prefix(120))"
            ) }
        } catch {
            notice = TimelineNotice(
                kind: .saveError,
                title: "Could not save",
                message: error.localizedDescription
            )
        }
    }

    public func flushSaves() {
        NotificationCenter.default.post(name: .captureCurrentWorkspacePosition, object: nil)
        for work in pendingRecovery.values { work.cancel() }
        pendingRecovery.removeAll()
        recoveryQueue.sync {}
        for workItem in pendingSaves.values {
            workItem.cancel()
        }
        pendingSaves.removeAll()
        for document in cache.documents.values {
            saveDocument(document.documentID)
        }
        rememberCurrentView()
        persistSession()
    }

    public func refreshExternalChanges() {
        store.invalidateDayIndex()
        var changed = false
        for document in cache.documents.values {
            do {
                let reloaded = try store.reloadExternalChangesIfNeeded(document)
                if reloaded != document {
                    cache.replace(reloaded)
                    changed = true
                }
            } catch StreamStoreError.diskChanged(let url, let diskText) {
                if recordConflict(document, diskText: diskText) { notice = TimelineNotice(
                    kind: .conflict,
                    title: "External edit detected",
                    message: "\(url.lastPathComponent) changed on disk while this day has unsaved edits."
                ) }
            } catch {
                notice = TimelineNotice(
                    kind: .saveError,
                    title: "Could not refresh files",
                    message: error.localizedDescription
                )
            }
        }
        refreshLibrary()
        if let stream {
            changed = refreshHistoryMembership(in: stream) || changed
            canLoadOlderDays = hasOlderDates(before: windowState.dates.last, in: stream)
        }
        if changed { publishDays() }
        libraryContentRevision &+= 1
    }

    public func handleDayRollover(now: Date = Date()) {
        guard stream != nil, isBootstrapped else { return }
        let newToday = calendar.startOfDay(for: now)
        guard newToday != today else { return }
        today = newToday
        // Reading and editing stay on their original day across midnight or a
        // clock change. Only an explicit Today action moves the workspace.
        publishDays()
    }

    public func jumpToToday() {
        syncWindowConfiguration()
        activeDate = today
        if let stream {
            windowState.reset(to: recentDates(endingAt: today, in: stream))
            canLoadOlderDays = hasOlderDates(before: windowState.dates.last, in: stream)
        } else {
            windowState.reset(to: [])
            canLoadOlderDays = false
        }

        publishDays()
        scrollRequest = .today(dayID(for: today))
    }

    public func searchMatchCount() -> Int {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return 0 }
        return days.reduce(0) { count, document in
            count + document.text.localizedStandardContains(query).asInt
        }
    }

    public func firstSearchMatchID() -> String? {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return nil }
        return days.first { $0.text.localizedStandardContains(query) }?.id
    }

    public func scrollToFirstSearchMatch() {
        guard let id = firstSearchMatchID() else { return }
        scrollRequest = .searchMatch(id)
    }

    private func loadDocument(
        for date: Date,
        in stream: Stream,
        createToday: Bool
    ) -> DayDocument? {
        let id = documentID(for: date, in: stream)
        if let cached = cache[id] { return cached }
        do {
            let document = try store.loadDay(
                date,
                in: stream,
                createIfMissing: createToday && calendar.isDate(date, inSameDayAs: today)
            )
            cache.insert(document)
            return document
        } catch {
            notice = TimelineNotice(
                kind: .saveError,
                title: "Could not load history",
                message: error.localizedDescription
            )
            return nil
        }
    }

    private func nextOlderDates(before oldest: Date, in stream: Stream) -> [Date] {
        syncWindowConfiguration()
        var olderDates: [Date] = []
        let start = blankHistoryStartDate(for: stream)
        var cursor = calendar.addingDays(-1, to: oldest)

        while olderDates.count < windowState.batchSize, cursor >= start {
            if let document = loadDocument(for: cursor, in: stream, createToday: false),
               shouldDisplay(document: document, in: stream) {
                olderDates.append(document.date)
            }
            cursor = calendar.addingDays(-1, to: cursor)
        }

        if olderDates.count < windowState.batchSize {
            let cutoff = oldest <= start ? oldest : start
            olderDates.append(contentsOf: existingDates(before: cutoff, in: stream, limit: windowState.batchSize - olderDates.count))
        }

        return olderDates
    }

    private func nextNewerDates(after newest: Date, in stream: Stream) -> [Date] {
        syncWindowConfiguration()
        guard newest < today else { return [] }

        var newerDatesAscending: [Date] = []
        let start = blankHistoryStartDate(for: stream)
        if newest < start {
            // Imported history is sparse: skip years of nonexistent blank days.
            let imported = store.existingDayDates(in: stream, before: start, limit: .max)
                .reversed().lazy.filter { $0 > newest }.prefix(windowState.batchSize)
            newerDatesAscending = imported.compactMap {
                loadDocument(for: $0, in: stream, createToday: false)?.date
            }
        }
        var cursor = max(start, calendar.addingDays(1, to: newest))

        while cursor <= today, newerDatesAscending.count < windowState.batchSize {
            if let document = loadDocument(for: cursor, in: stream, createToday: true),
               shouldDisplay(document: document, in: stream) {
                newerDatesAscending.append(document.date)
            }
            cursor = calendar.addingDays(1, to: cursor)
        }

        return newerDatesAscending.reversed()
    }

    private func recentDates(endingAt newest: Date, in stream: Stream) -> [Date] {
        let count = max(1, recentDayCount)
        let start = blankHistoryStartDate(for: stream)
        var dates: [Date] = []
        var cursor = calendar.startOfDay(for: newest)

        while dates.count < count, cursor >= start {
            if let document = loadDocument(for: cursor, in: stream, createToday: true),
               shouldDisplay(document: document, in: stream) {
                dates.append(document.date)
            }
            cursor = calendar.addingDays(-1, to: cursor)
        }

        if dates.count < count {
            dates.append(contentsOf: existingDates(before: start, in: stream, limit: count - dates.count))
        }

        return dates
    }

    private func spacerHeight(for date: Date) -> CGFloat {
        guard let document = cache[date] else {
            return estimatedCollapsedDayHeight
        }
        return TimelineRowHeightCalculator.height(
            for: document,
            isToday: calendar.isDate(document.date, inSameDayAs: today),
            isActive: activeDate.map { calendar.isDate($0, inSameDayAs: document.date) } ?? false,
            isMinimized: isDayMinimized(document.date),
            width: CurrentTheme.contentMaxWidth(configuration: configuration),
            configuration: configuration
        )
    }

    private func syncWindowConfiguration() {
        windowState.retainedDayCount = max(1, historyWindowDayCount)
        windowState.batchSize = max(1, historyBatchSize)
    }

    @discardableResult
    private func applyLibraryRoot(_ libraryRoot: URL?) -> Bool {
        let desiredRoot = (libraryRoot ?? fallbackLibraryRoot).standardizedFileURL
        guard store.libraryRoot.standardizedFileURL.path != desiredRoot.path else { return false }

        flushSaves()
        guard cache.dirtyDocuments.isEmpty else { return false }

        fileWatcher?.stop()
        fileWatcher = nil
        store = StreamStore(libraryRoot: desiredRoot, calendar: calendar)
        searchTask?.cancel()
        searchGeneration = UUID()
        searchResults = []
        isSearching = false
        streams = []
        folders = []
        openStreamIDs = []
        conflicts = []
        session = LibrarySession()
        streamWindows = [:]
        cache = DayCache(maxCleanDocuments: cache.maxCleanDocuments, calendar: calendar)
        stream = nil
        days = []
        activeDate = nil
        minimizedDayIDs = []
        scrollRequest = nil
        canLoadOlderDays = true
        topSpacerHeight = 0
        bottomSpacerHeight = 0
        windowState.reset(to: [])
        isBootstrapped = false
        return true
    }

    private func publishDays() {
        syncWindowConfiguration()
        if let stream {
            let visibleDates = windowState.dates.filter { date in
                guard let document = cache[date] else { return false }
                return shouldDisplay(document: document, in: stream)
            }
            if visibleDates != windowState.dates {
                windowState.replaceDatesPreservingSpacers(visibleDates)
            }
        }
        topSpacerHeight = windowState.topSpacerHeight
        bottomSpacerHeight = windowState.bottomSpacerHeight

        let visibleSet = Set(windowState.dates + [activeDate].compactMap { $0 })
        _ = cache.evictCleanDocuments(keeping: visibleSet, today: today)
        days = windowState.dates.compactMap { cache[$0] }
    }

    private func blankHistoryStartDate(for stream: Stream) -> Date {
        min(calendar.startOfDay(for: stream.createdAt), today)
    }

    private func existingDates(before date: Date, in stream: Stream, limit: Int) -> [Date] {
        let visibleDates = Set(windowState.dates)
        return store.existingDayDates(in: stream, before: date, limit: max(limit + visibleDates.count, limit))
            .filter { !visibleDates.contains($0) }
            .prefix(limit)
            .compactMap { date in
                loadDocument(for: date, in: stream, createToday: false)?.date
            }
    }

    private func hasOlderDates(before date: Date?, in stream: Stream) -> Bool {
        guard let date else { return false }
        let start = blankHistoryStartDate(for: stream)
        var cursor = calendar.addingDays(-1, to: date)
        while cursor >= start {
            if !configuration.hideEmptyWeekends || !calendar.isDateInWeekend(cursor)
                || cache[cursor]?.isDirty == true || store.dayFileExists(for: cursor, in: stream) {
                return true
            }
            cursor = calendar.addingDays(-1, to: cursor)
        }
        return !store.existingDayDates(in: stream, before: min(date, start), limit: 1).isEmpty
    }

    private func shouldDisplay(document: DayDocument, in stream: Stream) -> Bool {
        if document.id == scrollRequest?.dayID { return true }
        if document.date == activeDate { return true }
        if calendar.isDate(document.date, inSameDayAs: today) {
            return true
        }

        if document.date < blankHistoryStartDate(for: stream) {
            return store.dayFileExists(for: document.date, in: stream)
        }

        if configuration.hideEmptyWeekends,
           calendar.isDateInWeekend(document.date),
           document.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           !document.isDirty {
            return false
        }

        return true
    }

    private func scheduleAutosave(for id: DocumentID) {
        pendingSaves[id]?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                self?.saveDocument(id)
            }
        }
        pendingSaves[id] = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + autosaveDelay, execute: workItem)
    }
}

extension TimelineController {
    public var hasUnsavedChanges: Bool { !cache.dirtyDocuments.isEmpty }
    public var currentViewState: StreamViewState {
        guard let id = stream?.id else { return StreamViewState() }
        return session.views[id] ?? StreamViewState()
    }

    @discardableResult
    public func flushAllSaves() -> Bool {
        flushSaves()
        return !hasUnsavedChanges
    }

    public func dayID(for date: Date) -> String {
        guard let stream else { return DayFormatting.dayKey(for: date, calendar: calendar) }
        return documentID(for: date, in: stream).rawValue
    }

    private func documentID(for date: Date, in stream: Stream) -> DocumentID {
        DocumentID(libraryID: store.libraryID, streamID: stream.id,
                   dayKey: DayFormatting.dayKey(for: date, calendar: calendar))
    }

    public func selectStream(_ id: UUID, openInTab: Bool = false, focusEditor: Bool = true) {
        guard let selected = streams.first(where: { $0.id == id }) else { return }
        if stream?.id == id {
            if !focusEditor, scrollRequest?.shouldFocusEditor == true { scrollRequest?.shouldFocusEditor = false }
            if openInTab, !openStreamIDs.contains(id) { openStreamIDs.append(id); persistSession() }
            return
        }
        NotificationCenter.default.post(name: .captureCurrentWorkspacePosition, object: nil)
        rememberCurrentView()
        if let oldID = stream?.id {
            for document in cache.dirtyDocuments where document.streamID == oldID { saveDocument(document.documentID) }
        }
        stream = selected
        cache.select(libraryID: store.libraryID, streamID: id)
        if openInTab, !openStreamIDs.contains(id) { openStreamIDs.append(id) }
        session.selectedStreamID = id
        let saved = session.views[id] ?? StreamViewState()
        minimizedDayIDs = Set(saved.minimizedDayKeys.compactMap { key in
            store.date(for: key).map { documentID(for: $0, in: selected).rawValue }
        })
        let savedActiveDate = saved.dayKey.flatMap(store.date(for:))
        activeDate = savedActiveDate ?? today
        let anchorDate = saved.scrollDayKey.flatMap(store.date(for:)) ?? savedActiveDate ?? today
        var request = TimelineScrollRequest.searchMatch(dayID(for: anchorDate))
        request.offset = CGFloat(saved.scrollOffset)
        request.readingAnchor = saved.readingAnchor
        request.selectionRange = NSRange(location: max(0, saved.selectionLocation), length: max(0, saved.selectionLength))
        request.shouldFocusEditor = focusEditor && (savedActiveDate == nil || savedActiveDate == anchorDate)
            && !saved.minimizedDayKeys.contains(DayFormatting.dayKey(for: anchorDate, calendar: calendar))
        scrollRequest = request
        let restoresExistingWindow = streamWindows[id] != nil
        if let savedWindow = streamWindows[id] {
            windowState = savedWindow
            for date in savedWindow.dates { _ = loadDocument(for: date, in: selected, createToday: true) }
            publishDays()
            canLoadOlderDays = hasOlderDates(before: windowState.dates.last, in: selected)
        } else if let key = saved.scrollDayKey ?? saved.dayKey, let date = store.date(for: key), date != today {
            jumpToDate(date)
        } else {
            jumpToToday()
        }
        // Pin a requested blank day before restoring a different editing day.
        scrollRequest = request
        minimizedDayIDs = Set(saved.minimizedDayKeys.compactMap { key in
            store.date(for: key).map { documentID(for: $0, in: selected).rawValue }
        })
        if let savedActiveDate {
            _ = loadDocument(for: savedActiveDate, in: selected, createToday: false)
            activeDate = savedActiveDate
            let isAdjacentToWindow = windowState.dates.first.map { savedActiveDate <= calendar.addingDays(1, to: $0) } == true
                && windowState.dates.last.map { savedActiveDate >= calendar.addingDays(-1, to: $0) } == true
            if !restoresExistingWindow, isAdjacentToWindow, !windowState.dates.contains(savedActiveDate),
               windowState.dates.count < historyWindowDayCount {
                windowState.replaceDatesPreservingSpacers((windowState.dates + [savedActiveDate]).sorted(by: >))
            }
            publishDays()
        }
        persistSession()
    }

    public func openStreamTab(_ id: UUID) {
        selectStream(id, openInTab: true)
    }

    /// A new window can reuse this controller after the old window closed.
    /// Its collection view needs the latest position, not the previous jump.
    public func restoreCurrentViewPosition() {
        guard stream != nil else { return }
        let saved = currentViewState
        let date = (saved.scrollDayKey ?? saved.dayKey).flatMap(store.date(for:)) ?? activeDate ?? today
        var request = TimelineScrollRequest.searchMatch(dayID(for: date))
        request.offset = CGFloat(saved.scrollOffset)
        request.readingAnchor = saved.readingAnchor
        request.selectionRange = NSRange(location: max(0, saved.selectionLocation), length: max(0, saved.selectionLength))
        request.shouldFocusEditor = saved.editorHadFocus == true && activeDate == date
        scrollRequest = request
    }

    /// Calendar dots include unsaved writing without creating day files or loading history.
    public func writtenDayKeys(inMonth month: Date) -> Set<String> {
        guard let stream else { return [] }
        var keys = store.writtenDayKeys(inMonth: month, in: stream)
        for document in cache.dirtyDocuments where document.streamID == stream.id
            && document.libraryID == store.libraryID
            && calendar.isDate(document.date, equalTo: month, toGranularity: .month) {
            if document.text.unicodeScalars.contains(where: { !CharacterSet.whitespacesAndNewlines.contains($0) }) {
                keys.insert(document.dayKey)
            } else {
                keys.remove(document.dayKey)
            }
        }
        return keys
    }

    public func updateViewState(_ view: StreamViewState) {
        guard let id = stream?.id else { return }
        updateViewState(view, streamID: id, libraryID: store.libraryID)
    }

    public func updateViewState(_ view: StreamViewState, streamID: UUID, libraryID: String) {
        guard libraryID == store.libraryID, streams.contains(where: { $0.id == streamID }) else { return }
        guard session.views[streamID] != view else { return }
        if stream?.id == streamID, session.views[streamID]?.scrollDayKey != view.scrollDayKey {
            objectWillChange.send()
        }
        session.views[streamID] = view
        pendingSessionSave?.cancel()
        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor in self?.persistSession() }
        }
        pendingSessionSave = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    public func jumpToDate(_ date: Date) {
        guard let stream else { return }
        let date = calendar.startOfDay(for: date)
        activeDate = date
        minimizedDayIDs.remove(dayID(for: date))
        guard loadDocument(for: date, in: stream, createToday: calendar.isDate(date, inSameDayAs: today)) != nil else { return }
        // A direct jump loads only its neighborhood, never the intervening calendar.
        windowState.reset(to: [date])
        let older = nextOlderDates(before: date, in: stream)
        windowState.reset(to: [date] + Array(older.prefix(max(0, recentDayCount - 1))))
        publishDays()
        canLoadOlderDays = hasOlderDates(before: windowState.dates.last, in: stream)
        scrollRequest = .searchMatch(dayID(for: date))
    }

    @discardableResult
    public func createStream(name: String, folderID: UUID? = nil) -> Stream? {
        do {
            let created = try store.createStream(name: name, folderID: folderID)
            refreshLibrary()
            selectStream(created.id)
            return created
        } catch { report(error, title: "Could not create stream"); return nil }
    }

    @discardableResult
    public func renameStream(_ id: UUID, name: String) -> Bool {
        guard let name = checkedName(name), streams.contains(where: { $0.id == id }) else { return false }
        return updateLibrary { streams, _ in
            guard let index = streams.firstIndex(where: { $0.id == id }) else { return }
            streams[index].name = name
        }
    }

    public func moveStream(_ id: UUID, to folderID: UUID?) {
        guard folderID == nil || folders.contains(where: { $0.id == folderID }) else { return }
        updateLibrary { streams, _ in
            guard let index = streams.firstIndex(where: { $0.id == id }) else { return }
            streams[index].folderID = folderID
        }
    }

    public func setStreamPinned(_ id: UUID, isPinned: Bool) {
        updateLibrary { streams, _ in
            guard let index = streams.firstIndex(where: { $0.id == id }) else { return }
            streams[index].isPinned = isPinned
        }
    }

    public func archiveStream(_ id: UUID) {
        for document in cache.dirtyDocuments where document.streamID == id { saveDocument(document.documentID) }
        guard !cache.dirtyDocuments.contains(where: { $0.streamID == id }) else { return }
        updateLibrary { streams, _ in
            guard let index = streams.firstIndex(where: { $0.id == id }) else { return }
            streams[index].isArchived = true
        }
        guard streams.first(where: { $0.id == id })?.isArchived == true else { return }
        openStreamIDs.removeAll { $0 == id }
        if stream?.id == id {
            rememberCurrentView()
            stream = nil
            days = []
            activeDate = nil
            if let next = streams.first(where: { !$0.isArchived }) { selectStream(next.id) }
        }
        persistSession()
    }

    public func restoreStream(_ id: UUID) {
        updateLibrary { streams, _ in
            guard let index = streams.firstIndex(where: { $0.id == id }) else { return }
            streams[index].isArchived = false
        }
        if stream == nil { selectStream(id) }
    }

    public func reorderStreams(_ ids: [UUID]) {
        updateLibrary { streams, _ in
            let ordered = ids + streams.map(\.id).filter { !ids.contains($0) }
            for index in streams.indices { streams[index].order = ordered.firstIndex(of: streams[index].id) ?? index }
            streams.sort { $0.order < $1.order }
        }
    }

    @discardableResult
    public func createFolder(name: String) -> StreamFolder? {
        guard let name = checkedName(name) else { return nil }
        let folder = StreamFolder(name: name, order: (folders.map(\.order).max() ?? -1) + 1)
        updateLibrary { _, folders in folders.append(folder) }
        return folders.first { $0.id == folder.id }
    }

    @discardableResult
    public func renameFolder(_ id: UUID, name: String) -> Bool {
        guard let name = checkedName(name), folders.contains(where: { $0.id == id }) else { return false }
        return updateLibrary { _, folders in
            guard let index = folders.firstIndex(where: { $0.id == id }) else { return }
            folders[index].name = name
        }
    }

    public func removeFolder(_ id: UUID) {
        updateLibrary { streams, folders in
            folders.removeAll { $0.id == id }
            for index in streams.indices where streams[index].folderID == id { streams[index].folderID = nil }
        }
    }

    public func closeStreamTab(_ id: UUID) {
        openStreamIDs.removeAll { $0 == id }
        if stream?.id == id, let next = openStreamIDs.last { selectStream(next) }
        persistSession()
    }

    public func reorderOpenStreams(_ ids: [UUID]) {
        guard Set(ids) == Set(openStreamIDs), ids.count == openStreamIDs.count else { return }
        openStreamIDs = ids
        persistSession()
    }

    public func searchHistory(_ query: String, inCurrentStream: Bool = false) {
        searchTask?.cancel()
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let generation = UUID()
        searchGeneration = generation
        guard !query.isEmpty else { searchResults = []; isSearching = false; return }
        let selected = inCurrentStream ? streams.filter { $0.id == stream?.id } : streams
        let root = store.libraryRoot
        let calendar = calendar
        let drafts = cache.dirtyDocuments
        searchResults = []
        isSearching = true
        searchTask = Task { [weak self] in
            let worker = Task.detached(priority: .userInitiated) {
                LibrarySearch.search(query: query, streams: selected, libraryRoot: root, calendar: calendar, overrides: drafts)
            }
            let results = await withTaskCancellationHandler(operation: { await worker.value }, onCancel: { worker.cancel() })
            guard !Task.isCancelled, let self, self.searchGeneration == generation else { return }
            self.searchResults = results
            self.isSearching = false
        }
    }

    public func openSearchResult(_ result: LibrarySearchResult) {
        guard result.documentID.libraryID == store.libraryID else { return }
        selectStream(result.streamID)
        jumpToDate(result.date)
        var request = TimelineScrollRequest.searchMatch(dayID(for: result.date))
        request.selectionRange = result.matchRange
        scrollRequest = request
    }

    public func reloadConflictFromDisk(_ id: String) {
        guard let conflict = conflicts.first(where: { $0.id == id }) else { return }
        do {
            var document = cache[conflict.document.documentID] ?? conflict.document
            let diskText = try currentDiskText(for: document)
            pendingSaves.removeValue(forKey: document.documentID)?.cancel()
            pendingRecovery.removeValue(forKey: document.documentID)?.cancel()
            recoveryQueue.sync {}
            document.text = diskText
            document.lastSavedText = diskText
            document.isDirty = false
            store.removeRecovery(for: document)
            document = try store.reloadExternalChangesIfNeeded(document)
            cache.replace(document)
            conflicts.removeAll { $0.id == id }
            publishDays()
        } catch { report(error, title: "Could not reload the disk version") }
    }

    public func keepBothConflictVersions(_ id: String) {
        guard let conflict = conflicts.first(where: { $0.id == id }) else { return }
        let document = cache[conflict.document.documentID] ?? conflict.document
        let original = document.fileURL
        let copy = original.deletingPathExtension().appendingPathExtension("conflict-\(UUID().uuidString.prefix(8)).md")
        do {
            try document.text.write(to: copy, atomically: true, encoding: .utf8)
            reloadConflictFromDisk(id)
            if !conflicts.contains(where: { $0.id == id }) {
                notice = TimelineNotice(kind: .info, title: "Both versions kept", message: "Your edits were saved to \(copy.lastPathComponent). The original file contains the disk version.")
            }
        } catch { report(error, title: "Could not save the conflict copy") }
    }

    @discardableResult
    private func recordConflict(_ document: DayDocument, diskText: String) -> Bool {
        let existing = conflicts.first(where: { $0.document.documentID == document.documentID })
        guard existing != DocumentConflict(document: document, diskText: diskText) else { return false }
        let isNewDiskVersion = existing?.diskText != diskText
        conflicts.removeAll { $0.document.documentID == document.documentID }
        conflicts.append(DocumentConflict(document: document, diskText: diskText))
        return isNewDiskVersion
    }

    private func refreshLibrary() {
        guard FileManager.default.fileExists(atPath: store.libraryRoot.path) else {
            report(StreamStoreError.invalidLibrary("The library folder is no longer available."), title: "Library unavailable")
            return
        }
        do {
            let library = try store.loadLibrary()
            if streams != library.streams { streams = library.streams }
            if folders != library.folders { folders = library.folders }
            if let id = stream?.id { stream = streams.first { $0.id == id } }
        } catch { report(error, title: "Could not refresh the library") }
    }

    private func refreshHistoryMembership(in stream: Stream) -> Bool {
        let previous = windowState.dates
        if windowState.topSpacerHeight == 0, previous.first == today, previous.count <= recentDayCount {
            var refreshed = recentDates(endingAt: today, in: stream)
            if let activeDate, previous.contains(activeDate), !refreshed.contains(activeDate) {
                refreshed.append(activeDate)
                refreshed.sort(by: >)
            }
            windowState.replaceDatesPreservingSpacers(refreshed)
        } else if let newest = previous.first, let oldest = previous.last {
            let known = Set(previous)
            let additions = store.existingDayDates(in: stream, before: calendar.addingDays(1, to: newest),
                limit: historyWindowDayCount + previous.count).filter { $0 >= oldest && !known.contains($0) }
            guard !additions.isEmpty else { return false }
            for date in additions { _ = loadDocument(for: date, in: stream, createToday: false) }
            let anchor = currentViewState.scrollDayKey.flatMap(store.date(for:))
            windowState.mergeDates(additions, anchor: anchor) { [weak self] in
                self?.spacerHeight(for: $0) ?? TimelineRowHeightCalculator.collapsedEmptyDayHeight
            }
        }
        return windowState.dates != previous
    }

    @discardableResult
    private func updateLibrary(_ change: (inout [Stream], inout [StreamFolder]) -> Void) -> Bool {
        var nextStreams = streams
        var nextFolders = folders
        change(&nextStreams, &nextFolders)
        do {
            try store.saveLibrary(streams: nextStreams, folders: nextFolders)
            streams = nextStreams
            folders = nextFolders
            if let id = stream?.id { stream = streams.first { $0.id == id } }
            return true
        } catch { report(error, title: "Could not save library changes"); return false }
    }

    private func checkedName(_ name: String) -> String? {
        let value = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { report(StreamStoreError.invalidName, title: "A name is required"); return nil }
        return value
    }

    private func rememberCurrentView() {
        guard let stream else { return }
        var view = session.views[stream.id] ?? StreamViewState()
        view.dayKey = activeDate.map { DayFormatting.dayKey(for: $0, calendar: calendar) }
        view.minimizedDayKeys = Set(minimizedDayIDs.compactMap { $0.split(separator: "|").last.map(String.init) })
        session.views[stream.id] = view
        streamWindows[stream.id] = windowState
    }

    private func persistSession() {
        pendingSessionSave?.cancel()
        pendingSessionSave = nil
        session.selectedStreamID = stream?.id
        session.openStreamIDs = openStreamIDs
        do { try store.saveSession(session) }
        catch { report(error, title: "Could not save workspace position") }
    }

    private func report(_ error: Error, title: String) {
        notice = TimelineNotice(kind: .saveError, title: title, message: error.localizedDescription)
    }

    private func currentDiskText(for document: DayDocument) throws -> String {
        guard FileManager.default.fileExists(atPath: document.fileURL.path) else { return "" }
        return try String(contentsOf: document.fileURL, encoding: .utf8)
    }

    private func scheduleRecovery(_ document: DayDocument) {
        let id = document.documentID
        pendingRecovery[id]?.cancel()
        let root = store.libraryRoot
        let calendar = calendar
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pendingRecovery.removeValue(forKey: id)
            self.recoveryQueue.async { [weak self] in
                do { try StreamStore(libraryRoot: root, calendar: calendar).writeRecovery(document) }
                catch {
                    let message = error.localizedDescription
                    Task { @MainActor [weak self] in
                        guard let self, self.store.libraryID == id.libraryID, self.cache[id]?.isDirty == true else { return }
                        self.notice = TimelineNotice(kind: .saveError, title: "Could not protect unsaved edits", message: message)
                    }
                }
            }
        }
        pendingRecovery[id] = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }

    private func startWatchingLibrary() {
        fileWatcher?.stop()
        let libraryID = store.libraryID
        fileWatcher = LibraryFileWatcher(root: store.libraryRoot) { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.store.libraryID == libraryID else { return }
                self.refreshExternalChanges()
            }
        }
    }
}

private extension Bool {
    var asInt: Int { self ? 1 : 0 }
}
