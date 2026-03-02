import Foundation
import CoreServices

/// Monitors Claude Code's JSONL session directories using FSEvents.
final class FSEventsWatcher: @unchecked Sendable {
    typealias ChangeHandler = @Sendable ([String]) -> Void

    private var stream: FSEventStreamRef?
    private let paths: [String]
    private let latency: CFTimeInterval
    private var handlerPointer: UnsafeMutablePointer<ChangeHandler>?
    private let eventQueue = DispatchQueue(label: "com.devswitch.fsevents", qos: .utility)

    /// Directories to monitor for JSONL changes.
    @MainActor
    static var defaultPaths: [String] {
        let home = HomeDirectory.path
        var paths: [String] = []

        let primaryPath = "\(home)/.claude/projects"
        if FileManager.default.fileExists(atPath: primaryPath) {
            paths.append(primaryPath)
        }

        let legacyPath = "\(home)/.config/claude/projects"
        if FileManager.default.fileExists(atPath: legacyPath) {
            paths.append(legacyPath)
        }

        return paths
    }

    @MainActor
    init(paths: [String]? = nil, latency: CFTimeInterval = 2.0) {
        self.paths = paths ?? Self.defaultPaths
        self.latency = latency
    }

    func start(onChange: @escaping ChangeHandler) {
        guard !paths.isEmpty else { return }

        let wrappedHandler: ChangeHandler = { paths in
            let jsonlPaths = paths.filter { $0.hasSuffix(".jsonl") }
            if !jsonlPaths.isEmpty {
                onChange(jsonlPaths)
            }
        }

        let cfPaths = paths as CFArray
        var context = FSEventStreamContext()
        let ptr = UnsafeMutablePointer<ChangeHandler>.allocate(capacity: 1)
        ptr.initialize(to: wrappedHandler)
        self.handlerPointer = ptr
        context.info = UnsafeMutableRawPointer(ptr)

        let callback: FSEventStreamCallback = { _, clientCallBackInfo, _, eventPaths, _, _ in
            guard let info = clientCallBackInfo else { return }
            let handler = info.assumingMemoryBound(to: (@Sendable ([String]) -> Void).self).pointee
            let paths = Unmanaged<CFArray>.fromOpaque(eventPaths).takeUnretainedValue() as! [String]
            handler(paths)
        }

        stream = FSEventStreamCreate(
            nil,
            callback,
            &context,
            cfPaths,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            latency,
            UInt32(
                kFSEventStreamCreateFlagUseCFTypes |
                kFSEventStreamCreateFlagFileEvents
            )
        )

        if let stream {
            FSEventStreamSetDispatchQueue(stream, eventQueue)
            FSEventStreamStart(stream)
        }
    }

    func stop() {
        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            self.stream = nil
        }
        if let handlerPointer {
            handlerPointer.deinitialize(count: 1)
            handlerPointer.deallocate()
            self.handlerPointer = nil
        }
    }
}
