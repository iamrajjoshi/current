import Foundation

extension StreamStore {
    public var manifestURL: URL { libraryRoot.appendingPathComponent(".current-library.json") }
    private var sessionURL: URL { libraryRoot.appendingPathComponent(".current-session.json") }

    public func loadLibrary() throws -> StreamLibrary {
        try createDirectoryIfNeeded(libraryRoot)
        var manifest: LibraryManifest?
        if fileManager.fileExists(atPath: manifestURL.path) {
            do {
                manifest = try metadataDecoder.decode(LibraryManifest.self, from: Data(contentsOf: manifestURL))
            } catch {
                try backUp(manifestURL, suffix: ".damaged-backup")
                let backup = manifestURL.appendingPathExtension("backup")
                if let data = try? Data(contentsOf: backup) {
                    manifest = try? metadataDecoder.decode(LibraryManifest.self, from: data)
                }
            }
        }
        if let manifest, manifest.version != 1 {
            throw StreamStoreError.invalidLibrary("This library was created by a newer version of Current.")
        }
        var streams = try manifest?.streams.map { try $0.resolve(in: libraryRoot) } ?? []
        var folders = manifest?.folders ?? []
        let discovered = try discoverStreams()
        for stream in discovered where !streams.contains(where: { $0.slug == stream.slug || $0.id == stream.id }) {
            streams.append(stream)
        }
        if streams.isEmpty {
            let root = libraryRoot.appendingPathComponent("streams/daily", isDirectory: true)
            streams = [Stream(name: Self.defaultStreamName, slug: Self.defaultStreamSlug, rootURL: root)]
        }
        guard Set(streams.map(\.id)).count == streams.count,
              Set(streams.map(\.slug)).count == streams.count else {
            throw StreamStoreError.invalidLibrary("Duplicate stream identifiers were found.")
        }
        // A lost folder record must never hide a recovered stream.
        let folderIDs = Set(folders.map(\.id))
        for index in streams.indices where streams[index].folderID.map({ !folderIDs.contains($0) }) == true {
            streams[index].folderID = nil
        }
        streams.sort { ($0.order, $0.name) < ($1.order, $1.name) }
        folders.sort { ($0.order, $0.name) < ($1.order, $1.name) }
        let library = StreamLibrary(streams: streams, folders: folders)
        if manifest == nil || discovered.contains(where: { discovered in !((manifest?.streams ?? []).contains { $0.id == discovered.id }) }) {
            try saveLibrary(streams: streams, folders: folders)
        }
        return library
    }

    public func saveLibrary(streams: [Stream], folders: [StreamFolder]) throws {
        try createDirectoryIfNeeded(libraryRoot)
        let records = streams.map(StreamRecord.init)
        for record in records {
            let stream = try record.resolve(in: libraryRoot)
            try createDirectoryIfNeeded(stream.rootURL)
            let url = stream.rootURL.appendingPathComponent(metadataFilename)
            if let data = try? Data(contentsOf: url), (try? metadataDecoder.decode(Stream.self, from: data)) != nil {
                try backUp(url, suffix: ".backup")
            }
            try metadataEncoder.encode(record).write(to: url, options: .atomic)
        }
        let next = LibraryManifest(streams: records, folders: folders)
        if fileManager.fileExists(atPath: manifestURL.path) {
            let old = try Data(contentsOf: manifestURL)
            if (try? metadataDecoder.decode(LibraryManifest.self, from: old)) != nil {
                try old.write(to: manifestURL.appendingPathExtension("backup"), options: .atomic)
            }
        }
        try metadataEncoder.encode(next).write(to: manifestURL, options: .atomic)
    }

    public func createStream(name: String, folderID: UUID? = nil) throws -> Stream {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw StreamStoreError.invalidName }
        var library = try loadLibrary()
        let id = UUID()
        let components = trimmed.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
        var slug = components.joined(separator: "-")
        if slug.isEmpty { slug = "stream" }
        if library.streams.contains(where: { $0.slug == slug }) {
            slug += "-" + id.uuidString.prefix(8).lowercased()
        }
        let stream = Stream(id: id, name: trimmed, slug: slug,
                            rootURL: libraryRoot.appendingPathComponent("streams/\(slug)", isDirectory: true),
                            folderID: folderID, order: (library.streams.map(\.order).max() ?? -1) + 1)
        library.streams.append(stream)
        try saveLibrary(streams: library.streams, folders: library.folders)
        return stream
    }

    func loadSession() -> LibrarySession {
        guard let data = try? Data(contentsOf: sessionURL),
              let session = try? metadataDecoder.decode(LibrarySession.self, from: data) else { return LibrarySession() }
        return session
    }

    func saveSession(_ session: LibrarySession) throws {
        try createDirectoryIfNeeded(libraryRoot)
        try metadataEncoder.encode(session).write(to: sessionURL, options: .atomic)
    }

    public func date(for dayKey: String) -> Date? {
        let parts = dayKey.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3,
              let date = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2])),
              DayFormatting.dayKey(for: date, calendar: calendar) == dayKey else { return nil }
        return date
    }

    private func discoverStreams() throws -> [Stream] {
        let root = libraryRoot.appendingPathComponent("streams", isDirectory: true)
        guard fileManager.fileExists(atPath: root.path) else { return [] }
        let directories = try fileManager.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        return try directories.enumerated().map { index, directory in
            let metadata = directory.appendingPathComponent(metadataFilename)
            if let data = try? Data(contentsOf: metadata) {
                if let record = try? metadataDecoder.decode(StreamRecord.self, from: data) {
                    var stream = try record.resolve(in: libraryRoot)
                    stream.slug = directory.lastPathComponent
                    stream.rootURL = directory
                    return stream
                }
                if var stream = try? metadataDecoder.decode(Stream.self, from: data) {
                    stream.rootURL = directory
                    stream.slug = directory.lastPathComponent
                    stream.order = index
                    try backUp(metadata, suffix: ".backup")
                    return stream
                }
                try backUp(metadata, suffix: ".damaged-backup")
                // Preserve a readable identity even when another metadata field is damaged.
                let values = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
                let id = (values?["id"] as? String).flatMap(UUID.init(uuidString:)) ?? UUID()
                let name = (values?["name"] as? String) ?? directory.lastPathComponent
                return Stream(id: id, name: name, slug: directory.lastPathComponent,
                              rootURL: directory, order: index)
            }
            return Stream(name: directory.lastPathComponent == "daily" ? Self.defaultStreamName : directory.lastPathComponent,
                          slug: directory.lastPathComponent, rootURL: directory, order: index)
        }
    }

    private func backUp(_ url: URL, suffix: String) throws {
        let destination = URL(fileURLWithPath: url.path + suffix)
        if !fileManager.fileExists(atPath: destination.path) { try fileManager.copyItem(at: url, to: destination) }
    }
}
