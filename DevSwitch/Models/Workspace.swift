import Foundation

/// A developer workspace representing a project + branch context.
struct Workspace: Identifiable, Codable, Sendable {
    let id: UUID
    var name: String
    var projectPath: String
    var gitBranch: String?
    var notes: String
    var icon: String
    var color: String
    var createdAt: Date
    var lastActiveAt: Date
    var isActive: Bool
    var linkedSessionIds: [String]

    init(
        id: UUID = UUID(),
        name: String,
        projectPath: String,
        gitBranch: String? = nil,
        notes: String = "",
        icon: String = "folder.fill",
        color: String = "007AFF",
        createdAt: Date = .now,
        lastActiveAt: Date = .now,
        isActive: Bool = false,
        linkedSessionIds: [String] = []
    ) {
        self.id = id
        self.name = name
        self.projectPath = projectPath
        self.gitBranch = gitBranch
        self.notes = notes
        self.icon = icon
        self.color = color
        self.createdAt = createdAt
        self.lastActiveAt = lastActiveAt
        self.isActive = isActive
        self.linkedSessionIds = linkedSessionIds
    }

    // Backward-compatible decoder for existing saved workspaces
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        projectPath = try container.decode(String.self, forKey: .projectPath)
        gitBranch = try container.decodeIfPresent(String.self, forKey: .gitBranch)
        notes = try container.decodeIfPresent(String.self, forKey: .notes) ?? ""
        icon = try container.decode(String.self, forKey: .icon)
        color = try container.decode(String.self, forKey: .color)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        lastActiveAt = try container.decode(Date.self, forKey: .lastActiveAt)
        isActive = try container.decode(Bool.self, forKey: .isActive)
        linkedSessionIds = try container.decodeIfPresent([String].self, forKey: .linkedSessionIds) ?? []
    }

    /// The encoded project directory name used by Claude Code.
    /// "/Users/Abhi/Projects/myapp" → "-Users-Abhi-Projects-myapp"
    var encodedProjectPath: String {
        projectPath.replacingOccurrences(of: "/", with: "-")
    }

    /// Short display name from the project path.
    var projectName: String {
        URL(fileURLWithPath: projectPath).lastPathComponent
    }
}
