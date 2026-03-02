import AppKit

/// Captures and restores terminal tabs and their working directories.
enum TerminalService {

    // MARK: - Capture

    /// Capture terminal working directories from all terminal apps.
    static func captureAllTerminals() -> [TerminalTab] {
        var tabs: [TerminalTab] = []

        // Try AppleScript for Terminal.app
        if isAppRunning("Terminal") {
            tabs += captureViaAppleScript(app: "Terminal")
        }

        // Try AppleScript for iTerm2
        if isAppRunning("iTerm2") {
            tabs += captureViaAppleScript(app: "iTerm2")
        }

        // Fallback: find shell processes and their cwd
        if tabs.isEmpty {
            tabs = captureViaShellProcesses()
        }

        return tabs
    }

    // MARK: - Restore

    /// Restore all terminal tabs grouped by app.
    static func restoreAllTerminals(_ tabs: [TerminalTab]) {
        let terminalTabs = tabs.filter { $0.terminalApp == "Terminal" }
        let itermTabs = tabs.filter { $0.terminalApp == "iTerm2" }

        for (i, tab) in terminalTabs.enumerated() {
            let dir = tab.workingDirectory.replacingOccurrences(of: "'", with: "'\\''")
            let script: String
            if i == 0 {
                script = """
                tell application "Terminal"
                    activate
                    do script "cd '\(dir)'"
                end tell
                """
            } else {
                script = """
                tell application "Terminal"
                    tell application "System Events" to tell process "Terminal" to keystroke "t" using command down
                    delay 0.3
                    do script "cd '\(dir)'" in front window
                end tell
                """
            }
            var error: NSDictionary?
            NSAppleScript(source: script)?.executeAndReturnError(&error)
        }

        for (i, tab) in itermTabs.enumerated() {
            let dir = tab.workingDirectory.replacingOccurrences(of: "\"", with: "\\\"")
            let script: String
            if i == 0 {
                script = """
                tell application "iTerm2"
                    activate
                    tell current session of current tab of current window
                        write text "cd \\"\(dir)\\""
                    end tell
                end tell
                """
            } else {
                script = """
                tell application "iTerm2"
                    tell current window
                        create tab with default profile
                        tell current session of current tab
                            write text "cd \\"\(dir)\\""
                        end tell
                    end tell
                end tell
                """
            }
            var error: NSDictionary?
            NSAppleScript(source: script)?.executeAndReturnError(&error)
        }
    }

    // MARK: - Private

    private static func captureViaAppleScript(app: String) -> [TerminalTab] {
        if app == "iTerm2" {
            let script = """
            tell application "iTerm2"
                set dirList to ""
                repeat with w in windows
                    repeat with t in tabs of w
                        repeat with s in sessions of t
                            try
                                set dirList to dirList & (variable named "session.path" of s) & "\\n"
                            end try
                        end repeat
                    end repeat
                end repeat
                return dirList
            end tell
            """
            return parseAppleScriptOutput(script, app: "iTerm2")
        } else {
            // Terminal.app doesn't expose cwd directly — use lsof on its shell processes
            return captureTerminalAppDirs()
        }
    }

    /// Get Terminal.app shell working directories via lsof.
    private static func captureTerminalAppDirs() -> [TerminalTab] {
        // Find bash/zsh processes whose parent is Terminal
        let script = """
        /bin/ps -eo pid,ppid,comm | /usr/bin/grep -E '(bash|zsh|fish)$' | while read pid ppid comm; do
            parent_name=$(/bin/ps -p $ppid -o comm= 2>/dev/null)
            if echo "$parent_name" | /usr/bin/grep -q -i terminal; then
                /usr/sbin/lsof -p $pid -a -d cwd -Fn 2>/dev/null | /usr/bin/grep '^n' | /usr/bin/sed 's/^n//'
            fi
        done | /usr/bin/sort -u
        """

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", script]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            return output.split(separator: "\n")
                .map(String.init)
                .filter { !$0.isEmpty && $0 != "/" && $0 != NSHomeDirectory() }
                .map { TerminalTab(workingDirectory: $0, terminalApp: "Terminal") }
        } catch {
            return []
        }
    }

    /// Fallback: find any shell processes with non-home cwds.
    private static func captureViaShellProcesses() -> [TerminalTab] {
        let script = """
        /bin/ps -eo pid,comm | /usr/bin/grep -E '(bash|zsh|fish)$' | /usr/bin/awk '{print $1}' | while read pid; do
            /usr/sbin/lsof -p $pid -a -d cwd -Fn 2>/dev/null | /usr/bin/grep '^n' | /usr/bin/sed 's/^n//'
        done | /usr/bin/sort -u
        """

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", script]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            return output.split(separator: "\n")
                .map(String.init)
                .filter { !$0.isEmpty && $0 != "/" && $0 != NSHomeDirectory() }
                .map { TerminalTab(workingDirectory: $0, terminalApp: "Terminal") }
        } catch {
            return []
        }
    }

    private static func parseAppleScriptOutput(_ script: String, app: String) -> [TerminalTab] {
        var error: NSDictionary?
        guard let result = NSAppleScript(source: script)?.executeAndReturnError(&error),
              let output = result.stringValue else {
            return []
        }
        return output.split(separator: "\n")
            .map(String.init)
            .filter { !$0.isEmpty }
            .map { TerminalTab(workingDirectory: $0, terminalApp: app) }
    }

    private static func isAppRunning(_ name: String) -> Bool {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleId(for: name)) != nil
            && !NSRunningApplication.runningApplications(withBundleIdentifier: bundleId(for: name)).isEmpty
    }

    private static func bundleId(for app: String) -> String {
        switch app {
        case "Terminal": return "com.apple.Terminal"
        case "iTerm2": return "com.googlecode.iterm2"
        default: return ""
        }
    }
}
