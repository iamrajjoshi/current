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
    }

    mutating func replaceDatesPreservingSpacers(_ dates: [Date]) {
        self.dates = dates
    }

    mutating func clearTopSpacer() {
        topSpacerHeight = 0
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

        let restoredHeight = uniqueDates.reduce(CGFloat(0)) { $0 + max(1, heightForDate($1)) }
        if bottomSpacerHeight > 0 {
            bottomSpacerHeight = max(0, bottomSpacerHeight - restoredHeight)
        }

        var trimmedDates: [Date] = []
        if dates.count > retainedDayCount {
            let overflow = dates.count - retainedDayCount
            trimmedDates = Array(dates.prefix(overflow))
            topSpacerHeight += trimmedDates.reduce(CGFloat(0)) { $0 + max(1, heightForDate($1)) }
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

        let restoredHeight = uniqueDates.reduce(CGFloat(0)) { $0 + max(1, heightForDate($1)) }
        topSpacerHeight = max(0, topSpacerHeight - restoredHeight)

        var trimmedDates: [Date] = []
        if dates.count > retainedDayCount {
            let overflow = dates.count - retainedDayCount
            trimmedDates = Array(dates.suffix(overflow))
            bottomSpacerHeight += trimmedDates.reduce(CGFloat(0)) { $0 + max(1, heightForDate($1)) }
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
    @Published public private(set) var days: [DayDocument] = []
    @Published public private(set) var today: Date
    @Published public private(set) var isBootstrapped = false
    @Published public private(set) var scrollRequest: TimelineScrollRequest?
    @Published public private(set) var activeDate: Date?
    @Published public private(set) var canLoadOlderDays = true
    @Published public private(set) var topSpacerHeight: CGFloat = 0
    @Published public private(set) var bottomSpacerHeight: CGFloat = 0
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
    private var pendingSaves: [Date: DispatchWorkItem] = [:]
    private let calendar: Calendar
    private let fallbackLibraryRoot: URL
    private var configuration: CurrentConfiguration = .default

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
            return
        }

        do {
            let stream = try store.defaultStream()
            self.stream = stream
            today = calendar.startOfDay(for: now)
            isBootstrapped = true
            jumpToToday()
        } catch {
            notice = TimelineNotice(
                kind: .saveError,
                title: "Current could not open Daily",
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
        guard topSpacerHeight > 0 || windowState.topSpacerHeight > 0 else { return false }
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
        return true
    }

    @discardableResult
    public func loadOlderDays(measuredHeightForDayID: (String) -> CGFloat? = { _ in nil }) -> Bool {
        loadOlderWindow()
    }

    public func updateText(for date: Date, text: String) {
        let key = calendar.startOfDay(for: date)
        guard cache.updateText(for: key, text: text) != nil else { return }
        if activeDate != key {
            activeDate = key
        }
        publishDays()
        scheduleAutosave(for: key)
    }

    public func setActiveDate(_ date: Date) {
        let key = calendar.startOfDay(for: date)
        guard activeDate != key else { return }
        activeDate = key
    }

    public var activeDocument: DayDocument? {
        cache[activeDate ?? today] ?? cache[today]
    }

    public var activeDayID: String? {
        activeDate.map { DayFormatting.dayKey(for: $0, calendar: calendar) }
    }

    public func save(_ date: Date) {
        let key = calendar.startOfDay(for: date)
        pendingSaves[key]?.cancel()
        pendingSaves.removeValue(forKey: key)

        guard let document = cache[key], document.isDirty else { return }
        do {
            let saved = try store.saveDay(document)
            cache.replace(saved)
            publishDays()
        } catch StreamStoreError.diskChanged(let url, let diskText) {
            notice = TimelineNotice(
                kind: .conflict,
                title: "External edit detected",
                message: "\(url.lastPathComponent) changed on disk. Current kept your in-app edits open instead of overwriting the file. Disk version: \(diskText.prefix(120))"
            )
        } catch {
            notice = TimelineNotice(
                kind: .saveError,
                title: "Could not save",
                message: error.localizedDescription
            )
        }
    }

    public func flushSaves() {
        for workItem in pendingSaves.values {
            workItem.cancel()
        }
        pendingSaves.removeAll()
        for document in cache.dirtyDocuments {
            save(document.date)
        }
    }

    public func refreshExternalChanges() {
        var changed = false
        for document in days {
            do {
                let reloaded = try store.reloadExternalChangesIfNeeded(document)
                if reloaded != document {
                    cache.replace(reloaded)
                    changed = true
                }
            } catch StreamStoreError.diskChanged(let url, _) {
                notice = TimelineNotice(
                    kind: .conflict,
                    title: "External edit detected",
                    message: "\(url.lastPathComponent) changed on disk while this day has unsaved edits."
                )
            } catch {
                notice = TimelineNotice(
                    kind: .saveError,
                    title: "Could not refresh files",
                    message: error.localizedDescription
                )
            }
        }
        if changed { publishDays() }
    }

    public func handleDayRollover(now: Date = Date()) {
        guard stream != nil, isBootstrapped else { return }
        let newToday = calendar.startOfDay(for: now)
        guard newToday > today else { return }
        today = newToday
        jumpToToday()
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
        scrollRequest = .today(DayFormatting.dayKey(for: today, calendar: calendar))
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
        var cursor = calendar.addingDays(1, to: newest)

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
        guard store.libraryRoot.standardizedFileURL != desiredRoot else { return false }

        flushSaves()
        guard cache.dirtyDocuments.isEmpty else { return false }

        store = StreamStore(libraryRoot: desiredRoot, calendar: calendar)
        cache = DayCache(maxCleanDocuments: cache.maxCleanDocuments, calendar: calendar)
        stream = nil
        days = []
        activeDate = nil
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

        let visibleSet = Set(windowState.dates)
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
        return !nextOlderDates(before: date, in: stream).isEmpty
    }

    private func shouldDisplay(document: DayDocument, in stream: Stream) -> Bool {
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

    private func scheduleAutosave(for date: Date) {
        pendingSaves[date]?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                self?.save(date)
            }
        }
        pendingSaves[date] = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + autosaveDelay, execute: workItem)
    }
}

private extension Bool {
    var asInt: Int { self ? 1 : 0 }
}
