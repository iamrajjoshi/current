import Combine
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

@MainActor
public final class TimelineController: ObservableObject {
    @Published public private(set) var stream: Stream?
    @Published public private(set) var days: [DayDocument] = []
    @Published public private(set) var today: Date
    @Published public private(set) var isBootstrapped = false
    @Published public private(set) var scrollTargetID: String?
    @Published public private(set) var activeDate: Date?
    @Published public private(set) var canLoadOlderDays = true
    @Published public var searchQuery = ""
    @Published public var notice: TimelineNotice?

    public let store: StreamStore
    public var cache: DayCache
    public var recentDayCount: Int
    public var historyBatchSize: Int
    public var blankHistoryDayLimit: Int
    public var autosaveDelay: TimeInterval

    private var visibleDates: [Date] = []
    private var pendingSaves: [Date: DispatchWorkItem] = [:]
    private let calendar: Calendar

    public init(
        store: StreamStore = StreamStore(),
        cache: DayCache = DayCache(),
        recentDayCount: Int = 7,
        historyBatchSize: Int = 7,
        blankHistoryDayLimit: Int = 45,
        autosaveDelay: TimeInterval = 0.55,
        now: Date = Date()
    ) {
        self.store = store
        self.cache = cache
        self.recentDayCount = recentDayCount
        self.historyBatchSize = historyBatchSize
        self.blankHistoryDayLimit = blankHistoryDayLimit
        self.autosaveDelay = autosaveDelay
        self.calendar = store.calendar
        self.today = store.calendar.startOfDay(for: now)
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
            visibleDates = (0..<recentDayCount)
                .map { calendar.addingDays(-$0, to: today) }
            canLoadOlderDays = true
            try loadVisibleDates(createToday: true)
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

    public func loadOlderDays() {
        guard let stream else { return }
        guard let oldest = visibleDates.last else { return }

        let olderDates = nextOlderDates(before: oldest, in: stream)
        guard !olderDates.isEmpty else {
            canLoadOlderDays = false
            return
        }

        for date in olderDates where !visibleDates.contains(date) {
            visibleDates.append(date)
            do {
                cache.insert(try store.loadDay(date, in: stream))
            } catch {
                notice = TimelineNotice(
                    kind: .saveError,
                    title: "Could not load history",
                    message: error.localizedDescription
                )
            }
        }

        canLoadOlderDays = olderDates.count == historyBatchSize
        publishDays()
    }

    private func nextOlderDates(before oldest: Date, in stream: Stream) -> [Date] {
        guard historyBatchSize > 0 else { return [] }

        let blankFloor = calendar.addingDays(-(max(1, blankHistoryDayLimit) - 1), to: today)
        var olderDates: [Date] = []
        var cursor = calendar.addingDays(-1, to: oldest)

        while olderDates.count < historyBatchSize, cursor >= blankFloor {
            if !visibleDates.contains(cursor) {
                olderDates.append(cursor)
            }
            cursor = calendar.addingDays(-1, to: cursor)
        }

        let remaining = historyBatchSize - olderDates.count
        guard remaining > 0 else { return olderDates }

        let actualFileCutoff = olderDates.last ?? oldest
        let actualFileDates = store.existingDayDates(in: stream, before: actualFileCutoff, limit: remaining)
            .filter { !visibleDates.contains($0) && !olderDates.contains($0) }
        olderDates.append(contentsOf: actualFileDates)
        return olderDates
    }

    public func updateText(for date: Date, text: String) {
        let key = calendar.startOfDay(for: date)
        guard cache.updateText(for: key, text: text) != nil else { return }
        activeDate = key
        publishDays()
        scheduleAutosave(for: key)
    }

    public func setActiveDate(_ date: Date) {
        activeDate = calendar.startOfDay(for: date)
    }

    public var activeDocument: DayDocument? {
        cache[activeDate ?? today] ?? cache[today]
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
        guard let stream, isBootstrapped else { return }
        let newToday = calendar.startOfDay(for: now)
        guard newToday > today else { return }

        var cursor = calendar.addingDays(1, to: today)
        while cursor <= newToday {
            if !visibleDates.contains(cursor) {
                visibleDates.insert(cursor, at: 0)
            }
            do {
                cache.insert(try store.loadDay(cursor, in: stream, createIfMissing: cursor == newToday))
            } catch {
                notice = TimelineNotice(
                    kind: .saveError,
                    title: "Could not create today",
                    message: error.localizedDescription
                )
            }
            cursor = calendar.addingDays(1, to: cursor)
        }

        today = newToday
        publishDays()
        jumpToToday()
    }

    public func jumpToToday() {
        if !visibleDates.contains(today) {
            visibleDates.insert(today, at: 0)
            do {
                if let stream {
                    cache.insert(try store.loadDay(today, in: stream, createIfMissing: true))
                }
            } catch {
                notice = TimelineNotice(
                    kind: .saveError,
                    title: "Could not load today",
                    message: error.localizedDescription
                )
            }
            publishDays()
        }
        scrollTargetID = DayFormatting.dayKey(for: today, calendar: calendar)
    }

    public func copyCurrentDayMarkdown() -> String {
        cache[today]?.text ?? ""
    }

    public func copyVisibleStreamMarkdown() -> String {
        days.map { document in
            "# \(DayFormatting.visibleTitle(for: document.date))\n\n\(document.text)"
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        .joined(separator: "\n\n")
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
        scrollTargetID = firstSearchMatchID()
    }

    private func loadVisibleDates(createToday: Bool) throws {
        guard let stream else { return }
        for date in visibleDates {
            cache.insert(try store.loadDay(date, in: stream, createIfMissing: createToday && date == today))
        }
        publishDays()
    }

    private func publishDays() {
        let visibleSet = Set(visibleDates)
        _ = cache.evictCleanDocuments(keeping: visibleSet, today: today)
        days = visibleDates.compactMap { cache[$0] }
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
