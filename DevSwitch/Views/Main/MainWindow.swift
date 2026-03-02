import SwiftUI

/// Main window with NavigationSplitView: workspace sidebar + detail pane.
struct MainWindow: View {
    @Bindable var viewModel: WorkspaceListViewModel
    @Environment(\.openWindow) private var openWindow
    @State private var showDeleteAlert = false
    @State private var workspaceToDelete: Workspace?

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
        }
        .navigationTitle("")
        .alert("Delete Workspace?", isPresented: $showDeleteAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                if let ws = workspaceToDelete {
                    viewModel.deleteWorkspace(ws)
                }
            }
        } message: {
            if let ws = workspaceToDelete {
                Text("Are you sure you want to delete \"\(ws.name)\"? This cannot be undone.")
            }
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        List(selection: $viewModel.selectedWorkspaceId) {
            Section("Workspaces") {
                ForEach(viewModel.filteredWorkspaces) { workspace in
                    WorkspaceRow(workspace: workspace, sessionCount: viewModel.sessions(for: workspace).count)
                        .tag(workspace.id)
                        .contextMenu {
                            Button("Switch to This") { viewModel.switchTo(workspace) }
                            Divider()
                            Button("Delete", role: .destructive) {
                                workspaceToDelete = workspace
                                showDeleteAlert = true
                            }
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                workspaceToDelete = workspace
                                showDeleteAlert = true
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                }
            }

            // All sessions section in sidebar
            if !viewModel.sessionService.sessions.isEmpty {
                Section("All Sessions (\(viewModel.sessionService.sessions.count))") {
                    ForEach(viewModel.sessionService.sessions.prefix(20)) { session in
                        SidebarSessionRow(session: session)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .frame(minWidth: 240)
        .searchable(text: $viewModel.searchText, prompt: "Search workspaces")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    openWindow(id: "save-context")
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
    }

    // MARK: - Detail

    @ViewBuilder
    private var detail: some View {
        if let workspace = viewModel.selectedWorkspace {
            WorkspaceDetailView(
                workspace: workspace,
                sessions: viewModel.sessions(for: workspace),
                allSessions: viewModel.sessionService.sessions,
                store: viewModel.store,
                onRestore: {
                    viewModel.restoreContext(for: workspace)
                },
                onDelete: {
                    workspaceToDelete = workspace
                    showDeleteAlert = true
                }
            )
        } else {
            ContentUnavailableView(
                "Select a Workspace",
                systemImage: "rectangle.stack",
                description: Text("Choose a workspace from the sidebar or create a new one.")
            )
        }
    }
}

// MARK: - Sidebar Session Row

private struct SidebarSessionRow: View {
    let session: LinkedClaudeSession

    var body: some View {
        Button {
            SessionLauncher.openInClaude(session: session)
        } label: {
            HStack(spacing: 6) {
                Circle()
                    .fill(session.isActive ? Color.green : Color.gray.opacity(0.3))
                    .frame(width: 6, height: 6)

                VStack(alignment: .leading, spacing: 1) {
                    Text(session.projectName)
                        .font(.system(size: 11, weight: .medium))
                        .lineLimit(1)
                    HStack(spacing: 3) {
                        Text(session.shortModel)
                        Text("·")
                        Text(session.formattedCost)
                        Text("·")
                        Text(session.lastActivityTime, style: .relative)
                    }
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                }
            }
        }
        .buttonStyle(.plain)
    }
}
