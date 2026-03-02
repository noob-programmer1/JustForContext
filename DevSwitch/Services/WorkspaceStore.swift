import Foundation

/// CRUD persistence for workspaces and snapshots using JSON files.
@MainActor @Observable
final class WorkspaceStore {
    var workspaces: [Workspace] = []
    private(set) var snapshots: [UUID: WorkspaceSnapshot] = [:]

    private let workspacesURL: URL
    private let snapshotsURL: URL

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("DevSwitch", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.workspacesURL = dir.appendingPathComponent("workspaces.json")
        self.snapshotsURL = dir.appendingPathComponent("snapshots.json")
        load()
    }

    // MARK: - CRUD

    func add(_ workspace: Workspace) {
        workspaces.append(workspace)
        save()
    }

    func update(_ workspace: Workspace) {
        guard let idx = workspaces.firstIndex(where: { $0.id == workspace.id }) else { return }
        workspaces[idx] = workspace
        save()
    }

    func delete(_ workspace: Workspace) {
        workspaces.removeAll { $0.id == workspace.id }
        snapshots.removeValue(forKey: workspace.id)
        save()
    }

    func setActive(_ workspace: Workspace) {
        for i in workspaces.indices {
            workspaces[i].isActive = (workspaces[i].id == workspace.id)
            if workspaces[i].id == workspace.id {
                workspaces[i].lastActiveAt = .now
            }
        }
        save()
    }

    var activeWorkspace: Workspace? {
        workspaces.first(where: \.isActive)
    }

    // MARK: - Snapshots

    func saveSnapshot(_ snapshot: WorkspaceSnapshot) {
        snapshots[snapshot.workspaceId] = snapshot
        saveSnapshots()
    }

    func snapshot(for workspaceId: UUID) -> WorkspaceSnapshot? {
        snapshots[workspaceId]
    }

    // MARK: - Persistence

    private func load() {
        if let data = try? Data(contentsOf: workspacesURL),
           let decoded = try? JSONDecoder().decode([Workspace].self, from: data) {
            workspaces = decoded
        }
        if let data = try? Data(contentsOf: snapshotsURL),
           let decoded = try? JSONDecoder().decode([UUID: WorkspaceSnapshot].self, from: data) {
            snapshots = decoded
        }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(workspaces) else { return }
        try? data.write(to: workspacesURL, options: .atomic)
    }

    private func saveSnapshots() {
        guard let data = try? JSONEncoder().encode(snapshots) else { return }
        try? data.write(to: snapshotsURL, options: .atomic)
    }
}
