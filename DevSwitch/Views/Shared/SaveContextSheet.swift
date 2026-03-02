import SwiftUI

/// Sheet for saving the current context: create a new workspace or update an existing one.
struct SaveContextSheet: View {
    let viewModel: WorkspaceListViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openWindow) private var openWindow

    enum SaveMode: String, CaseIterable {
        case createNew = "New Workspace"
        case updateExisting = "Update Existing"
    }

    @State private var mode: SaveMode
    @State private var isSaving = false

    // Create new fields
    @State private var name = ""
    @State private var projectPath = ""
    @State private var selectedBranch: String?
    @State private var availableBranches: [String] = []
    @State private var currentBranch: String?
    @State private var selectedIcon = "folder.fill"
    @State private var selectedColor = "007AFF"

    // Update existing fields
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

    init(viewModel: WorkspaceListViewModel) {
        self.viewModel = viewModel
        let hasActive = viewModel.store.activeWorkspace != nil
        _mode = State(initialValue: hasActive ? .updateExisting : .createNew)
        _selectedWorkspaceId = State(initialValue: viewModel.store.activeWorkspace?.id)
    }

    var body: some View {
        VStack(spacing: 0) {
            Text("Save Context")
                .font(.headline)
                .padding(.top, 16)
                .padding(.bottom, 8)

            Picker("Mode", selection: $mode) {
                ForEach(SaveMode.allCases, id: \.self) { m in
                    Text(m.rawValue).tag(m)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.bottom, 12)

            Divider()

            ScrollView {
                switch mode {
                case .createNew:
                    createNewContent
                case .updateExisting:
                    updateExistingContent
                }
            }

            Divider()

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)

                Spacer()

                if isSaving {
                    ProgressView()
                        .scaleEffect(0.7)
                        .padding(.trailing, 4)
                }

                Button(mode == .createNew ? "Create & Save" : "Update Snapshot") {
                    performSave()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canSave || isSaving)
            }
            .padding(16)
        }
        .frame(width: 420, height: mode == .createNew ? 540 : 420)
    }

    // MARK: - Create New

    private var createNewContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Workspace Name")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                TextField("e.g. iOS Auth Flow", text: $name)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Project Path")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                HStack {
                    TextField("/path/to/project", text: $projectPath)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: projectPath) { _, newPath in
                            detectBranches(at: newPath)
                        }
                    Button("Browse") { browseForFolder() }
                }
            }

            if !availableBranches.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.triangle.branch")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        Text("Git Branch")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                        if let current = currentBranch {
                            Text("(current: \(current))")
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                        }
                    }

                    Picker("Branch", selection: $selectedBranch) {
                        ForEach(availableBranches, id: \.self) { branch in
                            HStack(spacing: 4) {
                                Text(branch)
                                if branch == currentBranch {
                                    Text("(current)")
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            .tag(Optional(branch))
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)

                    Text("DevSwitch will switch to this branch when activating this workspace.")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            }

            // Icon picker
            VStack(alignment: .leading, spacing: 6) {
                Text("Icon")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(32)), count: 6), spacing: 6) {
                    ForEach(icons, id: \.self) { icon in
                        Button {
                            selectedIcon = icon
                        } label: {
                            Image(systemName: icon)
                                .font(.system(size: 14))
                                .frame(width: 28, height: 28)
                                .background(
                                    selectedIcon == icon ? Color.blue.opacity(0.2) : Color.clear,
                                    in: RoundedRectangle(cornerRadius: 6)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(selectedIcon == icon ? Color.blue : Color.clear, lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            // Color picker
            VStack(alignment: .leading, spacing: 6) {
                Text("Color")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    ForEach(colors, id: \.hex) { color in
                        Button {
                            selectedColor = color.hex
                        } label: {
                            Circle()
                                .fill(Color(hex: color.hex) ?? .blue)
                                .frame(width: 22, height: 22)
                                .overlay(
                                    Circle()
                                        .stroke(Color.primary, lineWidth: selectedColor == color.hex ? 2 : 0)
                                        .padding(1)
                                )
                        }
                        .buttonStyle(.plain)
                        .help(color.name)
                    }
                }
            }
        }
        .padding(16)
    }

    // MARK: - Update Existing

    private var updateExistingContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Choose a workspace to update with your current context:")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.top, 12)

            if viewModel.store.workspaces.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "rectangle.stack.badge.plus")
                        .font(.system(size: 24))
                        .foregroundStyle(.tertiary)
                    Text("No workspaces yet. Switch to \"New Workspace\" to create one.")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
            } else {
                ForEach(viewModel.store.workspaces.sorted(by: { $0.lastActiveAt > $1.lastActiveAt })) { ws in
                    Button {
                        selectedWorkspaceId = ws.id
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: ws.icon)
                                .font(.system(size: 14))
                                .foregroundStyle(Color(hex: ws.color) ?? .blue)
                                .frame(width: 20)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(ws.name)
                                    .font(.system(size: 12, weight: .medium))
                                if let branch = ws.gitBranch {
                                    HStack(spacing: 3) {
                                        Image(systemName: "arrow.triangle.branch")
                                            .font(.system(size: 9))
                                        Text(branch)
                                            .font(.system(size: 10))
                                    }
                                    .foregroundStyle(.secondary)
                                }
                            }

                            Spacer()

                            if selectedWorkspaceId == ws.id {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.blue)
                            }

                            if ws.isActive {
                                Text("ACTIVE")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1)
                                    .background(.green, in: Capsule())
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(
                            selectedWorkspaceId == ws.id
                                ? Color.blue.opacity(0.08)
                                : Color.clear,
                            in: RoundedRectangle(cornerRadius: 6)
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }

            // Info about what will be captured
            VStack(alignment: .leading, spacing: 4) {
                Text("This will capture:")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                HStack(spacing: 12) {
                    captureLabel("IDE projects", icon: "hammer")
                    captureLabel("Windows", icon: "macwindow")
                    captureLabel("Terminals", icon: "terminal")
                    captureLabel("Browser tabs", icon: "globe")
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 12)
        }
    }

    private func captureLabel(_ text: String, icon: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 8))
            Text(text)
                .font(.system(size: 9))
        }
        .foregroundStyle(.tertiary)
    }

    // MARK: - Logic

    private var canSave: Bool {
        switch mode {
        case .createNew:
            return !name.isEmpty && !projectPath.isEmpty
        case .updateExisting:
            return selectedWorkspaceId != nil
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
                    icon: selectedIcon,
                    color: selectedColor
                )
            case .updateExisting:
                if let id = selectedWorkspaceId {
                    await viewModel.updateWorkspaceContext(workspaceId: id)
                }
            }
            isSaving = false
            dismiss()
        }
    }

    private func browseForFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Choose the project folder"

        if panel.runModal() == .OK, let url = panel.url {
            projectPath = url.path
            if name.isEmpty {
                name = url.lastPathComponent
            }
            detectBranches(at: url.path)
        }
    }

    private func detectBranches(at path: String) {
        guard !path.isEmpty else {
            availableBranches = []
            currentBranch = nil
            selectedBranch = nil
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
