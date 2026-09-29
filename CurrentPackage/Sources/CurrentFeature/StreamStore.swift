import Foundation

public final class StreamStore {
    public static let defaultStreamName = "Daily"
    public static let defaultStreamSlug = "daily"

    public let libraryRoot: URL
    public var calendar: Calendar
    let fileManager: FileManager
    let metadataFilename = ".current-stream.json"
    private var dayDateIndex: [UUID: [Date]] = [:]
    private struct WrittenDayCacheEntry {
        var modificationDate: Date?
        var size: Int?
        var hasContent: Bool
    }
    private var writtenDayCache: [URL: WrittenDayCacheEntry] = [:]
    public let libraryID: String

    public init(
        libraryRoot: URL = StreamStore.defaultLibraryRoot(),
        calendar: Calendar = .current,
        fileManager: FileManager = .default
    ) {
        self.libraryRoot = libraryRoot.standardizedFileURL
        self.libraryID = libraryRoot.standardizedFileURL.resolvingSymlinksInPath().path
        self.calendar = calendar
        self.fileManager = fileManager
    }

    public static func defaultLibraryRoot() -> URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        return (documents ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Documents", isDirectory: true))
            .appendingPathComponent("current", isDirectory: true)
    }

    public func defaultStream() throws -> Stream {
        let library = try loadLibrary()
        guard let stream = library.streams.first(where: { $0.slug == Self.defaultStreamSlug }) ?? library.streams.first else {
            throw StreamStoreError.invalidLibrary("No stream could be opened.")
        }
        return stream
    }

    public func dayURL(for date: Date, in stream: Stream) -> URL {
        let normalized = calendar.startOfDay(for: date)
        return stream.rootURL
            .appendingPathComponent(DayFormatting.yearFolder(for: normalized, calendar: calendar), isDirectory: true)
            .appendingPathComponent(DayFormatting.monthFolder(for: normalized, calendar: calendar), isDirectory: true)
            .appendingPathComponent("\(DayFormatting.dayKey(for: normalized, calendar: calendar)).md")
    }

    public func dayFileExists(for date: Date, in stream: Stream) -> Bool {
        fileManager.fileExists(atPath: dayURL(for: date, in: stream).path)
    }

    public func existingDayDates(
        in stream: Stream,
        before date: Date,
        limit: Int
    ) -> [Date] {
        guard limit > 0 else { return [] }
        let cutoff = calendar.startOfDay(for: date)
        if let indexed = dayDateIndex[stream.id] {
            return Array(indexed.lazy.filter { $0 < cutoff }.prefix(limit))
        }
        guard let enumerator = fileManager.enumerator(
                at: stream.rootURL,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
              ) else { return [] }

        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"

        var dates: Set<Date> = []
        for case let fileURL as URL in enumerator {
            guard fileURL.pathExtension == "md",
                  let resourceValues = try? fileURL.resourceValues(forKeys: [.isRegularFileKey]),
                  resourceValues.isRegularFile == true,
                  let parsedDate = formatter.date(from: fileURL.deletingPathExtension().lastPathComponent) else {
                continue
            }

            let normalized = calendar.startOfDay(for: parsedDate)
            dates.insert(normalized)
        }

        let recoveryRoot = libraryRoot.appendingPathComponent(".current-recovery/\(stream.id.uuidString)")
        for url in (try? fileManager.contentsOfDirectory(at: recoveryRoot, includingPropertiesForKeys: nil)) ?? [] {
            if let recoveredDate = self.date(for: url.deletingPathExtension().lastPathComponent) {
                dates.insert(recoveredDate)
            }
        }

        let indexed = dates.sorted(by: >)
        dayDateIndex[stream.id] = indexed
        return Array(indexed.lazy.filter { $0 < cutoff }.prefix(limit))
    }

    public func invalidateDayIndex() {
        dayDateIndex.removeAll()
        writtenDayCache.removeAll()
    }

