import Foundation

public struct DayCache {
    public private(set) var documents: [DocumentID: DayDocument] = [:]
    public var maxCleanDocuments: Int
    public var calendar: Calendar
    private var selectedLibraryID: String?
    private var selectedStreamID: UUID?

    public init(maxCleanDocuments: Int = 45, calendar: Calendar = .current) {
        self.maxCleanDocuments = maxCleanDocuments
        self.calendar = calendar
    }

    public mutating func select(libraryID: String, streamID: UUID) {
        selectedLibraryID = libraryID
        selectedStreamID = streamID
    }

    public subscript(id: DocumentID) -> DayDocument? { documents[id] }

    public subscript(date: Date) -> DayDocument? {
        guard let selectedLibraryID, let selectedStreamID else { return nil }
        let key = DayFormatting.dayKey(for: date, calendar: calendar)
        return documents[DocumentID(libraryID: selectedLibraryID, streamID: selectedStreamID, dayKey: key)]
    }

    public var sortedDocuments: [DayDocument] {
        documents.values.sorted { $0.date < $1.date }
    }

    public var dirtyDocuments: [DayDocument] {
        documents.values.filter(\.isDirty).sorted { $0.date < $1.date }
    }

    public mutating func insert(_ document: DayDocument) {
        if selectedStreamID == nil { select(libraryID: document.libraryID, streamID: document.streamID) }
        // Paging must not replace an unsaved buffer with its older disk contents.
        guard documents[document.documentID]?.isDirty != true else { return }
        documents[document.documentID] = document
    }

    public mutating func updateText(for date: Date, text: String) -> DayDocument? {
        guard let document = self[date] else { return nil }
        return updateText(for: document.documentID, text: text)
    }

    public mutating func updateText(for id: DocumentID, text: String) -> DayDocument? {
        guard var document = documents[id] else { return nil }
        document.text = text
        document.isDirty = text != document.lastSavedText
        document.lastLoadedAt = Date()
        documents[document.documentID] = document
        return document
    }

    public mutating func replace(_ document: DayDocument) {
        documents[document.documentID] = document
    }

    @discardableResult
    public mutating func evictCleanDocuments(keeping datesToKeep: Set<Date>, today: Date) -> [Date] {
        let normalizedKeep = Set(datesToKeep.map { DayFormatting.dayKey(for: $0, calendar: calendar) })
        let todayKey = DayFormatting.dayKey(for: today, calendar: calendar)

        let cleanCandidates = documents.values
            .filter { !$0.isDirty }
            .filter { document in
                let isSelected = document.libraryID == selectedLibraryID && document.streamID == selectedStreamID
                return !(isSelected && (normalizedKeep.contains(document.dayKey) || document.dayKey == todayKey))
            }
            .sorted { $0.lastLoadedAt < $1.lastLoadedAt }

        let cleanCount = documents.values.filter { !$0.isDirty }.count
        let overflow = max(0, cleanCount - maxCleanDocuments)
        guard overflow > 0 else { return [] }

        let evicted = Array(cleanCandidates.prefix(overflow))
        for document in evicted {
            documents.removeValue(forKey: document.documentID)
        }
        return evicted.map(\.date)
    }
}
