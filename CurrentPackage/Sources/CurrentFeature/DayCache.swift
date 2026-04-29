import Foundation

public struct DayCache {
    public private(set) var documents: [Date: DayDocument] = [:]
    public var maxCleanDocuments: Int
    public var calendar: Calendar

    public init(maxCleanDocuments: Int = 45, calendar: Calendar = .current) {
        self.maxCleanDocuments = maxCleanDocuments
        self.calendar = calendar
    }

    public subscript(date: Date) -> DayDocument? {
        documents[calendar.startOfDay(for: date)]
    }

    public var sortedDocuments: [DayDocument] {
        documents.values.sorted { $0.date < $1.date }
    }

    public var dirtyDocuments: [DayDocument] {
        documents.values.filter(\.isDirty).sorted { $0.date < $1.date }
    }

    public mutating func insert(_ document: DayDocument) {
        documents[calendar.startOfDay(for: document.date)] = document
    }

    public mutating func updateText(for date: Date, text: String) -> DayDocument? {
        let key = calendar.startOfDay(for: date)
        guard var document = documents[key] else { return nil }
        document.text = text
        document.isDirty = text != document.lastSavedText
        document.lastLoadedAt = Date()
        documents[key] = document
        return document
    }

    public mutating func replace(_ document: DayDocument) {
        documents[calendar.startOfDay(for: document.date)] = document
    }

    @discardableResult
    public mutating func evictCleanDocuments(keeping datesToKeep: Set<Date>, today: Date) -> [Date] {
        let normalizedKeep = Set(datesToKeep.map { calendar.startOfDay(for: $0) })
        let todayKey = calendar.startOfDay(for: today)

        let cleanCandidates = documents.values
            .filter { !$0.isDirty }
            .filter { !normalizedKeep.contains($0.date) }
            .filter { $0.date != todayKey }
            .sorted { $0.lastLoadedAt < $1.lastLoadedAt }

        let cleanCount = documents.values.filter { !$0.isDirty }.count
        let overflow = max(0, cleanCount - maxCleanDocuments)
        guard overflow > 0 else { return [] }

        let evicted = cleanCandidates.prefix(overflow).map(\.date)
        for date in evicted {
            documents.removeValue(forKey: date)
        }
        return Array(evicted)
    }
}
