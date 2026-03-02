import SwiftUI

/// Detail pane showing workspace info, linked Claude sessions, and notes.
struct WorkspaceDetailView: View {
    let workspace: Workspace
    let sessions: [LinkedClaudeSession]
    let allSessions: [LinkedClaudeSession]
    let store: WorkspaceStore
    var onRestore: () -> Void
    var onDelete: () -> Void

    @State private var editedNotes: String = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                headerSection
                sessionSection
                snapshotSection
                notesSection
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear { editedNotes = workspace.notes }
        .onChange(of: workspace.id) { _, _ in editedNotes = workspace.notes }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Image(systemName: workspace.icon)
                    .font(.system(size: 28))
                    .foregroundStyle(Color(hex: workspace.color) ?? .blue)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(workspace.name)
                            .font(.title2.bold())

                        if workspace.isActive {
                            Text("ACTIVE")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.green, in: Capsule())
                        }

                        Spacer()

                        Button(role: .destructive) {
                            onDelete()
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 12))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.red.opacity(0.6))
                        .help("Delete workspace")
                    }

                    HStack(spacing: 12) {
                        if let branch = workspace.gitBranch {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.triangle.branch")
                                Text(branch)
                            }
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.orange.opacity(0.1), in: Capsule())
                        }

                        Label(workspace.projectPath, systemImage: "folder")
                            .font(.system(size: 12))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            }
        }
    }

    // MARK: - Sessions

    private var sessionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Claude Sessions")
                    .font(.headline)
                Text("(\(sessions.count))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
            }

            if sessions.isEmpty {
                HStack {
                    Spacer()
                    VStack(spacing: 6) {
                        Image(systemName: "bubble.left.and.text.bubble.right")
                            .font(.system(size: 24))
                            .foregroundStyle(.tertiary)
                        Text("No sessions linked to this workspace")
                            .font(.system(size: 12))
                            .foregroundStyle(.tertiary)
                        Text("Sessions are matched by project path: \(workspace.encodedProjectPath)")
                            .font(.system(size: 10))
                            .foregroundStyle(.quaternary)
                            .lineLimit(2)
                    }
                    .padding(.vertical, 16)
                    Spacer()
                }
                .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
            } else {
                ForEach(sessions) { session in
                    ClaudeSessionRow(session: session)
                }
            }
        }
    }

    // MARK: - Snapshot

    private var snapshotSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Context Snapshot")
                .font(.headline)

            if let snapshot = store.snapshot(for: workspace.id) {
                VStack(alignment: .leading, spacing: 10) {
                    // Summary stats + restore button
                    HStack(spacing: 16) {
                        snapshotStat(
                            icon: "chevron.left.forwardslash.chevron.right",
                            label: "IDEs",
                            count: snapshot.ideStates.count
                        )
                        snapshotStat(
                            icon: "macwindow.on.rectangle",
                            label: "Windows",
                            count: snapshot.windowStates.count
                        )
                        snapshotStat(
                            icon: "globe",
                            label: "Tabs",
                            count: snapshot.browserTabs.count
                        )
                        snapshotStat(
                            icon: "terminal",
                            label: "Terminals",
                            count: snapshot.terminalTabs.count
                        )
                        Spacer()
                        Button("Restore Context") {
                            onRestore()
                        }
                        .font(.system(size: 11, weight: .medium))
                    }

                    // IDE Projects
                    if !snapshot.ideStates.isEmpty {
                        Divider()
                        Text("IDE Projects")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)

                        ForEach(snapshot.ideStates) { ide in
                            HStack(spacing: 8) {
                                Image(systemName: "chevron.left.forwardslash.chevron.right")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 14)
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 6) {
                                        Text(ide.appName)
                                            .font(.system(size: 11, weight: .medium))
                                        if let branch = ide.gitBranch {
                                            HStack(spacing: 2) {
                                                Image(systemName: "arrow.triangle.branch")
                                                    .font(.system(size: 9))
                                                Text(branch)
                                            }
                                            .font(.system(size: 10))
                                            .foregroundStyle(.orange)
                                        }
                                    }
                                    if let path = ide.projectPath {
                                        Text(path)
                                            .font(.system(size: 10))
                                            .foregroundStyle(.tertiary)
                                            .lineLimit(1)
                                            .truncationMode(.middle)
                                    }
                                    if !ide.openFiles.isEmpty {
                                        Text("\(ide.openFiles.count) open file\(ide.openFiles.count == 1 ? "" : "s")")
                                            .font(.system(size: 9))
                                            .foregroundStyle(.quaternary)
                                    }
                                }
                                Spacer()
                            }
                        }
                    }

                    // Other apps
                    if !snapshot.windowStates.isEmpty {
                        Divider()
                        let uniqueApps = uniqueAppsFromSnapshot(snapshot)
                        ForEach(uniqueApps, id: \.bundleId) { app in
                            HStack(spacing: 8) {
                                Image(systemName: "macwindow")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 14)
                                Text(app.name)
                                    .font(.system(size: 11, weight: .medium))
                                Text("\(app.windowCount) window\(app.windowCount == 1 ? "" : "s")")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.tertiary)
                                Spacer()
                            }
                        }
                    }

                    Text("Captured \(snapshot.capturedAt, style: .relative) ago")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
                .padding(12)
                .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
            } else {
                Text("No snapshot captured yet. Switch away from this workspace to save context.")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private func uniqueAppsFromSnapshot(_ snapshot: WorkspaceSnapshot) -> [(bundleId: String, name: String, windowCount: Int)] {
        var counts: [String: (name: String, count: Int)] = [:]
        for ws in snapshot.windowStates {
            guard !ws.appBundleId.isEmpty else { continue }
            if let existing = counts[ws.appBundleId] {
                counts[ws.appBundleId] = (existing.name, existing.count + 1)
            } else {
                counts[ws.appBundleId] = (ws.appName, 1)
            }
        }
        return counts.map { (bundleId: $0.key, name: $0.value.name, windowCount: $0.value.count) }
            .sorted { $0.name < $1.name }
    }

    private func snapshotStat(icon: String, label: String, count: Int) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(.secondary)
            Text("\(count)")
                .font(.system(size: 14, weight: .semibold, design: .monospaced))
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Notes

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Notes")
                .font(.headline)

            TextEditor(text: $editedNotes)
                .font(.system(size: 12))
                .frame(minHeight: 80)
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
                .onChange(of: editedNotes) { _, newValue in
                    var updated = workspace
                    updated.notes = newValue
                    store.update(updated)
                }
        }
    }
}
