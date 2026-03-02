import SwiftUI

/// Main popover content displayed when clicking the menubar icon.
struct PopoverView: View {
    @Bindable var viewModel: WorkspaceListViewModel
    @Environment(\.openWindow) private var openWindow
    @State private var showSaveContext = false

    var body: some View {
        if showSaveContext {
            InlineSaveContextView(viewModel: viewModel, isPresented: $showSaveContext)
                .frame(width: 340, height: 460)
        } else {
            VStack(spacing: 0) {
                header
                Divider()
                content
                Divider()
                footer
            }
            .frame(width: 340, height: 460)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "rectangle.stack.fill")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.blue)
            Text("JustForContext")
                .font(.system(size: 12, weight: .bold))

            Spacer()

            HStack(spacing: 2) {
                Button { viewModel.sessionService.refresh() } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 10))
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tertiary)
                .help("Refresh")

                Button { openWindow(id: "main") } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 9))
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tertiary)
                .help("Open main window")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Content

    private var content: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 0) {
                if viewModel.isSwitching {
                    switchingIndicator
                }

                // Workspaces
                if !viewModel.filteredWorkspaces.isEmpty {
                    sectionHeader("Workspaces", count: viewModel.filteredWorkspaces.count)

                    ForEach(viewModel.filteredWorkspaces) { workspace in
                        WorkspacePopoverRow(
                            workspace: workspace,
                            sessions: viewModel.sessions(for: workspace),
                            snapshot: viewModel.store.snapshot(for: workspace.id),
                            onSwitch: { viewModel.switchTo(workspace) },
                            onRestore: { viewModel.restoreContext(for: workspace) },
                            onDelete: { viewModel.deleteWorkspace(workspace) }
                        )
                    }
                }

                // Recent Claude Sessions
                if !viewModel.sessionService.sessions.isEmpty {
                    if !viewModel.filteredWorkspaces.isEmpty {
                        Divider().padding(.horizontal, 12).padding(.vertical, 4)
                    }
                    sectionHeader("Recent Claude Sessions", count: viewModel.sessionService.sessions.count)

                    ForEach(viewModel.sessionService.sessions.prefix(6)) { session in
                        RecentSessionRow(session: session)
                    }

                    if viewModel.sessionService.sessions.count > 6 {
                        Button { openWindow(id: "main") } label: {
                            Text("View all \(viewModel.sessionService.sessions.count) sessions")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.blue)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 5)
                        }
                        .buttonStyle(.plain)
                    }
                }

                if viewModel.filteredWorkspaces.isEmpty && viewModel.sessionService.sessions.isEmpty {
                    emptyState
                }
            }
            .padding(.vertical, 2)
        }
    }

    private var switchingIndicator: some View {
        HStack(spacing: 6) {
            ProgressView()
                .scaleEffect(0.5)
            Text("Switching...")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
    }

    private func sectionHeader(_ title: String, count: Int) -> some View {
        HStack(spacing: 5) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)

            Text("\(count)")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(.quaternary.opacity(0.6), in: Capsule())

            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
        .padding(.bottom, 3)
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Spacer()
            Image(systemName: "square.stack.3d.up")
                .font(.system(size: 24))
                .foregroundStyle(.quaternary)
            Text("No workspaces yet")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            Text("Save your current context to get started")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 0) {
            Button {
                showSaveContext = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 11))
                    Text("Save Context")
                        .font(.system(size: 11, weight: .semibold))
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)

            Spacer()

            HStack(spacing: 2) {
                Button {
                    if let url = URL(string: "https://buymeacoffee.com/noob_programmer") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Image(systemName: "cup.and.saucer.fill")
                        .font(.system(size: 10))
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.orange)
                .help("Buy me a coffee")

                Button { NSApplication.shared.terminate(nil) } label: {
                    Image(systemName: "power")
                        .font(.system(size: 10))
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tertiary)
                .help("Quit JustForContext")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
    }
}

// MARK: - Workspace Row

private struct WorkspacePopoverRow: View {
    let workspace: Workspace
    let sessions: [LinkedClaudeSession]
    let snapshot: WorkspaceSnapshot?
    let onSwitch: () -> Void
    let onRestore: () -> Void
    let onDelete: () -> Void

    @State private var isHovered = false
    @State private var isExpanded = false