    /// Inspect only this month's canonical Markdown files. Unchanged files reuse
    /// their content result; no blank documents are materialized for the calendar.
    public func writtenDayKeys(inMonth month: Date, in stream: Stream) -> Set<String> {
        let directory = dayURL(for: month, in: stream).deletingLastPathComponent()
        let properties: Set<URLResourceKey> = [.isRegularFileKey, .contentModificationDateKey, .fileSizeKey]
        guard let files = try? fileManager.contentsOfDirectory(at: directory,
                includingPropertiesForKeys: Array(properties), options: [.skipsHiddenFiles]) else { return [] }
        var result: Set<String> = []
        for url in files {
            let key = url.deletingPathExtension().lastPathComponent
            guard url.pathExtension == "md", let date = date(for: key),
                  calendar.isDate(date, equalTo: month, toGranularity: .month),
                  url.standardizedFileURL == dayURL(for: date, in: stream).standardizedFileURL,
                  let values = try? url.resourceValues(forKeys: properties), values.isRegularFile == true else { continue }
            let hasContent: Bool
            if let cached = writtenDayCache[url], cached.modificationDate == values.contentModificationDate,
               cached.size == values.fileSize {
                hasContent = cached.hasContent
            } else {
                let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
                hasContent = text.unicodeScalars.contains { !CharacterSet.whitespacesAndNewlines.contains($0) }
                writtenDayCache[url] = WrittenDayCacheEntry(modificationDate: values.contentModificationDate,
                                                          size: values.fileSize, hasContent: hasContent)
            }
            if hasContent { result.insert(key) }
        }
        return result
    }

    public func loadDay(
        _ date: Date,
        in stream: Stream,
        createIfMissing: Bool = false
    ) throws -> DayDocument {
        let normalized = calendar.startOfDay(for: date)
        let fileURL = dayURL(for: normalized, in: stream)

        if !fileManager.fileExists(atPath: fileURL.path) {
            if createIfMissing {
                try createDirectoryIfNeeded(fileURL.deletingLastPathComponent())
                do {
                    try Data().write(to: fileURL, options: [.atomic])
                    dayDateIndex.removeValue(forKey: stream.id)
                } catch {
                    throw StreamStoreError.unableToWrite(fileURL, error.localizedDescription)
                }
            } else {
                return recover(DayDocument(streamID: stream.id, date: normalized, fileURL: fileURL, text: "",
                                           libraryID: libraryID, dayKey: DayFormatting.dayKey(for: normalized, calendar: calendar)))
            }
        }

        let text: String
        do {
            let data = try Data(contentsOf: fileURL)
            guard let decoded = String(data: data, encoding: .utf8) else { throw StreamStoreError.unableToRead(fileURL) }
            text = decoded
        } catch {
            throw StreamStoreError.unableToRead(fileURL)
        }

        return recover(DayDocument(
            streamID: stream.id,
            date: normalized,
            fileURL: fileURL,
            text: text,
            lastLoadedAt: Date(),
            lastKnownModificationDate: modificationDate(for: fileURL),
            libraryID: libraryID,
            dayKey: DayFormatting.dayKey(for: normalized, calendar: calendar)
        ))
    }

    @discardableResult
    public func saveDay(_ document: DayDocument) throws -> DayDocument {
        try validateDocumentLocation(document)
        try createDirectoryIfNeeded(document.fileURL.deletingLastPathComponent())

        if fileManager.fileExists(atPath: document.fileURL.path) {
            guard let diskText = try? String(contentsOf: document.fileURL, encoding: .utf8) else {
                throw StreamStoreError.unableToRead(document.fileURL)
            }
            if document.isDirty, diskText != document.lastSavedText {
                throw StreamStoreError.diskChanged(document.fileURL, diskText: diskText)
            }
        } else if document.isDirty, document.lastKnownModificationDate != nil {
            throw StreamStoreError.diskChanged(document.fileURL, diskText: "")
        }

        do {
            try document.text.write(to: document.fileURL, atomically: true, encoding: .utf8)
        } catch {
            throw StreamStoreError.unableToWrite(document.fileURL, error.localizedDescription)
        }

        var saved = document
        saved.lastSavedText = document.text
        saved.isDirty = false
        saved.lastLoadedAt = Date()
        saved.lastKnownModificationDate = modificationDate(for: document.fileURL)
        dayDateIndex.removeValue(forKey: document.streamID)
        writtenDayCache.removeValue(forKey: document.fileURL)
        removeRecovery(for: document)
        return saved
    }

