import Foundation

/// Discovers Claude Code sessions and links them to workspaces by matching project paths.
@MainActor @Observable
final class ClaudeSessionService {
    var sessions: [LinkedClaudeSession] = []

    private var watcher: FSEventsWatcher?

    func startMonitoring() {
        watcher = FSEventsWatcher()

        Task {
            let discovered = await Self.discoverOnBackground()
            self.sessions = discovered
        }

        watcher?.start { _ in
            Task { @MainActor [weak self] in
                let discovered = await Self.discoverOnBackground()
                self?.sessions = discovered
            }
        }
    }

    func stopMonitoring() {
        watcher?.stop()
        watcher = nil
    }

    /// Get sessions matching a workspace by linked IDs or project path.
    func sessions(for workspace: Workspace) -> [LinkedClaudeSession] {
        let linkedIds = Set(workspace.linkedSessionIds)
        let encodedPath = workspace.encodedProjectPath

        var matched: [LinkedClaudeSession] = []
        var seenIds = Set<String>()

        for session in sessions {
            let matchesById = linkedIds.contains(session.id)
            let matchesByPath = !encodedPath.isEmpty && session.projectPath == encodedPath

            if (matchesById || matchesByPath) && !seenIds.contains(session.id) {
                seenIds.insert(session.id)
                matched.append(session)
            }
        }

        return matched.sorted { $0.lastActivityTime > $1.lastActivityTime }
    }

    /// Get all currently active session IDs.
    func activeSessionIds() -> [String] {
        sessions.filter(\.isActive).map(\.id)
    }

    /// Trigger a manual refresh.
    func refresh() {
        Task {
            let discovered = await Self.discoverOnBackground()
            self.sessions = discovered
        }
    }

    // MARK: - Static background discovery

    private static func discoverOnBackground() async -> [LinkedClaudeSession] {
        await Task.detached {
            let discovered = discoverSessionFiles()
            var updated: [LinkedClaudeSession] = []

            for (projectPath, sessionFile) in discovered {
                let sessionId = sessionFile.deletingPathExtension().lastPathComponent
                let metadata = extractSessionMetadata(from: sessionFile)
                guard metadata.hasRecords else { continue }

                let session = LinkedClaudeSession(
                    id: sessionId,
                    sessionId: metadata.sessionId,
                    projectPath: projectPath,
                    cwd: metadata.cwd,
                    model: metadata.model,
                    lastActivityTime: metadata.lastTime,
                    isActive: metadata.isActive,
                    totalTokens: metadata.totalTokens,
                    totalCost: metadata.totalCost
                )
                updated.append(session)
            }

            return updated.sorted { $0.lastActivityTime > $1.lastActivityTime }
        }.value
    }

    private nonisolated static func extractSessionMetadata(from fileURL: URL) -> SessionMetadata {
        var meta = SessionMetadata()

        if let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
           let modDate = attrs[.modificationDate] as? Date {
            meta.isActive = Date.now.timeIntervalSince(modDate) < 300
        }

        guard let fileHandle = try? FileHandle(forReadingFrom: fileURL) else { return meta }
        defer { try? fileHandle.close() }

        let fileSize = fileHandle.seekToEndOfFile()
        guard fileSize > 0 else { return meta }
        let readStart = fileSize > 65536 ? fileSize - 65536 : 0

        // Read first 4KB to get sessionId
        fileHandle.seek(toFileOffset: 0)
        let headData = fileHandle.readData(ofLength: min(4096, Int(fileSize)))
        let headText = String(data: headData, encoding: .utf8) ?? ""
        for line in headText.split(separator: "\n") {
            if let record = JSONLParser.parseLine(String(line)) {
                meta.hasRecords = true
                if meta.sessionId == nil, let sid = record.sessionId {
                    meta.sessionId = sid
                }
                if meta.cwd == nil, let cwd = record.cwd {
                    meta.cwd = cwd
                }
                if let ts = record.timestamp, ts > meta.lastTime {
                    meta.lastTime = ts
                }
                if meta.sessionId != nil, meta.cwd != nil { break }
            }
        }

        // Read tail for recent data
        fileHandle.seek(toFileOffset: readStart)
        let tailData = fileHandle.readDataToEndOfFile()
        guard let tailText = String(data: tailData, encoding: .utf8) else { return meta }

        for line in tailText.split(separator: "\n") {
            guard let record = JSONLParser.parseLine(String(line)) else { continue }
            meta.hasRecords = true

            if let ts = record.timestamp, ts > meta.lastTime {
                meta.lastTime = ts
            }
            if meta.sessionId == nil, let sid = record.sessionId {
                meta.sessionId = sid
            }
            if meta.cwd == nil, let cwd = record.cwd {
                meta.cwd = cwd
            }
            if record.type == .assistant {
                if let m = record.message?.model {
                    meta.model = m
                }
                if let usage = record.message?.usage {
                    meta.totalTokens += (usage.inputTokens ?? 0)
                        + (usage.outputTokens ?? 0)
                        + (usage.cacheReadInputTokens ?? 0)
                }
                if let cost = record.costUSD {
                    meta.totalCost += cost
                }
            }
        }

        return meta
    }

    /// Discover all JSONL session files from ~/.claude/projects/.
    /// Structure: ~/.claude/projects/<encoded-project-path>/<session-uuid>.jsonl
    private nonisolated static func discoverSessionFiles() -> [(projectPath: String, sessionFile: URL)] {
        var results: [(String, URL)] = []
        let fm = FileManager.default
        let home = URL(fileURLWithPath: HomeDirectory.path)

        let basePaths = [
            home.appendingPathComponent(".claude/projects"),
            home.appendingPathComponent(".config/claude/projects")
        ]

        for basePath in basePaths {
            guard let projectDirs = try? fm.contentsOfDirectory(
                at: basePath,
                includingPropertiesForKeys: nil,
                options: .skipsHiddenFiles
            ) else { continue }

            for projectDir in projectDirs {
                var isDir: ObjCBool = false
                guard fm.fileExists(atPath: projectDir.path, isDirectory: &isDir),
                      isDir.boolValue else { continue }

                // JSONL files are directly in the project directory
                guard let files = try? fm.contentsOfDirectory(
                    at: projectDir,
                    includingPropertiesForKeys: [.contentModificationDateKey],
                    options: .skipsHiddenFiles
                ) else { continue }

                for file in files where file.pathExtension == "jsonl" {
                    results.append((projectDir.lastPathComponent, file))
                }
            }
        }

        return results
    }
}

// MARK: - Session Metadata

private struct SessionMetadata: Sendable {
    var hasRecords = false
    var sessionId: String?
    var cwd: String?
    var model: String?
    var lastTime = Date.distantPast
    var totalTokens = 0
    var totalCost: Double = 0
    var isActive = false
}
