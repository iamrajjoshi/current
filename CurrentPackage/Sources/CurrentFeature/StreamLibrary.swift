import Foundation

public struct StreamFolder: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var order: Int

    public init(id: UUID = UUID(), name: String, order: Int = 0) {
        self.id = id
        self.name = name
        self.order = order
    }
}

public struct StreamLibrary: Equatable, Sendable {
    public var streams: [Stream]
    public var folders: [StreamFolder]
}

struct LibraryManifest: Codable {
    var version = 1
    var streams: [StreamRecord]
    var folders: [StreamFolder]
}

/// On-disk metadata has no absolute URLs. A library copy owns its own resolved paths.
struct StreamRecord: Codable {
    var id: UUID
    var name: String
    var relativePath: String
    var createdAt: Date
    var folderID: UUID?
    var isPinned: Bool
    var isArchived: Bool
    var order: Int

    init(_ stream: Stream) {
        id = stream.id
        name = stream.name
        relativePath = "streams/\(stream.slug)"
        createdAt = stream.createdAt
        folderID = stream.folderID
        isPinned = stream.isPinned
        isArchived = stream.isArchived
        order = stream.order
    }

    func resolve(in root: URL) throws -> Stream {
        let components = relativePath.split(separator: "/", omittingEmptySubsequences: false)
        guard components.count == 2, components[0] == "streams",
              !components[1].isEmpty, components[1] != ".", components[1] != ".." else {
            throw StreamStoreError.invalidLibrary("An invalid stream path was found in the library metadata.")
        }
        return Stream(id: id, name: name, slug: String(components[1]),
                      rootURL: root.appendingPathComponent(relativePath, isDirectory: true),
                      createdAt: createdAt, folderID: folderID, isPinned: isPinned,
                      isArchived: isArchived, order: order)
    }
}

public struct StreamViewState: Codable, Equatable, Sendable {
    public var dayKey: String?
    public var scrollDayKey: String?
    public var scrollOffset: Double
    public var selectionLocation: Int
    public var selectionLength: Int
    public var minimizedDayKeys: Set<String>
    public var readingAnchor: MarkdownReadingAnchor?
    public var editorHadFocus: Bool?

    public init(dayKey: String? = nil, scrollDayKey: String? = nil, scrollOffset: Double = 0,
                selectionLocation: Int = 0, selectionLength: Int = 0, minimizedDayKeys: Set<String> = [],
                readingAnchor: MarkdownReadingAnchor? = nil, editorHadFocus: Bool? = nil) {
        self.dayKey = dayKey
        self.scrollDayKey = scrollDayKey
        self.scrollOffset = scrollOffset
        self.selectionLocation = selectionLocation
        self.selectionLength = selectionLength
        self.minimizedDayKeys = minimizedDayKeys
        self.readingAnchor = readingAnchor
        self.editorHadFocus = editorHadFocus
    }
}

extension Notification.Name {
    static let captureCurrentWorkspacePosition = Notification.Name("Current.captureWorkspacePosition")
}

struct LibrarySession: Codable {
    var selectedStreamID: UUID?
    var openStreamIDs: [UUID] = []
    var views: [UUID: StreamViewState] = [:]
}

public struct LibrarySearchResult: Equatable, Identifiable, Sendable {
    public var id: String { documentID.rawValue }
    public var documentID: DocumentID
    public var streamID: UUID
    public var streamName: String
    public var date: Date
    public var dayKey: String
    public var snippet: String
    public var matchRange: NSRange
    /// Plain-text context and UTF-16 highlight coordinates. matchRange above
    /// continues to address the original Markdown for exact editor selection.
    public var excerpt: String { snippet }
    public var excerptMatchRange: NSRange = NSRange(location: NSNotFound, length: 0)
}

public struct DocumentConflict: Identifiable, Equatable {
    public var id: String { document.id }
    public var document: DayDocument
    public var diskText: String
}