    public func reloadExternalChangesIfNeeded(_ document: DayDocument) throws -> DayDocument {
        guard fileManager.fileExists(atPath: document.fileURL.path) else {
            guard document.lastKnownModificationDate != nil else { return document }
            if document.isDirty { throw StreamStoreError.diskChanged(document.fileURL, diskText: "") }
            var removed = document
            removed.text = ""
            removed.lastSavedText = ""
            removed.lastKnownModificationDate = nil
            return removed
        }

        let currentModificationDate = modificationDate(for: document.fileURL)
        guard currentModificationDate != document.lastKnownModificationDate else {
            return document
        }

        guard let diskText = try? String(contentsOf: document.fileURL, encoding: .utf8) else {
            throw StreamStoreError.unableToRead(document.fileURL)
        }
        if document.isDirty, diskText != document.lastSavedText {
            throw StreamStoreError.diskChanged(document.fileURL, diskText: diskText)
        }

        var reloaded = document
        reloaded.text = diskText
        reloaded.lastSavedText = diskText
        reloaded.isDirty = false
        reloaded.lastLoadedAt = Date()
        reloaded.lastKnownModificationDate = currentModificationDate
        return reloaded
    }

    func createDirectoryIfNeeded(_ url: URL) throws {
        guard !fileManager.fileExists(atPath: url.path) else { return }
        do {
            try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        } catch {
            throw StreamStoreError.unableToCreateLibrary(error.localizedDescription)
        }
    }

    private func modificationDate(for url: URL) -> Date? {
        (try? fileManager.attributesOfItem(atPath: url.path)[.modificationDate]) as? Date
    }

    var metadataDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    var metadataEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    func validateDocumentLocation(_ document: DayDocument) throws {
        guard document.fileURL.standardizedFileURL.resolvingSymlinksInPath().path.hasPrefix(libraryID + "/") else {
            throw StreamStoreError.unableToWrite(document.fileURL, "This document belongs to another library.")
        }
    }

    public func writeRecovery(_ document: DayDocument) throws {
        try validateDocumentLocation(document)
        guard document.isDirty else { removeRecovery(for: document); return }
        let url = recoveryURL(for: document)
        try createDirectoryIfNeeded(url.deletingLastPathComponent())
        try metadataEncoder.encode(document).write(to: url, options: .atomic)
    }

    func removeRecovery(for document: DayDocument) {
        try? fileManager.removeItem(at: recoveryURL(for: document))
    }

    func recoveredDocuments(in streams: [Stream]) -> [DayDocument] {
        streams.flatMap { stream in
            let root = libraryRoot.appendingPathComponent(".current-recovery/\(stream.id.uuidString)")
            return ((try? fileManager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []).compactMap { url -> DayDocument? in
                guard url.pathExtension == "json", let date = self.date(for: url.deletingPathExtension().lastPathComponent),
                      let document = try? loadDay(date, in: stream), document.isDirty else { return nil }
                return document
            }
        }
    }

    private func recoveryURL(for document: DayDocument) -> URL {
        libraryRoot.appendingPathComponent(".current-recovery", isDirectory: true)
            .appendingPathComponent(document.streamID.uuidString, isDirectory: true)
            .appendingPathComponent(document.dayKey + ".json")
    }

    private func recover(_ document: DayDocument) -> DayDocument {
        guard let data = try? Data(contentsOf: recoveryURL(for: document)),
              var recovered = try? metadataDecoder.decode(DayDocument.self, from: data),
              recovered.streamID == document.streamID, recovered.dayKey == document.dayKey else { return document }
        if recovered.text == document.text { removeRecovery(for: document); return document }
        recovered.fileURL = document.fileURL
        recovered.libraryID = document.libraryID
        recovered.date = document.date
        recovered.isDirty = recovered.text != recovered.lastSavedText
        return recovered.isDirty ? recovered : document
    }
}
