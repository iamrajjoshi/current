import Foundation

public struct Stream: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var slug: String
    public var rootURL: URL
    public var createdAt: Date
    public var folderID: UUID?
    public var isPinned: Bool
    public var isArchived: Bool
    public var order: Int

    public init(
        id: UUID = UUID(),
        name: String,
        slug: String,
        rootURL: URL,
        createdAt: Date = Date(),
        folderID: UUID? = nil,
        isPinned: Bool = false,
        isArchived: Bool = false,
        order: Int = 0
    ) {
        self.id = id
        self.name = name
        self.slug = slug
        self.rootURL = rootURL
        self.createdAt = createdAt
        self.folderID = folderID
        self.isPinned = isPinned
        self.isArchived = isArchived
        self.order = order
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, slug, rootURL, createdAt, folderID, isPinned, isArchived, order
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        name = try values.decode(String.self, forKey: .name)
        slug = try values.decode(String.self, forKey: .slug)
        rootURL = try values.decode(URL.self, forKey: .rootURL)
        createdAt = try values.decode(Date.self, forKey: .createdAt)
        folderID = try values.decodeIfPresent(UUID.self, forKey: .folderID)
        isPinned = try values.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
        isArchived = try values.decodeIfPresent(Bool.self, forKey: .isArchived) ?? false
        order = try values.decodeIfPresent(Int.self, forKey: .order) ?? 0
    }
}

public struct DocumentID: Codable, Hashable, Sendable {
    public var libraryID: String
    public var streamID: UUID
    public var dayKey: String

    public init(libraryID: String, streamID: UUID, dayKey: String) {
        self.libraryID = libraryID
        self.streamID = streamID
        self.dayKey = dayKey
    }

    public var rawValue: String { "\(libraryID)|\(streamID.uuidString)|\(dayKey)" }
}

public struct DayDocument: Codable, Equatable, Identifiable, Sendable {
    public var id: String { documentID.rawValue }
    public var documentID: DocumentID {
        DocumentID(libraryID: libraryID, streamID: streamID, dayKey: dayKey)
    }

    public var streamID: UUID
    public var libraryID: String
    public var dayKey: String
    public var date: Date
    public var fileURL: URL
    public var text: String
    public var lastSavedText: String
    public var isDirty: Bool
    public var lastLoadedAt: Date
    public var lastKnownModificationDate: Date?

    public init(
        streamID: UUID,
        date: Date,
        fileURL: URL,
        text: String,
        lastSavedText: String? = nil,
        isDirty: Bool = false,
        lastLoadedAt: Date = Date(),
        lastKnownModificationDate: Date? = nil,
        libraryID: String? = nil,
        dayKey: String? = nil
    ) {
        self.streamID = streamID
        self.libraryID = libraryID ?? fileURL.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().standardizedFileURL.path
        self.dayKey = dayKey ?? DayFormatting.dayKey(for: date)
        self.date = date
        self.fileURL = fileURL
        self.text = text
        self.lastSavedText = lastSavedText ?? text
        self.isDirty = isDirty
        self.lastLoadedAt = lastLoadedAt
        self.lastKnownModificationDate = lastKnownModificationDate
    }
}

public enum StreamStoreError: Error, Equatable, LocalizedError {
    case missingDocumentsDirectory
    case unableToCreateLibrary(String)
    case unableToRead(URL)
    case unableToWrite(URL, String)
    case diskChanged(URL, diskText: String)
    case invalidName
    case invalidLibrary(String)

    public var errorDescription: String? {
        switch self {
        case .missingDocumentsDirectory:
            return "Current could not find your Documents folder."
        case .unableToCreateLibrary(let message):
            return "Current could not create its library: \(message)"
        case .unableToRead(let url):
            return "Current could not read \(url.lastPathComponent)."
        case .unableToWrite(let url, let message):
            return "Current could not save \(url.lastPathComponent): \(message)"
        case .diskChanged(let url, _):
            return "\(url.lastPathComponent) changed on disk before Current could save it."
        case .invalidName:
            return "Enter a name that contains at least one character."
        case .invalidLibrary(let message):
            return "Current could not open this library: \(message)"
        }
    }
}

public enum DayFormatting {
    public static func dayKey(for date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: calendar.startOfDay(for: date))
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    public static func yearFolder(for date: Date, calendar: Calendar = .current) -> String {
        let year = calendar.component(.year, from: calendar.startOfDay(for: date))
        return String(format: "%04d", year)
    }

    public static func monthFolder(for date: Date, calendar: Calendar = .current) -> String {
        let month = calendar.component(.month, from: calendar.startOfDay(for: date))
        return String(format: "%02d", month)
    }

    public static func visibleTitle(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    public static func shortTitle(for date: Date, calendar: Calendar = .current) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE, MMM d"
        return formatter.string(from: date)
    }

    public static func monthDayTitle(for date: Date, calendar: Calendar = .current) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }
}

public extension Calendar {
    func addingDays(_ count: Int, to date: Date) -> Date {
        self.date(byAdding: .day, value: count, to: startOfDay(for: date)) ?? startOfDay(for: date)
    }
}
