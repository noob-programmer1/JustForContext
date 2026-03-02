import Foundation

/// Tracks the last-read byte offset for each JSONL file.
/// Ensures we only read NEW lines appended since last check.
/// Persists offsets to disk so they survive app restarts.
actor FileOffsetTracker {
    private var offsets: [String: UInt64] = [:]
    private let storageURL: URL

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("DevSwitch", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.storageURL = dir.appendingPathComponent("file_offsets.json")
        self.offsets = Self.loadOffsets(from: storageURL)
    }

    func offset(for path: String) -> UInt64 {
        offsets[path] ?? 0
    }

    func setOffset(_ offset: UInt64, for path: String) {
        offsets[path] = offset
    }

    func save() {
        let stringOffsets = offsets.mapValues { String($0) }
        guard let data = try? JSONEncoder().encode(stringOffsets) else { return }
        try? data.write(to: storageURL, options: .atomic)
    }

    func pruneStaleEntries() {
        let fm = FileManager.default
        offsets = offsets.filter { fm.fileExists(atPath: $0.key) }
    }

    func resetAll() {
        offsets.removeAll()
        try? FileManager.default.removeItem(at: storageURL)
    }

    private static func loadOffsets(from url: URL) -> [String: UInt64] {
        guard let data = try? Data(contentsOf: url),
              let stringOffsets = try? JSONDecoder().decode([String: String].self, from: data) else {
            return [:]
        }
        return stringOffsets.compactMapValues { UInt64($0) }
    }
}
