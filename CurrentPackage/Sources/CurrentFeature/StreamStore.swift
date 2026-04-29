import Foundation

public final class StreamStore {
    public static let defaultStreamName = "Daily"
    public static let defaultStreamSlug = "Daily"

    public let libraryRoot: URL
    public var calendar: Calendar
    private let fileManager: FileManager
    private let metadataFilename = ".current-stream.json"

    public init(
        libraryRoot: URL = StreamStore.defaultLibraryRoot(),
        calendar: Calendar = .current,
        fileManager: FileManager = .default
    ) {
        self.libraryRoot = libraryRoot
        self.calendar = calendar
        self.fileManager = fileManager
    }

    public static func defaultLibraryRoot() -> URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        return (documents ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Documents", isDirectory: true))
            .appendingPathComponent("Current", isDirectory: true)
    }

    public func defaultStream() throws -> Stream {
        let streamRoot = libraryRoot
            .appendingPathComponent("Streams", isDirectory: true)
            .appendingPathComponent(Self.defaultStreamSlug, isDirectory: true)
        try createDirectoryIfNeeded(streamRoot)

        let metadataURL = streamRoot.appendingPathComponent(metadataFilename)
        if fileManager.fileExists(atPath: metadataURL.path),
           let data = try? Data(contentsOf: metadataURL),
           let stream = try? JSONDecoder().decode(Stream.self, from: data) {
            return stream
        }

        let stream = Stream(name: Self.defaultStreamName, slug: Self.defaultStreamSlug, rootURL: streamRoot)
        try writeMetadata(stream, to: metadataURL)
        return stream
    }

    public func dayURL(for date: Date, in stream: Stream) -> URL {
        let normalized = calendar.startOfDay(for: date)
        return stream.rootURL
            .appendingPathComponent(DayFormatting.yearFolder(for: normalized, calendar: calendar), isDirectory: true)
            .appendingPathComponent(DayFormatting.monthFolder(for: normalized, calendar: calendar), isDirectory: true)
            .appendingPathComponent("\(DayFormatting.dayKey(for: normalized, calendar: calendar)).md")
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
                } catch {
                    throw StreamStoreError.unableToWrite(fileURL, error.localizedDescription)
                }
            } else {
                return DayDocument(streamID: stream.id, date: normalized, fileURL: fileURL, text: "")
            }
        }

        let text: String
        do {
            let data = try Data(contentsOf: fileURL)
            text = String(data: data, encoding: .utf8) ?? ""
        } catch {
            throw StreamStoreError.unableToRead(fileURL)
        }

        return DayDocument(
            streamID: stream.id,
            date: normalized,
            fileURL: fileURL,
            text: text,
            lastLoadedAt: Date(),
            lastKnownModificationDate: modificationDate(for: fileURL)
        )
    }

    @discardableResult
    public func saveDay(_ document: DayDocument) throws -> DayDocument {
        try createDirectoryIfNeeded(document.fileURL.deletingLastPathComponent())

        if fileManager.fileExists(atPath: document.fileURL.path) {
            let diskText = (try? String(contentsOf: document.fileURL, encoding: .utf8)) ?? ""
            if document.isDirty, diskText != document.lastSavedText {
                throw StreamStoreError.diskChanged(document.fileURL, diskText: diskText)
            }
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
        return saved
    }

    public func reloadExternalChangesIfNeeded(_ document: DayDocument) throws -> DayDocument {
        guard fileManager.fileExists(atPath: document.fileURL.path) else {
            return document
        }

        let currentModificationDate = modificationDate(for: document.fileURL)
        guard currentModificationDate != document.lastKnownModificationDate else {
            return document
        }

        let diskText = (try? String(contentsOf: document.fileURL, encoding: .utf8)) ?? ""
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

    private func writeMetadata(_ stream: Stream, to url: URL) throws {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(stream).write(to: url, options: [.atomic])
        } catch {
            throw StreamStoreError.unableToCreateLibrary(error.localizedDescription)
        }
    }

    private func createDirectoryIfNeeded(_ url: URL) throws {
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
}
