import Foundation

/// Search is rebuilt from Markdown, not from whichever days happen to be on screen.
public enum LibrarySearch {
    public static func search(query: String, streams: [Stream], libraryRoot: URL,
                              calendar: Calendar = .current, limit: Int = 200,
                              overrides: [DayDocument] = []) -> [LibrarySearchResult] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }
        let store = StreamStore(libraryRoot: libraryRoot, calendar: calendar)
        let streamIDs = Set(streams.map(\.id))
        let overrides = Dictionary(uniqueKeysWithValues: overrides.filter {
            $0.libraryID == store.libraryID && streamIDs.contains($0.streamID)
        }.map { ($0.documentID, $0) })
        var seen: Set<DocumentID> = []
        var matches: [LibrarySearchResult] = []
        func appendMatch(text: String, date: Date, stream: Stream, id: DocumentID) {
            guard let range = text.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) else { return }
            let sourceMatch = NSRange(range, in: text)
            let excerpt = MarkdownSearchExcerpt.make(source: text, matchRange: sourceMatch)
            matches.append(LibrarySearchResult(documentID: id, streamID: stream.id, streamName: stream.name,
                date: date, dayKey: id.dayKey, snippet: excerpt.text, matchRange: sourceMatch, excerptMatchRange: excerpt.matchRange))
        }
        for stream in streams {
            guard !Task.isCancelled else { return [] }
            guard let files = FileManager.default.enumerator(at: stream.rootURL,
                    includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) else { continue }
            for case let url as URL in files {
                guard !Task.isCancelled else { return [] }
                guard url.pathExtension == "md", let date = store.date(for: url.deletingPathExtension().lastPathComponent),
                      url.standardizedFileURL == store.dayURL(for: date, in: stream).standardizedFileURL else { continue }
                let key = DayFormatting.dayKey(for: date, calendar: calendar)
                let id = DocumentID(libraryID: store.libraryID, streamID: stream.id, dayKey: key)
                seen.insert(id)
                guard let text = overrides[id]?.text ?? (try? String(contentsOf: url, encoding: .utf8)) else { continue }
                appendMatch(text: text, date: date, stream: stream, id: id)
            }
        }
        for document in overrides.values where !seen.contains(document.documentID) {
            guard !Task.isCancelled else { return [] }
            guard let stream = streams.first(where: { $0.id == document.streamID }) else { continue }
            appendMatch(text: document.text, date: document.date, stream: stream, id: document.documentID)
        }
        return Array(matches.sorted { $0.date == $1.date ? $0.streamName < $1.streamName : $0.date > $1.date }.prefix(limit))
    }
}
