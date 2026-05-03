import Combine
import Foundation

public struct CurrentConfiguration: Equatable, Hashable, Sendable {
    public static let defaultFontFamily: String? = nil
    public static let defaultFontSize: Double = 13
    public static let defaultLineHeight: Double = 22
    public static let defaultContentWidth: Double = 700
    public static let defaultRecentDays = 7
    public static let defaultHistoryBatchDays = 14
    public static let defaultHistoryWindowDays = 180
    public static let defaultAutosaveDelay: Double = 0.55

    public var fontFamily: String?
    public var fontSize: Double
    public var lineHeight: Double
    public var contentWidth: Double
    public var recentDays: Int
    public var historyBatchDays: Int
    public var historyWindowDays: Int
    public var autosaveDelay: Double

    public init(
        fontFamily: String? = Self.defaultFontFamily,
        fontSize: Double = Self.defaultFontSize,
        lineHeight: Double = Self.defaultLineHeight,
        contentWidth: Double = Self.defaultContentWidth,
        recentDays: Int = Self.defaultRecentDays,
        historyBatchDays: Int = Self.defaultHistoryBatchDays,
        historyWindowDays: Int = Self.defaultHistoryWindowDays,
        autosaveDelay: Double = Self.defaultAutosaveDelay
    ) {
        self.fontFamily = fontFamily
        self.fontSize = fontSize
        self.lineHeight = lineHeight
        self.contentWidth = contentWidth
        self.recentDays = recentDays
        self.historyBatchDays = historyBatchDays
        self.historyWindowDays = historyWindowDays
        self.autosaveDelay = autosaveDelay
    }

    public static let `default` = CurrentConfiguration()

    public static let editableTemplate = """
    # Current configuration
    # Syntax is key = value. Blank lines and whole-line # comments are ignored.
    # Empty values reset a setting to Current's default.
    #
    # font-family =
    # font-size = 13
    # line-height = 22
    # content-width = 700
    # recent-days = 7
    # history-batch-days = 14
    # history-window-days = 180
    # autosave-delay = 0.55
    #
    # Split config into another file:
    # config-file = extras.current
    # config-file = ?machine.current
    """
}

public enum CurrentConfigurationDiagnosticSeverity: String, Equatable, Sendable {
    case warning
    case error
}

public struct CurrentConfigurationDiagnostic: Identifiable, Equatable, Sendable {
    public var severity: CurrentConfigurationDiagnosticSeverity
    public var message: String
    public var url: URL?
    public var line: Int?

    public var id: String {
        "\(severity.rawValue):\(url?.path ?? ""):\(line.map(String.init) ?? ""):\(message)"
    }

    public init(
        severity: CurrentConfigurationDiagnosticSeverity,
        message: String,
        url: URL? = nil,
        line: Int? = nil
    ) {
        self.severity = severity
        self.message = message
        self.url = url
        self.line = line
    }

    public var displayMessage: String {
        var prefix = severity.rawValue.capitalized
        if let url {
            prefix += " in \(url.lastPathComponent)"
        }
        if let line {
            prefix += ":\(line)"
        }
        return "\(prefix): \(message)"
    }
}

public struct CurrentConfigurationLoadResult: Equatable, Sendable {
    public var configuration: CurrentConfiguration
    public var diagnostics: [CurrentConfigurationDiagnostic]
    public var rootURL: URL?

    public init(
        configuration: CurrentConfiguration,
        diagnostics: [CurrentConfigurationDiagnostic] = [],
        rootURL: URL? = nil
    ) {
        self.configuration = configuration
        self.diagnostics = diagnostics
        self.rootURL = rootURL
    }
}

public struct CurrentConfigurationLocations: Equatable, Sendable {
    public var xdgConfigDirectory: URL
    public var applicationSupportDirectory: URL

    public init(
        xdgConfigDirectory: URL,
        applicationSupportDirectory: URL
    ) {
        self.xdgConfigDirectory = xdgConfigDirectory
        self.applicationSupportDirectory = applicationSupportDirectory
    }