    /// Total linked sessions — use discovered matches, fall back to stored IDs.
    private var linkedSessionCount: Int {
        max(sessions.count, workspace.linkedSessionIds.count)
    }

    /// Small summary chips shown on the row when collapsed, hinting at expandable content.
    @ViewBuilder
    private var expandSummaryChips: some View {
        let ideCount = snapshot?.ideStates.count ?? 0
        let appCount = capturedApps.count
        let total = ideCount + linkedSessionCount + appCount
        if total > 0 {
            Text("\(total) items")
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(.secondary.opacity(0.08), in: Capsule())
        }
    }

    private var capturedApps: [(name: String, icon: String, bundleId: String)] {
        guard let snapshot else { return [] }
        let skip: Set<String> = [
            "com.apple.dt.Xcode", "com.google.android.studio",
            "com.jetbrains.intellij", "com.jetbrains.intellij.ce",
            "com.microsoft.VSCode", "com.todesktop.230313mzl4w4u92"
        ]
        var seen = Set<String>()
        var apps: [(String, String, String)] = []
        for ws in snapshot.windowStates {
            guard !ws.appBundleId.isEmpty,
                  !seen.contains(ws.appBundleId),
                  !skip.contains(ws.appBundleId) else { continue }
            seen.insert(ws.appBundleId)
            apps.append((ws.appName, appIcon(for: ws.appBundleId), ws.appBundleId))
        }
        return apps
    }

    var body: some View {
        VStack(spacing: 0) {
            // Main row — click to expand/collapse
            HStack(spacing: 0) {
                Button {
                    isExpanded.toggle()
                } label: {
                    HStack(spacing: 8) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 6)
                                .fill((Color(hex: workspace.color) ?? .blue).opacity(0.12))
                                .frame(width: 28, height: 28)
                            Image(systemName: workspace.icon)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Color(hex: workspace.color) ?? .blue)
                        }
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(workspace.isActive ? Color.green : .clear, lineWidth: 1.5)
                        )

                        VStack(alignment: .leading, spacing: 1) {
                            HStack(spacing: 5) {
                                Text(workspace.name)
                                    .font(.system(size: 11, weight: .semibold))
                                    .lineLimit(1)
                                if workspace.isActive {
                                    Circle().fill(Color.green).frame(width: 5, height: 5)
                                }
                            }

                            if !workspace.notes.isEmpty {
                                Text(workspace.notes)
                                    .font(.system(size: 9.5))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }

                            HStack(spacing: 3) {
                                if let branch = workspace.gitBranch {
                                    Image(systemName: "arrow.triangle.branch").font(.system(size: 7))
                                    Text(branch).lineLimit(1)
                                }
                                if linkedSessionCount > 0 {
                                    if workspace.gitBranch != nil { Text("·").foregroundStyle(.quaternary) }
                                    Image(systemName: "bubble.left.fill").font(.system(size: 6))
                                    Text("\(linkedSessionCount)")
                                }
                                if let snap = snapshot, !snap.ideStates.isEmpty {
                                    Text("·").foregroundStyle(.quaternary)
                                    Image(systemName: "chevron.left.forwardslash.chevron.right").font(.system(size: 7))
                                    Text("\(snap.ideStates.count)")
                                }
                            }
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                        }

                        Spacer(minLength: 4)

                        // Expand affordance — summary chips + chevron
                        HStack(spacing: 4) {
                            if !isExpanded {
                                expandSummaryChips
                            }
                            Image(systemName: "chevron.right")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(isHovered ? .secondary : .tertiary)
                                .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                // Restore CTA
                if snapshot != nil {
                    Button(action: onRestore) {
                        HStack(spacing: 3) {
                            Image(systemName: "arrow.counterclockwise")
                                .font(.system(size: 8, weight: .semibold))
                            Text("Restore")
                                .font(.system(size: 9, weight: .medium))
                        }
                        .foregroundStyle(.blue)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                        .background(Color.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 5))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Restore context")
                    .padding(.leading, 4)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isHovered ? Color.primary.opacity(0.05) : .clear)
            )
            .onHover { h in withAnimation(.easeOut(duration: 0.1)) { isHovered = h } }
            .contextMenu {
                Button("Switch to This") { onSwitch() }
                Button("Restore Context") { onRestore() }
                Divider()
                Button("Delete", role: .destructive) { onDelete() }
            }

