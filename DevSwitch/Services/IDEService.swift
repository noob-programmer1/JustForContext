import AppKit
import Foundation

/// Detects running IDEs and captures/restores their project state.
enum IDEService {

    // MARK: - IDE Registry

    enum IDE: String, CaseIterable, Sendable {
        case xcode = "com.apple.dt.Xcode"
        case vscode = "com.microsoft.VSCode"
        case cursor = "com.todesktop.230313mzl4w4u92"
        case androidStudio = "com.google.android.studio"
        case intellij = "com.jetbrains.intellij"
        case intellijCE = "com.jetbrains.intellij.ce"

        var displayName: String {
            switch self {
            case .xcode: "Xcode"
            case .vscode: "VS Code"
            case .cursor: "Cursor"
            case .androidStudio: "Android Studio"
            case .intellij, .intellijCE: "IntelliJ IDEA"
            }
        }
    }

    // MARK: - Capture All

    static func captureAllIDEs() async -> [IDEState] {
        var states: [IDEState] = []

        for ide in IDE.allCases {
            let running = NSRunningApplication.runningApplications(withBundleIdentifier: ide.rawValue)
            guard !running.isEmpty else { continue }

            switch ide {
            case .xcode:
                states.append(contentsOf: captureXcode())
            case .vscode, .cursor:
                if let state = captureElectronIDE(ide) {
                    states.append(state)
                }
            case .androidStudio, .intellij, .intellijCE:
                states.append(contentsOf: captureJetBrainsIDE(ide))
            }
        }

        return states
    }

    // MARK: - Xcode (AppleScript → xcuserstate → DerivedData)

    private static func captureXcode() -> [IDEState] {
        // Primary: Ask Xcode directly which workspace documents are open.
        // This is the only reliable way to know what's CURRENTLY open.
        var projectPaths = findXcodeProjectsViaAppleScript()

        // Fallback 1: Recently modified xcuserstate files (tight 3-min window)
        if projectPaths.isEmpty {
            projectPaths = findXcodeProjectsViaUserState()
        }

        // Fallback 2: DerivedData info.plist
        if projectPaths.isEmpty {
            projectPaths = findXcodeProjectsViaDerivedData()
        }

        guard !projectPaths.isEmpty else { return [] }

        // Best-effort: get open source files via AppleScript (for display only)
        let openFiles = captureXcodeOpenFiles()

        return projectPaths.map { projectPath in
            let projectDir: String
            if projectPath.hasSuffix(".xcodeproj") || projectPath.hasSuffix(".xcworkspace") {
                projectDir = URL(fileURLWithPath: projectPath).deletingLastPathComponent().path
            } else {
                projectDir = projectPath
            }
            let branch = GitService.currentBranch(at: projectDir)
            let relevantFiles = openFiles.filter { $0.hasPrefix(projectDir) }

            return IDEState(
                bundleId: IDE.xcode.rawValue,
                appName: "Xcode",
                projectPath: projectPath,
                openFiles: relevantFiles,
                gitBranch: branch
            )
        }
    }

    /// Ask Xcode directly for its currently open workspace documents via AppleScript.
    /// This is the most reliable method — returns only what's actually open right now.
    private static func findXcodeProjectsViaAppleScript() -> [String] {
        let script = """
        tell application "Xcode"
            try
                set wsPaths to ""
                repeat with doc in workspace documents
                    set wsPaths to wsPaths & path of doc & "\\n"
                end repeat
                return wsPaths
            on error
                return ""
            end try
        end tell
        """
        let paths = runAppleScriptLines(script)
        guard !paths.isEmpty else { return [] }

        // Deduplicate: if a .xcworkspace is inside a .xcodeproj, prefer the .xcodeproj
        var result: [String] = []
        var seen = Set<String>()
        for path in paths {
            var normalized = path
            if normalized.hasSuffix("/project.xcworkspace") {
                normalized = String(normalized.dropLast("/project.xcworkspace".count))
            }
            if !seen.contains(normalized) {
                seen.insert(normalized)
                result.append(normalized)
            }
        }
        return result
    }