    public init(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        applicationSupportDirectory: URL? = nil
    ) {
        let xdgRootPath = environment["XDG_CONFIG_HOME"].flatMap { value -> String? in
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        let xdgRoot = xdgRootPath.map {
            Self.fileURL(for: $0, homeDirectory: homeDirectory)
        } ?? homeDirectory.appendingPathComponent(".config", isDirectory: true)

        let applicationSupport = applicationSupportDirectory ?? Self.defaultApplicationSupportDirectory(
            homeDirectory: homeDirectory
        )

        self.init(
            xdgConfigDirectory: xdgRoot.appendingPathComponent("current", isDirectory: true),
            applicationSupportDirectory: applicationSupport
        )
    }

    public var primaryEditableURL: URL {
        xdgConfigDirectory.appendingPathComponent("config.current")
    }

    public var searchURLs: [URL] {
        [
            xdgConfigDirectory.appendingPathComponent("config.current"),
            xdgConfigDirectory.appendingPathComponent("config"),
            applicationSupportDirectory.appendingPathComponent("config.current"),
            applicationSupportDirectory.appendingPathComponent("config")
        ]
    }

    public func firstExistingConfig(fileManager: FileManager = .default) -> URL? {
        searchURLs.first { url in
            var isDirectory: ObjCBool = false
            return fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory)
                && !isDirectory.boolValue
        }
    }

    static func fileURL(for path: String, homeDirectory: URL) -> URL {
        if path == "~" {
            return homeDirectory
        }
        if path.hasPrefix("~/") {
            return homeDirectory.appendingPathComponent(String(path.dropFirst(2)))
        }
        return URL(fileURLWithPath: path)
    }

    private static func defaultApplicationSupportDirectory(homeDirectory: URL) -> URL {
        let base = homeDirectory.appendingPathComponent("Library/Application Support", isDirectory: true)
        return base.appendingPathComponent("com.raj.current", isDirectory: true)
    }
}

public final class CurrentConfigurationStore: ObservableObject {
    @Published public private(set) var configuration: CurrentConfiguration
    @Published public private(set) var diagnostics: [CurrentConfigurationDiagnostic]
    @Published public private(set) var loadedRootURL: URL?

    public let locations: CurrentConfigurationLocations
    private let fileManager: FileManager
    private let homeDirectory: URL

    public init(
        locations: CurrentConfigurationLocations = CurrentConfigurationLocations(),
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        fileManager: FileManager = .default
    ) {
        self.locations = locations
        self.homeDirectory = homeDirectory
        self.fileManager = fileManager
        let result = CurrentConfigurationLoader.load(
            locations: locations,
            homeDirectory: homeDirectory,
            fileManager: fileManager
        )
        self.configuration = result.configuration
        self.diagnostics = result.diagnostics
        self.loadedRootURL = result.rootURL
    }

    @discardableResult
    public func reload() -> [CurrentConfigurationDiagnostic] {
        let result = CurrentConfigurationLoader.load(
            locations: locations,
            homeDirectory: homeDirectory,
            fileManager: fileManager
        )
        configuration = result.configuration
        diagnostics = result.diagnostics
        loadedRootURL = result.rootURL
        return result.diagnostics
    }

    public func ensureEditableConfigurationFile() throws -> URL {
        if let existing = locations.firstExistingConfig(fileManager: fileManager) {
            return existing
        }

        let url = locations.primaryEditableURL
        try fileManager.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try CurrentConfiguration.editableTemplate.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}

private enum CurrentConfigurationLoader {
    static func load(
        locations: CurrentConfigurationLocations,
        homeDirectory: URL,
        fileManager: FileManager
    ) -> CurrentConfigurationLoadResult {
        guard let rootURL = locations.firstExistingConfig(fileManager: fileManager) else {
            return CurrentConfigurationLoadResult(configuration: .default)
        }

        var context = LoadingContext(
            homeDirectory: homeDirectory,
            fileManager: fileManager
        )
        parseFile(rootURL.standardizedFileURL, context: &context, optional: false)
        return CurrentConfigurationLoadResult(
            configuration: context.configuration,
            diagnostics: context.diagnostics,
            rootURL: rootURL
        )
    }