            // Expanded detail
            if isExpanded {
                expandedContent
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.easeInOut(duration: 0.15), value: isExpanded)
    }

    // MARK: - Expanded Content

    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 2) {
            // IDEs
            if let snap = snapshot, !snap.ideStates.isEmpty {
                CollapsibleGroup(
                    title: "IDEs",
                    count: snap.ideStates.count,
                    icon: "hammer",
                    threshold: 4
                ) {
                    ForEach(snap.ideStates) { ide in
                        HStack(spacing: 5) {
                            Image(systemName: ideIcon(for: ide.bundleId))
                                .font(.system(size: 8))
                                .foregroundStyle(.secondary)
                                .frame(width: 12)
                            Text(ide.appName)
                                .font(.system(size: 9.5, weight: .medium))
                            if let path = ide.projectPath {
                                Spacer()
                                Text(URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent)
                                    .font(.system(size: 9))
                                    .foregroundStyle(.tertiary)
                                    .lineLimit(1)
                            }
                            if let branch = ide.gitBranch {
                                HStack(spacing: 1) {
                                    Image(systemName: "arrow.triangle.branch").font(.system(size: 7))
                                    Text(branch).lineLimit(1)
                                }
                                .font(.system(size: 8))
                                .foregroundStyle(.orange)
                            }
                        }
                        .padding(.vertical, 1)
                    }
                }
            }

            // Claude Sessions — discovered + linked
            if linkedSessionCount > 0 {
                CollapsibleGroup(
                    title: "Claude Sessions",
                    count: linkedSessionCount,
                    icon: "bubble.left.fill",
                    threshold: 4
                ) {
                    ForEach(sessions) { session in
                        SessionInlineRow(session: session, projectDir: workspace.projectPath)
                    }

                    // Show linked IDs that weren't discovered — still clickable
                    let discoveredIds = Set(sessions.map(\.id))
                    let unmatched = workspace.linkedSessionIds.filter { !discoveredIds.contains($0) }
                    ForEach(unmatched, id: \.self) { sessionId in
                        Button {
                            SessionLauncher.openBySessionId(
                                sessionId,
                                projectPath: workspace.projectPath
                            )
                        } label: {
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(Color.gray.opacity(0.25))
                                    .frame(width: 4, height: 4)
                                Text(String(sessionId.prefix(8)) + "…")
                                    .font(.system(size: 9.5, weight: .medium))
                                    .foregroundStyle(.tertiary)
                                Spacer()
                                Image(systemName: "arrow.up.forward")
                                    .font(.system(size: 7))
                                    .foregroundStyle(.quaternary)
                            }
                            .padding(.vertical, 1.5)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            // Apps
            if !capturedApps.isEmpty {
                CollapsibleGroup(
                    title: "Apps",
                    count: capturedApps.count,
                    icon: "macwindow",
                    threshold: 4
                ) {
                    ForEach(capturedApps, id: \.bundleId) { app in
                        HStack(spacing: 5) {
                            Image(systemName: app.icon)
                                .font(.system(size: 8))
                                .foregroundStyle(.secondary)
                                .frame(width: 12)
                            Text(app.name)
                                .font(.system(size: 9.5, weight: .medium))
                                .lineLimit(1)
                        }
                        .padding(.vertical, 1)
                    }
                }
            }

            // Snapshot meta
            if let snap = snapshot {
                HStack(spacing: 6) {
                    if !snap.terminalTabs.isEmpty {
                        miniStat("\(snap.terminalTabs.count)", icon: "terminal")
                    }
                    if !snap.browserTabs.isEmpty {
                        miniStat("\(snap.browserTabs.count)", icon: "globe")
                    }
                    Spacer()
                    Text("Saved \(snap.capturedAt, style: .relative) ago")
                        .font(.system(size: 8))
                        .foregroundStyle(.quaternary)
                }
                .padding(.horizontal, 12)
                .padding(.leading, 36)
                .padding(.vertical, 3)
            }
        }
        .padding(.bottom, 4)
    }

    private func miniStat(_ value: String, icon: String) -> some View {
        HStack(spacing: 2) {
            Image(systemName: icon).font(.system(size: 7))
            Text(value).font(.system(size: 9, weight: .medium, design: .monospaced))
        }
        .foregroundStyle(.tertiary)
    }

    private func ideIcon(for bundleId: String) -> String {
        switch bundleId {
        case "com.apple.dt.Xcode": return "hammer"
        case "com.google.android.studio": return "cpu"
        case let id where id.contains("jetbrains"): return "cpu"
        case "com.microsoft.VSCode", "com.todesktop.230313mzl4w4u92": return "curlybraces"
        default: return "chevron.left.forwardslash.chevron.right"
        }
    }

    private func appIcon(for bundleId: String) -> String {
        switch bundleId {
        case let id where id.contains("Safari"): return "safari"
        case let id where id.contains("Chrome"): return "globe"
        case let id where id.contains("Terminal"): return "terminal"
        case let id where id.contains("iterm"): return "terminal"
        case let id where id.contains("Warp"): return "terminal"
        case let id where id.contains("Slack"): return "bubble.left.and.bubble.right"
        case let id where id.contains("Figma"): return "paintbrush"
        case let id where id.contains("Music"): return "music.note"
        default: return "macwindow"
        }
    }
}

// MARK: - Collapsible Group

private struct CollapsibleGroup<Content: View>: View {
    let title: String
    let count: Int
    let icon: String
    let threshold: Int
    @ViewBuilder let content: Content

    @State private var isOpen: Bool = true

    /// Auto-collapse if count exceeds threshold; start open otherwise.
    private var shouldStartCollapsed: Bool { count > threshold }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            Button {
                withAnimation(.easeInOut(duration: 0.12)) { isOpen.toggle() }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: isOpen ? "chevron.down" : "chevron.right")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 8)

                    Image(systemName: icon)
                        .font(.system(size: 8))
                        .foregroundStyle(.secondary)

                    Text(title.uppercased())
                        .font(.system(size: 8.5, weight: .bold))
                        .foregroundStyle(.secondary)
                        .tracking(0.3)

                    Text("\(count)")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(.secondary.opacity(0.12), in: Capsule())

                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.vertical, 4)

            // Content
            if isOpen {
                content
            }
        }
        .padding(.horizontal, 12)
        .padding(.leading, 36)
        .onAppear {
            if shouldStartCollapsed { isOpen = false }
        }
    }
}