    /// Fallback: Find Xcode projects by scanning for recently modified `UserInterfaceState.xcuserstate` files.
    /// Uses a 10-minute window — broad enough to catch active projects, tight enough to exclude old ones.
    private static func findXcodeProjectsViaUserState() -> [String] {
        let home = HomeDirectory.path
        let searchDirs = [
            "\(home)/Documents",
            "\(home)/Desktop",
            "\(home)/Projects"
        ]

        let fm = FileManager.default
        let cutoff = Date().addingTimeInterval(-10 * 60) // 10 minutes
        var candidates: [(path: String, modDate: Date)] = []

        for searchDir in searchDirs {
            guard fm.fileExists(atPath: searchDir) else { continue }

            // Use find command for efficiency
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/find")
            process.arguments = [searchDir, "-name", "UserInterfaceState.xcuserstate",
                                 "-mmin", "-10", "-type", "f"]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = Pipe()

            guard (try? process.run()) != nil else { continue }
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: data, encoding: .utf8) else { continue }

            for line in output.split(separator: "\n") {
                let path = String(line)
                // Extract .xcodeproj or .xcworkspace path
                // Path format: /path/to/Project.xcodeproj/project.xcworkspace/xcuserdata/.../UserInterfaceState.xcuserstate
                // OR: /path/to/Project.xcworkspace/xcuserdata/.../UserInterfaceState.xcuserstate
                guard let range = path.range(of: "\\.xc(odeproj|workspace)", options: .regularExpression) else { continue }
                let endIdx = range.upperBound
                var projectPath = String(path[path.startIndex..<endIdx])

                // If it's a project.xcworkspace inside an .xcodeproj, use the .xcodeproj
                if projectPath.hasSuffix(".xcodeproj/project.xcworkspace") {
                    projectPath = String(projectPath.dropLast("/project.xcworkspace".count))
                }

                // Get modification time
                if let attrs = try? fm.attributesOfItem(atPath: path),
                   let modDate = attrs[.modificationDate] as? Date,
                   modDate > cutoff {
                    candidates.append((projectPath, modDate))
                }
            }
        }

