import Foundation
import AppKit

/// Orchestrates the full context switch: save current → switch → restore target.
@MainActor
enum ContextSwitcher {

    struct SwitchResult {
        var savedSnapshot: WorkspaceSnapshot?
        var branchSwitched: Bool = false
        var idesRestored: Int = 0
        var windowsRestored: Int = 0
        var tabsRestored: Int = 0
        var terminalsRestored: Int = 0
        var error: String?
    }

    /// Perform a full context switch from the current workspace to the target.
    static func switchWorkspace(
        from current: Workspace?,
        to target: Workspace,
        store: WorkspaceStore
    ) async -> SwitchResult {
        var result = SwitchResult()

        // 1. SAVE current context (only if switching to a DIFFERENT workspace)
        if let current, current.id != target.id {
            // Record the current git branch on the workspace being saved
            if let actualBranch = GitService.currentBranch(at: current.projectPath) {
                var updated = current
                updated.gitBranch = actualBranch
                store.update(updated)
            }

            let snapshot = await captureContext(for: current)
            store.saveSnapshot(snapshot)
            result.savedSnapshot = snapshot
        }

        // 2. SWITCH git branch (only if different workspace AND same project path)
        if let current, current.id != target.id {
            if let branch = target.gitBranch, !branch.isEmpty {
                // Only switch if the target has the same project path (same repo, different branch)
                // or always switch if target has a branch set
                do {
                    try await GitService.checkout(branch: branch, at: target.projectPath)
                    result.branchSwitched = true
                } catch {
                    result.error = "Branch switch failed: \(error.localizedDescription)"
                }
            }
        }

        // 3. SET as active
        store.setActive(target)

        // 4. RESTORE target context
        if let snapshot = store.snapshot(for: target.id) {
            await restoreContext(from: snapshot, result: &result)
        }

        return result
    }

    /// Restore context for the already-active workspace (no save, no git switch).
    static func restoreWorkspace(
        _ workspace: Workspace,
        store: WorkspaceStore
    ) async -> SwitchResult {
        var result = SwitchResult()

        if let snapshot = store.snapshot(for: workspace.id) {
            await restoreContext(from: snapshot, result: &result)
        } else {
            result.error = "No saved context snapshot for this workspace."
        }

        return result
    }

    /// Capture the full context for a workspace.
    static func captureContext(for workspace: Workspace) async -> WorkspaceSnapshot {
        async let windows = Task.detached { WindowCaptureService.captureAllWindows() }.value
        async let tabs = Task.detached { BrowserService.captureAllTabs() }.value
        async let terminals = Task.detached { TerminalService.captureAllTerminals() }.value
        async let ides = Task.detached { await IDEService.captureAllIDEs() }.value

        return WorkspaceSnapshot(
            workspaceId: workspace.id,
            windowStates: await windows,
            browserTabs: await tabs,
            terminalTabs: await terminals,
            ideStates: await ides
        )
    }

    /// Restore context from a snapshot.
    static func restoreContext(from snapshot: WorkspaceSnapshot, result: inout SwitchResult) async {
        // 1. Restore IDEs first (they need time to launch and load projects)
        if !snapshot.ideStates.isEmpty {
            await IDEService.restoreIDEs(snapshot.ideStates)
            result.idesRestored = snapshot.ideStates.count
        }

        // 2. Launch remaining apps that aren't running
        if !snapshot.windowStates.isEmpty {
            launchMissingApps(from: snapshot.windowStates)
            // Brief delay to let apps launch
            try? await Task.sleep(for: .seconds(1))
            WindowCaptureService.restoreWindows(from: snapshot.windowStates)
            result.windowsRestored = snapshot.windowStates.count
        }

        // 3. Browser tabs
        if !snapshot.browserTabs.isEmpty {
            BrowserService.restoreAllTabs(snapshot.browserTabs)
            result.tabsRestored = snapshot.browserTabs.count
        }

        // 4. Terminal tabs
        if !snapshot.terminalTabs.isEmpty {
            TerminalService.restoreAllTerminals(snapshot.terminalTabs)
            result.terminalsRestored = snapshot.terminalTabs.count
        }
    }

    /// Launch apps that were in the snapshot but aren't currently running.
    private static func launchMissingApps(from windowStates: [WindowState]) {
        let uniqueBundleIds = Set(windowStates.map(\.appBundleId)).filter { !$0.isEmpty }

        for bundleId in uniqueBundleIds {
            let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId)
            if running.isEmpty {
                if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
                    let config = NSWorkspace.OpenConfiguration()
                    config.activates = false // Don't steal focus
                    NSWorkspace.shared.openApplication(at: url, configuration: config)
                }
            }
        }
    }

    // MARK: - Permission Checks

    /// Check if Accessibility permission is granted (needed for window repositioning).
    static func hasAccessibilityPermission() -> Bool {
        AXIsProcessTrusted()
    }

    /// Prompt user to grant Accessibility permission.
    static func requestAccessibilityPermission() {
        let promptKeyString = "AXTrustedCheckOptionPrompt"
        let options = [promptKeyString: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }
}