// MARK: - Recent Session Row (global list)

private struct RecentSessionRow: View {
    let session: LinkedClaudeSession
    @State private var isHovered = false

    var body: some View {
        Button {
            SessionLauncher.openInClaude(session: session)
        } label: {
            HStack(spacing: 7) {
                Circle()
                    .fill(session.isActive ? Color.green : Color.gray.opacity(0.25))
                    .frame(width: 5, height: 5)

                Text(session.projectName)
                    .font(.system(size: 10.5, weight: .medium))
                    .lineLimit(1)

                Text(session.shortModel)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(.secondary.opacity(0.08), in: Capsule())

                Spacer()

                Text(session.formattedTokens)
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)

                Text(session.lastActivityTime, style: .relative)
                    .font(.system(size: 8))
                    .foregroundStyle(.quaternary)
                    .frame(width: 38, alignment: .trailing)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 4.5)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(isHovered ? Color.primary.opacity(0.04) : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(.easeOut(duration: 0.1)) { isHovered = h } }
    }
}

// MARK: - Session Inline Row (inside workspace)

private struct SessionInlineRow: View {
    let session: LinkedClaudeSession
    var projectDir: String? = nil
    @State private var isHovered = false

    var body: some View {
        Button {
            SessionLauncher.openInClaude(session: session, projectDir: projectDir)
        } label: {
            HStack(spacing: 4) {
                Circle()
                    .fill(session.isActive ? Color.green : Color.gray.opacity(0.25))
                    .frame(width: 4, height: 4)

                Text(session.summary ?? session.shortModel)
                    .font(.system(size: 9.5, weight: .medium))
                    .lineLimit(1)

                Spacer()

                Text(session.formattedTokens)
                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 1.5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Inline Save Context View

private struct InlineSaveContextView: View {
    let viewModel: WorkspaceListViewModel
    @Binding var isPresented: Bool

    enum SaveMode: String, CaseIterable {
        case createNew = "New Workspace"
        case updateExisting = "Update Existing"
    }

    @State private var mode: SaveMode
    @State private var isSaving = false

    @State private var name = ""
    @State private var projectPath = ""
    @State private var description = ""
    @State private var selectedBranch: String?
    @State private var availableBranches: [String] = []
    @State private var currentBranch: String?
    @State private var selectedIcon = "folder.fill"
    @State private var selectedColor = "007AFF"
    @State private var showFilePicker = false

    @State private var selectedWorkspaceId: UUID?

    private let icons = [
        "folder.fill", "hammer.fill", "wrench.fill", "desktopcomputer",
        "iphone", "apps.iphone", "swift", "chevron.left.forwardslash.chevron.right",
        "cube.fill", "shippingbox.fill", "leaf.fill", "bolt.fill"
    ]

    private let colors: [(name: String, hex: String)] = [
        ("Blue", "007AFF"), ("Purple", "AF52DE"), ("Pink", "FF2D55"),
        ("Red", "FF3B30"), ("Orange", "FF9500"), ("Yellow", "FFCC00"),
        ("Green", "34C759"), ("Teal", "5AC8FA"), ("Indigo", "5856D6"), ("Gray", "8E8E93")
    ]

    init(viewModel: WorkspaceListViewModel, isPresented: Binding<Bool>) {
        self.viewModel = viewModel
        self._isPresented = isPresented
        let hasActive = viewModel.store.activeWorkspace != nil
        _mode = State(initialValue: hasActive ? .updateExisting : .createNew)
        _selectedWorkspaceId = State(initialValue: viewModel.store.activeWorkspace?.id)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button {
                    isPresented = false
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 10, weight: .bold))
                        Text("Back")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)

                Spacer()

                Text("Save Context")
                    .font(.system(size: 12, weight: .bold))

                Spacer()
                Color.clear.frame(width: 40, height: 1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            // Active sessions indicator
            let activeSessions = viewModel.sessionService.sessions.filter(\.isActive)
            if !activeSessions.isEmpty {
                HStack(spacing: 4) {
                    Circle().fill(Color.green).frame(width: 5, height: 5)
                    Text("\(activeSessions.count) active Claude session\(activeSessions.count == 1 ? "" : "s") will be linked")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(.green.opacity(0.05))
            }

            Picker("Mode", selection: $mode) {
                ForEach(SaveMode.allCases, id: \.self) { m in
                    Text(m.rawValue).tag(m)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            Divider()

            // Content
            ScrollView(.vertical, showsIndicators: false) {
                switch mode {
                case .createNew:
                    createNewContent
                case .updateExisting:
                    updateExistingContent
                }
            }

            Divider()

            // Footer
            HStack {
                Button("Cancel") { isPresented = false }
                    .font(.system(size: 11))
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)

                Spacer()

                if isSaving {
                    ProgressView().scaleEffect(0.5).padding(.trailing, 2)
                }

                Button {
                    performSave()
                } label: {
                    Text(mode == .createNew ? "Create" : "Update")
                        .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(!canSave || isSaving)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
        }
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [.folder]
        ) { result in
            if case .success(let url) = result {
                projectPath = url.path
                if name.isEmpty { name = url.lastPathComponent }
                detectBranches(at: url.path)
            }
        }
    }

    // MARK: - Create New

    private var createNewContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Name
            field("Name") {
                TextField("e.g. iOS Auth Flow", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11))
            }

            // Description
            field("Description", optional: true) {
                TextField("What are you working on?", text: $description)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11))
            }

            // Project Path
            field("Project Path", optional: true, hint: "Links git branches & Claude sessions") {
                HStack(spacing: 4) {
                    TextField("/path/to/project", text: $projectPath)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11))
                        .onChange(of: projectPath) { _, newPath in
                            detectBranches(at: newPath)
                        }
                    Button("Browse") { showFilePicker = true }
                        .controlSize(.mini)
                        .font(.system(size: 10))
                }
            }