        // Deduplicate and sort by most recent
        var seen = Set<String>()
        return candidates
            .sorted { $0.modDate > $1.modDate }
            .compactMap { candidate in
                guard !seen.contains(candidate.path) else { return nil }
                seen.insert(candidate.path)
                return candidate.path
            }
    }

    /// Fallback: Scan DerivedData for recently active Xcode projects.
    private static func findXcodeProjectsViaDerivedData() -> [String] {
        let home = HomeDirectory.path
        let derivedDataDir = "\(home)/Library/Developer/Xcode/DerivedData"
        let fm = FileManager.default

        guard let entries = try? fm.contentsOfDirectory(atPath: derivedDataDir) else { return [] }

        let cutoff = Date().addingTimeInterval(-30 * 60) // 30 minutes
        var projects: [String] = []

        for entry in entries {
            if entry.hasSuffix(".noindex") { continue }

            let dirPath = "\(derivedDataDir)/\(entry)"
            let plistPath = "\(dirPath)/info.plist"

            guard fm.fileExists(atPath: plistPath) else { continue }

            guard let attrs = try? fm.attributesOfItem(atPath: dirPath),
                  let modDate = attrs[.modificationDate] as? Date,
                  modDate > cutoff else { continue }

            guard let plistData = fm.contents(atPath: plistPath),
                  let plist = try? PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any],
                  let workspacePath = plist["WorkspacePath"] as? String else { continue }

            projects.append(workspacePath)
        }

        return projects
    }

    /// Best-effort capture of open source documents via AppleScript.
    private static func captureXcodeOpenFiles() -> [String] {
        let filesScript = """
        tell application "Xcode"
            try
                set docPaths to ""
                repeat with doc in source documents
                    set docPaths to docPaths & path of doc & "\\n"
                end repeat
                return docPaths
            on error
                return ""
            end try
        end tell
        """
        return runAppleScriptLines(filesScript)
    }

    // MARK: - VS Code / Cursor (filesystem + SQLite)

    private static func captureElectronIDE(_ ide: IDE) -> IDEState? {
        let appSupportName = ide == .vscode ? "Code" : "Cursor"
        let home = HomeDirectory.path
        let storageBase = "\(home)/Library/Application Support/\(appSupportName)/User/workspaceStorage"

        let fm = FileManager.default
        guard let hashDirs = try? fm.contentsOfDirectory(
            at: URL(fileURLWithPath: storageBase),
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: .skipsHiddenFiles
        ) else { return nil }

        // Find workspace.json files, pick most recently modified
        var candidates: [(dir: URL, modDate: Date, folderPath: String)] = []
        for dir in hashDirs {
            let wsJson = dir.appendingPathComponent("workspace.json")
            guard fm.fileExists(atPath: wsJson.path),
                  let data = try? Data(contentsOf: wsJson),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let folder = json["folder"] as? String else { continue }

            let attrs = try? fm.attributesOfItem(atPath: dir.path)
            let modDate = attrs?[.modificationDate] as? Date ?? .distantPast

            let folderPath: String
            if let url = URL(string: folder) {
                folderPath = url.path
            } else {
                folderPath = folder
            }

            candidates.append((dir, modDate, folderPath))
        }

        guard let newest = candidates.max(by: { $0.modDate < $1.modDate }) else { return nil }

        // Read open files from state.vscdb
        let openFiles = readVSCodeOpenFiles(from: newest.dir)
        let branch = GitService.currentBranch(at: newest.folderPath)

        return IDEState(
            bundleId: ide.rawValue,
            appName: ide.displayName,
            projectPath: newest.folderPath,
            openFiles: openFiles,
            gitBranch: branch
        )
    }

    private static func readVSCodeOpenFiles(from storageDir: URL) -> [String] {
        let dbPath = storageDir.appendingPathComponent("state.vscdb").path
        guard FileManager.default.fileExists(atPath: dbPath) else { return [] }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = [dbPath, "SELECT value FROM ItemTable WHERE key = 'history.entries' LIMIT 1;"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let jsonStr = String(data: data, encoding: .utf8),
                  let jsonData = jsonStr.data(using: .utf8),
                  let parsed = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                  let entries = parsed["entries"] as? [[String: Any]] else { return [] }

            return entries.compactMap { entry -> String? in
                guard let editor = entry["editor"] as? [String: Any],
                      let uri = editor["resource"] as? String,
                      let url = URL(string: uri) else { return nil }
                return url.path
            }.prefix(20).map { $0 }
        } catch {
            return []
        }
    }

    // MARK: - JetBrains / Android Studio

    private static func captureJetBrainsIDE(_ ide: IDE) -> [IDEState] {
        // Strategy 1: Use lsof to find project directories open by the IDE process
        let apps = NSRunningApplication.runningApplications(withBundleIdentifier: ide.rawValue)
        var projectPaths = findProjectsViaLsof(pids: apps.map(\.processIdentifier))

        // Strategy 2: Find projects with recently modified .idea/workspace.xml
        if projectPaths.isEmpty {
            projectPaths = findJetBrainsProjectsViaIdeaDir()
        }

        // Strategy 3: Fall back to recentProjects.xml
        if projectPaths.isEmpty {
            let home = HomeDirectory.path
            let configDirs = findJetBrainsConfigDirs(ide: ide, home: home)
            for configDir in configDirs {
                let recentPath = "\(configDir)/options/recentProjects.xml"
                if let paths = parseRecentProjectPaths(at: recentPath, home: home) {
                    projectPaths = paths
                    break
                }
            }
        }

        guard !projectPaths.isEmpty else { return [] }

        return projectPaths.compactMap { path in
            // Skip paths that don't look like project directories
            let fm = FileManager.default
            guard fm.fileExists(atPath: path) else { return nil }

            let branch = GitService.currentBranch(at: path)
            return IDEState(
                bundleId: ide.rawValue,
                appName: ide.displayName,
                projectPath: path,
                openFiles: [],
                gitBranch: branch
            )
        }
    }

    /// Use lsof to find user project directories open by IDE processes.
    private static func findProjectsViaLsof(pids: [pid_t]) -> [String] {
        guard !pids.isEmpty else { return [] }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/lsof")
        process.arguments = pids.flatMap { ["-p", "\($0)"] } + ["-Fn"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        guard (try? process.run()) != nil else { return [] }
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else { return [] }

        let home = HomeDirectory.path
        var projectDirs = Set<String>()

        for line in output.split(separator: "\n") {
            guard line.hasPrefix("n\(home)/Documents/") || line.hasPrefix("n\(home)/Desktop/") ||
                  line.hasPrefix("n\(home)/Projects/") else { continue }
            let path = String(line.dropFirst(1)) // drop 'n' prefix

            // Skip Library, gradle, sdk paths
            if path.contains("/.gradle/") || path.contains("/Library/") ||
               path.contains("/sdk/") || path.contains("/.build/") { continue }

            // Extract the project root: first 2 components after Documents/Desktop/Projects
            let components = path.split(separator: "/").map(String.init)
            // Find index of Documents/Desktop/Projects
            if let baseIdx = components.firstIndex(where: { $0 == "Documents" || $0 == "Desktop" || $0 == "Projects" }),
               baseIdx + 1 < components.count {
                // Project is the next 1-2 path components after base
                let projectDepth = min(baseIdx + 3, components.count) // up to 2 levels deep
                let projectPath = "/" + components[0..<projectDepth].joined(separator: "/")
                if FileManager.default.fileExists(atPath: projectPath) {
                    projectDirs.insert(projectPath)
                }
            }
        }

        return Array(projectDirs).sorted()
    }

    /// Find projects with recently modified .idea/workspace.xml — indicates actively open JetBrains project.
    private static func findJetBrainsProjectsViaIdeaDir() -> [String] {
        let home = HomeDirectory.path
        let searchDirs = ["\(home)/Documents", "\(home)/Desktop", "\(home)/Projects"]

        var candidates: [(path: String, modDate: Date)] = []
        let cutoff = Date().addingTimeInterval(-60 * 60) // 1 hour

        for searchDir in searchDirs {
            guard FileManager.default.fileExists(atPath: searchDir) else { continue }

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/find")
            process.arguments = [searchDir, "-path", "*/.idea/workspace.xml",
                                 "-mmin", "-60", "-type", "f", "-maxdepth", "4"]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = Pipe()

            guard (try? process.run()) != nil else { continue }
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: data, encoding: .utf8) else { continue }

            for line in output.split(separator: "\n") {
                let wsPath = String(line)
                // Project dir is parent of .idea/
                let projectDir = URL(fileURLWithPath: wsPath)
                    .deletingLastPathComponent() // workspace.xml -> .idea
                    .deletingLastPathComponent() // .idea -> project root
                    .path

                if let attrs = try? FileManager.default.attributesOfItem(atPath: wsPath),
                   let modDate = attrs[.modificationDate] as? Date,
                   modDate > cutoff {
                    candidates.append((projectDir, modDate))
                }
            }
        }

        // Return most recently modified first
        return candidates.sorted { $0.modDate > $1.modDate }.map(\.path)
    }

    /// Find JetBrains IDE config directories sorted by version (newest first).
    private static func findJetBrainsConfigDirs(ide: IDE, home: String) -> [String] {
        let fm = FileManager.default
        let searchPaths: [(base: String, prefix: String)]

        switch ide {
        case .androidStudio:
            searchPaths = [("\(home)/Library/Application Support/Google", "AndroidStudio")]
        case .intellij:
            searchPaths = [("\(home)/Library/Application Support/JetBrains", "IntelliJIdea")]
        case .intellijCE:
            searchPaths = [("\(home)/Library/Application Support/JetBrains", "IdeaIC")]
        default:
            return []
        }

        var dirs: [String] = []
        for (base, prefix) in searchPaths {
            guard let entries = try? fm.contentsOfDirectory(atPath: base) else { continue }
            for entry in entries where entry.hasPrefix(prefix) {
                dirs.append("\(base)/\(entry)")
            }
        }

        return dirs.sorted().reversed()
    }

    /// Parse recentProjects.xml to find the most recently opened project path.
    private static func parseRecentProjectPaths(at path: String, home: String) -> [String]? {
        guard FileManager.default.fileExists(atPath: path),
              let data = FileManager.default.contents(atPath: path),
              let doc = try? XMLDocument(data: data, options: []),
              let entries = try? doc.nodes(forXPath: "//entry") else { return nil }

        struct ProjectEntry {
            let path: String
            let timestamp: Int64
        }

        var projects: [ProjectEntry] = []
        for entry in entries {
            guard let element = entry as? XMLElement,
                  var key = element.attribute(forName: "key")?.stringValue else { continue }
            key = key.replacingOccurrences(of: "$USER_HOME$", with: home)

            if let tsNode = try? element.nodes(forXPath: ".//option[@name='activationTimestamp']").first as? XMLElement,
               let tsStr = tsNode.attribute(forName: "value")?.stringValue,
               let ts = Int64(tsStr) {
                projects.append(ProjectEntry(path: key, timestamp: ts))
            }
        }

        guard !projects.isEmpty else { return nil }
        projects.sort { $0.timestamp > $1.timestamp }
        return [projects.first!.path]
    }

    // MARK: - Restore

    static func restoreIDEs(_ states: [IDEState]) async {
        for state in states {
            guard let ide = IDE(rawValue: state.bundleId),
                  let projectPath = state.projectPath, !projectPath.isEmpty else { continue }

            switch ide {
            case .xcode:
                restoreViaOpen(path: projectPath)
            case .vscode:
                restoreViaCLI(command: "code", path: projectPath)
            case .cursor:
                restoreViaCLI(command: "cursor", path: projectPath)
            case .androidStudio:
                restoreViaOpenApp(appName: "Android Studio", path: projectPath)
            case .intellij, .intellijCE:
                restoreViaOpenApp(appName: "IntelliJ IDEA", path: projectPath)
            }
        }
    }

    /// Restore by `open <path>` — works for Xcode .xcodeproj/.xcworkspace
    private static func restoreViaOpen(path: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = [path]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try? process.run()
        process.waitUntilExit()
    }

    /// Restore by CLI: `code /folder` or `cursor /folder`
    private static func restoreViaCLI(command: String, path: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [command, path]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try? process.run()
        process.waitUntilExit()
    }

    /// Restore by `open -a "App Name" /path`
    private static func restoreViaOpenApp(appName: String, path: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-a", appName, path]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try? process.run()
        process.waitUntilExit()
    }

    // MARK: - AppleScript Helpers

    private static func runAppleScriptLines(_ source: String) -> [String] {
        var error: NSDictionary?
        guard let result = NSAppleScript(source: source)?.executeAndReturnError(&error),
              let output = result.stringValue else { return [] }
        return output.split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}
