import Foundation

/// A captured snapshot of the full workspace context.
struct WorkspaceSnapshot: Codable, Sendable {
    let workspaceId: UUID
    let capturedAt: Date
    var windowStates: [WindowState]
    var browserTabs: [BrowserTab]
    var terminalTabs: [TerminalTab]
    var ideStates: [IDEState]

    init(
        workspaceId: UUID,
        capturedAt: Date = .now,
        windowStates: [WindowState] = [],
        browserTabs: [BrowserTab] = [],
        terminalTabs: [TerminalTab] = [],
        ideStates: [IDEState] = []
    ) {
        self.workspaceId = workspaceId
        self.capturedAt = capturedAt
        self.windowStates = windowStates
        self.browserTabs = browserTabs
        self.terminalTabs = terminalTabs
        self.ideStates = ideStates
    }

    // Custom decoder so existing saved snapshots without ideStates still load.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        workspaceId = try container.decode(UUID.self, forKey: .workspaceId)
        capturedAt = try container.decode(Date.self, forKey: .capturedAt)
        windowStates = try container.decode([WindowState].self, forKey: .windowStates)
        browserTabs = try container.decode([BrowserTab].self, forKey: .browserTabs)
        terminalTabs = try container.decode([TerminalTab].self, forKey: .terminalTabs)
        ideStates = try container.decodeIfPresent([IDEState].self, forKey: .ideStates) ?? []
    }
}

/// Position and size of a window.
struct WindowState: Codable, Sendable {
    let appBundleId: String
    let appName: String
    let windowTitle: String
    let x: Double
    let y: Double
    let width: Double
    let height: Double
}

/// A browser tab (Safari or Chrome).
struct BrowserTab: Codable, Sendable {
    let browser: String
    let url: String
    let title: String
}

/// A terminal tab with its working directory.
struct TerminalTab: Codable, Sendable {
    let workingDirectory: String
    let terminalApp: String
}