            // Branch
            if !availableBranches.isEmpty {
                field("Branch") {
                    Picker("Branch", selection: $selectedBranch) {
                        ForEach(availableBranches, id: \.self) { branch in
                            Text(branch + (branch == currentBranch ? " (current)" : ""))
                                .tag(Optional(branch))
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .font(.system(size: 10))
                }
            }

            // Icon & Color row
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Icon")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(26)), count: 6), spacing: 3) {
                        ForEach(icons, id: \.self) { icon in
                            Button { selectedIcon = icon } label: {
                                Image(systemName: icon)
                                    .font(.system(size: 10))
                                    .frame(width: 24, height: 24)
                                    .background(
                                        selectedIcon == icon ? (Color(hex: selectedColor) ?? .blue).opacity(0.15) : Color.clear,
                                        in: RoundedRectangle(cornerRadius: 4)
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 4)
                                            .stroke(selectedIcon == icon ? (Color(hex: selectedColor) ?? .blue) : .clear, lineWidth: 1)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Color")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(20)), count: 2), spacing: 3) {
                        ForEach(colors, id: \.hex) { color in
                            Button { selectedColor = color.hex } label: {
                                Circle()
                                    .fill(Color(hex: color.hex) ?? .blue)
                                    .frame(width: 18, height: 18)
                                    .overlay(
                                        Circle().stroke(Color.primary, lineWidth: selectedColor == color.hex ? 2 : 0)
                                            .padding(1)
                                    )
                            }
                            .buttonStyle(.plain)
                            .help(color.name)
                        }
                    }
                }
            }
        }
        .padding(12)
    }

    // MARK: - Update Existing

    private var updateExistingContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            if viewModel.store.workspaces.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "rectangle.stack.badge.plus")
                        .font(.system(size: 20))
                        .foregroundStyle(.tertiary)
                    Text("No workspaces yet")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            } else {
                ForEach(viewModel.store.workspaces.sorted(by: { $0.lastActiveAt > $1.lastActiveAt })) { ws in
                    Button { selectedWorkspaceId = ws.id } label: {
                        HStack(spacing: 8) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 5)
                                    .fill((Color(hex: ws.color) ?? .blue).opacity(0.12))
                                    .frame(width: 24, height: 24)
                                Image(systemName: ws.icon)
                                    .font(.system(size: 10))
                                    .foregroundStyle(Color(hex: ws.color) ?? .blue)
                            }

                            VStack(alignment: .leading, spacing: 1) {
                                Text(ws.name)
                                    .font(.system(size: 11, weight: .medium))
                                if let branch = ws.gitBranch {
                                    HStack(spacing: 2) {
                                        Image(systemName: "arrow.triangle.branch")
                                            .font(.system(size: 7))
                                        Text(branch)
                                            .font(.system(size: 9))
                                    }
                                    .foregroundStyle(.tertiary)
                                }
                            }

                            Spacer()

                            if selectedWorkspaceId == ws.id {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 14))
                                    .foregroundStyle(.blue)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(selectedWorkspaceId == ws.id ? Color.blue.opacity(0.06) : .clear)
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
    }

    // MARK: - Helpers

    private func field(_ label: String, optional: Bool = false, hint: String? = nil, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 3) {
                Text(label)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                if optional {
                    Text("(optional)")
                        .font(.system(size: 9))
                        .foregroundStyle(.quaternary)
                }
            }
            content()
            if let hint {
                Text(hint)
                    .font(.system(size: 8))
                    .foregroundStyle(.quaternary)
            }
        }
    }

    private var canSave: Bool {
        switch mode {
        case .createNew: return !name.isEmpty
        case .updateExisting: return selectedWorkspaceId != nil
        }
    }

    private func performSave() {
        isSaving = true
        Task {
            switch mode {
            case .createNew:
                await viewModel.createAndSaveWorkspace(
                    name: name,
                    projectPath: projectPath,
                    gitBranch: selectedBranch,
                    notes: description,
                    icon: selectedIcon,
                    color: selectedColor
                )
            case .updateExisting:
                if let id = selectedWorkspaceId {
                    await viewModel.updateWorkspaceContext(workspaceId: id)
                }
            }
            isSaving = false
            isPresented = false
        }
    }

    private func detectBranches(at path: String) {
        guard !path.isEmpty else {
            availableBranches = []; currentBranch = nil; selectedBranch = nil
            return
        }
        let branches = GitService.branches(at: path)
        let current = GitService.currentBranch(at: path)
        availableBranches = branches
        currentBranch = current
        if selectedBranch == nil || !branches.contains(selectedBranch ?? "") {
            selectedBranch = current
        }
    }
}
