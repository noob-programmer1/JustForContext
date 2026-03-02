import Foundation

/// Represents the captured state of a running IDE.
struct IDEState: Codable, Sendable, Identifiable {
    var id: String { bundleId + (projectPath ?? "") }

    let bundleId: String       // "com.apple.dt.Xcode"
    let appName: String        // "Xcode"
    let projectPath: String?   // Project/workspace path open in the IDE
    let openFiles: [String]    // File paths currently open (for display)
    let gitBranch: String?     // Git branch at capture time
}
