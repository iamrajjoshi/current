import CoreServices
import Foundation

/// FSEvents observes descendants, including notes that haven't entered the day cache.
final class LibraryFileWatcher {
    private final class Handler {
        let action: @Sendable () -> Void
        init(_ action: @escaping @Sendable () -> Void) { self.action = action }
    }

    private var stream: FSEventStreamRef?

    init(root: URL, onChange: @escaping @Sendable () -> Void) {
        let handler = Unmanaged.passRetained(Handler(onChange))
        var context = FSEventStreamContext(version: 0, info: handler.toOpaque(), retain: nil,
            release: { pointer in
                guard let pointer else { return }
                Unmanaged<Handler>.fromOpaque(pointer).release()
            }, copyDescription: nil)
        let callback: FSEventStreamCallback = { _, context, _, eventPaths, _, _ in
            guard let context else { return }
            let paths = unsafeBitCast(eventPaths, to: NSArray.self).compactMap { $0 as? String }
            // Selection/scroll journals are written frequently. Their own events
            // must not rescan note history and reload the library while scrolling.
            let relevant = paths.contains { path in
                let url = URL(fileURLWithPath: path)
                guard !url.pathComponents.contains(".current-recovery") else { return false }
                let name = url.lastPathComponent
                if name == ".current-library.json" || name == ".current-stream.json" { return true }
                return !name.hasPrefix(".")
            }
            guard relevant else { return }
            Unmanaged<Handler>.fromOpaque(context).takeUnretainedValue().action()
        }
        stream = FSEventStreamCreate(nil, callback, &context, [root.path] as CFArray,
                                    FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.35,
                                    FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagWatchRoot | kFSEventStreamCreateFlagUseCFTypes))
        guard let stream else { handler.release(); return }
        FSEventStreamSetDispatchQueue(stream, DispatchQueue.global(qos: .utility))
        if !FSEventStreamStart(stream) { stop() }
    }

    func stop() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    deinit { stop() }
}
