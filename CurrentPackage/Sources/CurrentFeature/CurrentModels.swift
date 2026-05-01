import Foundation

public struct Stream: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var slug: String
    public var rootURL: URL
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        slug: String,
        rootURL: URL,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.slug = slug
        self.rootURL = rootURL
        self.createdAt = createdAt
    }
}

public struct DayDocument: Equatable, Identifiable, Sendable {
    public var id: String { DayFormatting.dayKey(for: date) }

    public var streamID: UUID
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
        lastKnownModificationDate: Date? = nil
    ) {
        self.streamID = streamID
        self.date = Calendar.current.startOfDay(for: date)
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