    private static func parseFile(
        _ url: URL,
        context: inout LoadingContext,
        optional: Bool,
        includedFrom parentURL: URL? = nil,
        line includeLine: Int? = nil
    ) {
        var isDirectory: ObjCBool = false
        let exists = context.fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory)
        guard exists && !isDirectory.boolValue else {
            if !optional {
                context.diagnostics.append(CurrentConfigurationDiagnostic(
                    severity: .error,
                    message: "Config file not found: \(url.path)",
                    url: parentURL,
                    line: includeLine
                ))
            }
            return
        }

        let standardizedURL = url.standardizedFileURL
        if context.stack.contains(standardizedURL) {
            context.diagnostics.append(CurrentConfigurationDiagnostic(
                severity: .warning,
                message: "Skipped cyclic config-file include: \(standardizedURL.path)",
                url: parentURL,
                line: includeLine
            ))
            return
        }

        let text: String
        do {
            text = try String(contentsOf: standardizedURL, encoding: .utf8)
        } catch {
            context.diagnostics.append(CurrentConfigurationDiagnostic(
                severity: .error,
                message: "Could not read config file: \(error.localizedDescription)",
                url: standardizedURL
            ))
            return
        }

        context.stack.append(standardizedURL)
        defer { _ = context.stack.popLast() }

        var includes: [ConfigInclude] = []
        for (index, rawLine) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let lineNumber = index + 1
            let line = String(rawLine).trimmingCharacters(in: CharacterSet(charactersIn: "\r"))
            parseLine(line, lineNumber: lineNumber, url: standardizedURL, context: &context, includes: &includes)
        }

