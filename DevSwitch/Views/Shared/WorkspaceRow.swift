import SwiftUI

/// Sidebar row for a workspace.
struct WorkspaceRow: View {
    let workspace: Workspace
    let sessionCount: Int

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: workspace.icon)
                .font(.system(size: 14))
                .foregroundStyle(Color(hex: workspace.color) ?? .blue)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(workspace.name)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)

                    if workspace.isActive {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 6, height: 6)
                    }
                }

                HStack(spacing: 4) {
                    if let branch = workspace.gitBranch {
                        Text(branch)
                            .lineLimit(1)
                    }

                    if sessionCount > 0 {
                        Text("· \(sessionCount) session\(sessionCount == 1 ? "" : "s")")
                    }
                }
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}
