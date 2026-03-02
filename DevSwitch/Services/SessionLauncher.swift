import AppKit

/// Opens Claude Code sessions in Terminal.
enum SessionLauncher {
    /// Open a session. Uses the session's `cwd` (actual working directory from JSONL)
    /// as the most reliable path, with optional override from workspace.
    static func openInClaude(session: LinkedClaudeSession, projectDir: String? = nil) {
        let sessionId = session.sessionId ?? session.id
        let dir = projectDir ?? session.cwd ?? NSHomeDirectory()
        resumeInTerminal(sessionId: sessionId, projectDir: dir)
    }

    /// Open a session by raw ID + workspace project path.
    static func openBySessionId(_ sessionId: String, projectPath: String) {
        let dir = projectPath.isEmpty ? NSHomeDirectory() : projectPath
        resumeInTerminal(sessionId: sessionId, projectDir: dir)
    }

    private static func resumeInTerminal(sessionId: String, projectDir: String) {
        let escapedDir = projectDir.replacingOccurrences(of: "'", with: "'\\''")
        let escapedId = sessionId.replacingOccurrences(of: "'", with: "'\\''")

        let shellCmd = "cd '\(escapedDir)' && claude --resume '\(escapedId)'"
        let script = """
        tell application "Terminal"
            activate
            do script "\(shellCmd)"
        end tell
        """

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        try? process.run()
    }
}