        for include in includes {
            guard !include.path.isEmpty else {
                context.diagnostics.append(CurrentConfigurationDiagnostic(
                    severity: .warning,
                    message: "Ignored empty config-file value.",
                    url: standardizedURL,
                    line: include.line
                ))
                continue
            }

            let includeURL = resolvedIncludeURL(
                include.path,
                from: standardizedURL,
                homeDirectory: context.homeDirectory
            )
            parseFile(
                includeURL,
                context: &context,
                optional: include.optional,
                includedFrom: standardizedURL,
                line: include.line
            )
        }
    }

    private static func parseLine(
        _ line: String,
        lineNumber: Int,
        url: URL,
        context: inout LoadingContext,
        includes: inout [ConfigInclude]
    ) {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { return }

        guard let equals = line.firstIndex(of: "=") else {
            context.diagnostics.append(CurrentConfigurationDiagnostic(
                severity: .warning,
                message: "Ignored line without '='.",
                url: url,
                line: lineNumber
            ))
            return
        }

        let key = line[..<equals].trimmingCharacters(in: .whitespaces)
        let rawValue = line[line.index(after: equals)...].trimmingCharacters(in: .whitespaces)

        if key == "config-file" {
            includes.append(parseInclude(rawValue, line: lineNumber))
            return
        }

        apply(
            key: String(key),
            value: unquoted(String(rawValue)),
            lineNumber: lineNumber,
            url: url,
            context: &context
        )
    }

    private static func apply(
        key: String,
        value: String,
        lineNumber: Int,
        url: URL,
        context: inout LoadingContext
    ) {
        switch key {
        case "font-family":
            context.configuration.fontFamily = value.isEmpty ? CurrentConfiguration.default.fontFamily : value
        case "font-size":
            if let parsed = parsedDouble(
                value,
                key: key,
                range: 6...72,
                defaultValue: CurrentConfiguration.default.fontSize,
                lineNumber: lineNumber,
                url: url,
                context: &context
            ) {
                context.configuration.fontSize = parsed
            }
        case "line-height":
            if let parsed = parsedDouble(
                value,
                key: key,
                range: 8...120,
                defaultValue: CurrentConfiguration.default.lineHeight,
                lineNumber: lineNumber,
                url: url,
                context: &context
            ) {
                context.configuration.lineHeight = parsed
            }
        case "content-width":
            if let parsed = parsedDouble(
                value,
                key: key,
                range: 320...2000,
                defaultValue: CurrentConfiguration.default.contentWidth,
                lineNumber: lineNumber,
                url: url,
                context: &context
            ) {
                context.configuration.contentWidth = parsed
            }
        case "recent-days":
            if let parsed = parsedInt(
                value,
                key: key,
                range: 1...3650,
                defaultValue: CurrentConfiguration.default.recentDays,
                lineNumber: lineNumber,
                url: url,
                context: &context
            ) {
                context.configuration.recentDays = parsed
            }
        case "history-batch-days":
            if let parsed = parsedInt(
                value,
                key: key,
                range: 1...3650,
                defaultValue: CurrentConfiguration.default.historyBatchDays,
                lineNumber: lineNumber,
                url: url,
                context: &context
            ) {
                context.configuration.historyBatchDays = parsed
            }
        case "history-window-days":
            if let parsed = parsedInt(
                value,
                key: key,
                range: 1...10000,
                defaultValue: CurrentConfiguration.default.historyWindowDays,
                lineNumber: lineNumber,
                url: url,
                context: &context
            ) {
                context.configuration.historyWindowDays = parsed
            }
        case "autosave-delay":
            if let parsed = parsedDouble(
                value,
                key: key,
                range: 0...60,
                defaultValue: CurrentConfiguration.default.autosaveDelay,
                lineNumber: lineNumber,
                url: url,
                context: &context
            ) {
                context.configuration.autosaveDelay = parsed
            }
        default:
            context.diagnostics.append(CurrentConfigurationDiagnostic(
                severity: .warning,
                message: "Unknown config key '\(key)'.",
                url: url,
                line: lineNumber
            ))
        }
    }

    private static func parsedDouble(
        _ value: String,
        key: String,
        range: ClosedRange<Double>,
        defaultValue: Double,
        lineNumber: Int,
        url: URL,
        context: inout LoadingContext
    ) -> Double? {
        guard !value.isEmpty else {
            return defaultValue
        }
        guard let parsed = Double(value), range.contains(parsed) else {
            context.diagnostics.append(CurrentConfigurationDiagnostic(
                severity: .warning,
                message: "Ignored invalid value for \(key): \(value).",
                url: url,
                line: lineNumber
            ))
            return nil
        }
        return parsed
    }

    private static func parsedInt(
        _ value: String,
        key: String,
        range: ClosedRange<Int>,
        defaultValue: Int,
        lineNumber: Int,
        url: URL,
        context: inout LoadingContext
    ) -> Int? {
        guard !value.isEmpty else {
            return defaultValue
        }
        guard let parsed = Int(value), range.contains(parsed) else {
            context.diagnostics.append(CurrentConfigurationDiagnostic(
                severity: .warning,
                message: "Ignored invalid value for \(key): \(value).",
                url: url,
                line: lineNumber
            ))
            return nil
        }
        return parsed
    }

    private static func parseInclude(_ rawValue: String, line: Int) -> ConfigInclude {
        var value = rawValue.trimmingCharacters(in: .whitespaces)
        var optional = false
        if value.hasPrefix("?") {
            optional = true
            value.removeFirst()
            value = value.trimmingCharacters(in: .whitespaces)
        }
        return ConfigInclude(path: unquoted(value), optional: optional, line: line)
    }

    private static func unquoted(_ value: String) -> String {
        guard value.count >= 2,
              let first = value.first,
              let last = value.last,
              (first == "\"" && last == "\"") || (first == "'" && last == "'") else {
            return value
        }

        let start = value.index(after: value.startIndex)
        let end = value.index(before: value.endIndex)
        return String(value[start..<end])
            .replacingOccurrences(of: "\\\"", with: "\"")
            .replacingOccurrences(of: "\\\\", with: "\\")
    }

    private static func resolvedIncludeURL(
        _ path: String,
        from containingURL: URL,
        homeDirectory: URL
    ) -> URL {
        if path.hasPrefix("/") || path == "~" || path.hasPrefix("~/") {
            return CurrentConfigurationLocations.fileURL(for: path, homeDirectory: homeDirectory).standardizedFileURL
        }
        return containingURL
            .deletingLastPathComponent()
            .appendingPathComponent(path)
            .standardizedFileURL
    }
}

private struct LoadingContext {
    var configuration = CurrentConfiguration()
    var diagnostics: [CurrentConfigurationDiagnostic] = []
    var stack: [URL] = []
    var homeDirectory: URL
    var fileManager: FileManager
}

private struct ConfigInclude {
    var path: String
    var optional: Bool
    var line: Int
}
