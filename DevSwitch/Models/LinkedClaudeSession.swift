import Foundation

/// A Claude Code session linked to a workspace by matching project paths.
struct LinkedClaudeSession: Identifiable, Codable, Sendable {
    let id: String                      // JSONL filename (session UUID)
    let sessionId: String?              // sessionId from JSONL records
    let projectPath: String             // URL-encoded project directory name
    let cwd: String?                    // Actual working directory from JSONL (reliable)
    let projectName: String
    let model: String?
    let lastActivityTime: Date
    let isActive: Bool
    let totalTokens: Int
    let totalCost: Double
    var summary: String?                // User-editable label like "OAuth login flow"

    init(
        id: String,
        sessionId: String? = nil,
        projectPath: String,
        cwd: String? = nil,
        projectName: String? = nil,
        model: String? = nil,
        lastActivityTime: Date = .distantPast,
        isActive: Bool = false,
        totalTokens: Int = 0,
        totalCost: Double = 0,
        summary: String? = nil
    ) {
        self.id = id
        self.sessionId = sessionId
        self.projectPath = projectPath
        self.cwd = cwd
        self.projectName = projectName ?? Self.resolveProjectName(cwd: cwd, encodedPath: projectPath)
        self.model = model
        self.lastActivityTime = lastActivityTime
        self.isActive = isActive
        self.totalTokens = totalTokens
        self.totalCost = totalCost
        self.summary = summary
    }

    /// Resolves project name: prefer `cwd` (actual path), fall back to encoded path.
    static func resolveProjectName(cwd: String?, encodedPath: String) -> String {
        if let cwd, !cwd.isEmpty {
            return URL(fileURLWithPath: cwd).lastPathComponent
        }
        let decoded = encodedPath
            .replacingOccurrences(of: "-", with: "/")
            .removingPercentEncoding ?? encodedPath
        let components = decoded.split(separator: "/").filter { !$0.isEmpty }
        return components.last.map(String.init) ?? encodedPath
    }

    var formattedTokens: String {
        if totalTokens >= 1_000_000 {
            return String(format: "%.1fM", Double(totalTokens) / 1_000_000)
        } else if totalTokens >= 1_000 {
            return String(format: "%.0fK", Double(totalTokens) / 1_000)
        }
        return "\(totalTokens)"
    }

    var formattedCost: String {
        if totalCost >= 100 {
            return String(format: "$%.0f", totalCost)
        } else if totalCost >= 10 {
            return String(format: "$%.1f", totalCost)
        }
        return String(format: "$%.2f", totalCost)
    }

    var shortModel: String {
        guard let model else { return "—" }
        if model.contains("opus") { return "Opus" }
        if model.contains("sonnet") { return "Sonnet" }
        if model.contains("haiku") { return "Haiku" }
        return String(model.prefix(8))
    }
}
