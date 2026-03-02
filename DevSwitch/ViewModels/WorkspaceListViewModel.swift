import SwiftUI

/// ViewModel for the workspace list — used in both menubar popover and main window sidebar.
@MainActor @Observable
final class WorkspaceListViewModel {
    let store = WorkspaceStore()
    let sessionService = ClaudeSessionService()

    var searchText = ""
    var showSaveContextSheet = false
    var selectedWorkspaceId: UUID?
    var isSwitching = false
    var lastSwitchResult: ContextSwitcher.SwitchResult?

    var filteredWorkspaces: [Workspace] {
        if searchText.isEmpty {
            return store.workspaces.sorted { $0.lastActiveAt > $1.lastActiveAt }
        }
        return store.workspaces
            .filter { $0.name.localizedCaseInsensitiveContains(searchText)
                || $0.projectPath.localizedCaseInsensitiveContains(searchText) }
            .sorted { $0.lastActiveAt > $1.lastActiveAt }
    }

    var selectedWorkspace: Workspace? {
        guard let id = selectedWorkspaceId else { return nil }
        return store.workspaces.first { $0.id == id }
    }

    func start() {
        sessionService.startMonitoring()
        refreshBranches()
    }

    func stop() {
        sessionService.stopMonitoring()
    }

    /// Full context switch: save current, switch git, restore target.
    func switchTo(_ workspace: Workspace) {
        guard !isSwitching else { return }
        isSwitching = true

        let current = store.activeWorkspace
        selectedWorkspaceId = workspace.id

        Task {
            let result = await ContextSwitcher.switchWorkspace(
                from: current,
                to: workspace,
                store: store
            )
            lastSwitchResult = result
            isSwitching = false
            refreshBranches()
        }
    }

    /// Restore context for the active workspace without saving first.
    func restoreContext(for workspace: Workspace) {
        guard !isSwitching else { return }
        isSwitching = true

        Task {
            let result = await ContextSwitcher.restoreWorkspace(
                workspace,
                store: store
            )
            lastSwitchResult = result
            isSwitching = false
        }
    }

    /// Quick activate without full context switch (just marks active).
    func quickActivate(_ workspace: Workspace) {
        store.setActive(workspace)
        selectedWorkspaceId = workspace.id
    }

    // MARK: - Permissions

    var hasAccessibilityPermission: Bool {
        ContextSwitcher.hasAccessibilityPermission()
    }

    func requestAccessibilityPermission() {
        ContextSwitcher.requestAccessibilityPermission()
    }

    func deleteWorkspace(_ workspace: Workspace) {
        if selectedWorkspaceId == workspace.id {
            selectedWorkspaceId = nil
        }
        store.delete(workspace)
    }

    func sessions(for workspace: Workspace) -> [LinkedClaudeSession] {
        sessionService.sessions(for: workspace)
    }

    /// Refresh branches only for workspaces that don't have one set.
    /// Workspaces with an explicit branch keep it (that's what gets checked out on switch).
    func refreshBranches() {
        for i in store.workspaces.indices {
            if store.workspaces[i].gitBranch == nil || store.workspaces[i].gitBranch?.isEmpty == true {
                if let branch = GitService.currentBranch(at: store.workspaces[i].projectPath) {
                    store.workspaces[i].gitBranch = branch
                }
            }
        }
    }

    /// Save current workspace's context snapshot without switching.
    func saveCurrentContext() {
        guard let current = store.activeWorkspace else { return }
        Task {
            let snapshot = await ContextSwitcher.captureContext(for: current)
            store.saveSnapshot(snapshot)
        }
    }

    /// Create a new workspace AND immediately capture the current context.
    func createAndSaveWorkspace(
        name: String,
        projectPath: String,
        gitBranch: String? = nil,
        notes: String = "",
        icon: String,
        color: String
    ) async {
        let branch = gitBranch ?? GitService.currentBranch(at: projectPath)

        // Link all currently active Claude sessions
        let activeIds = sessionService.activeSessionIds()

        let workspace = Workspace(
            name: name,
            projectPath: projectPath,
            gitBranch: branch,
            notes: notes,
            icon: icon,
            color: color,
            linkedSessionIds: activeIds
        )
        store.add(workspace)
        store.setActive(workspace)
        selectedWorkspaceId = workspace.id

        // Immediately capture current context
        let snapshot = await ContextSwitcher.captureContext(for: workspace)
        store.saveSnapshot(snapshot)
    }

    /// Update an existing workspace's snapshot with the current context.
    func updateWorkspaceContext(workspaceId: UUID) async {
        guard var workspace = store.workspaces.first(where: { $0.id == workspaceId }) else { return }

        // Update git branch to current
        if let branch = GitService.currentBranch(at: workspace.projectPath) {
            workspace.gitBranch = branch
        }

        // Link all currently active Claude sessions (merge with existing)
        let activeIds = sessionService.activeSessionIds()
        let merged = Array(Set(workspace.linkedSessionIds + activeIds))
        workspace.linkedSessionIds = merged
        workspace.lastActiveAt = .now
        store.update(workspace)

        // Capture and save snapshot
        let snapshot = await ContextSwitcher.captureContext(for: workspace)
        store.saveSnapshot(snapshot)
    }
}
