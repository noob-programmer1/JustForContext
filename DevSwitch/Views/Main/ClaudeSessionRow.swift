import SwiftUI

/// A row displaying a linked Claude session with an "Open" button.
struct ClaudeSessionRow: View {
    let session: LinkedClaudeSession
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 10) {
            // Active indicator
            Circle()
                .fill(session.isActive ? Color.green : Color.gray.opacity(0.3))
                .frame(width: 7, height: 7)

            // Session info
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(session.summary ?? "Session")
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)

                    Text(session.shortModel)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(.quaternary, in: Capsule())
                }

                HStack(spacing: 6) {
                    Text(session.formattedTokens + " tokens")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                    Text("·")
                        .foregroundStyle(.quaternary)
                    Text(session.formattedCost)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Text("·")
                        .foregroundStyle(.quaternary)
                    Text(session.lastActivityTime, style: .relative)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            // Open in Terminal button
            Button {
                SessionLauncher.openInClaude(session: session)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "terminal")
                        .font(.system(size: 10))
                    Text("Open")
                        .font(.system(size: 10, weight: .medium))
                }
                .foregroundStyle(isHovered ? Color.blue : Color.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    isHovered ? Color.blue.opacity(0.1) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 5)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(Color.gray.opacity(0.2), lineWidth: 0.5)
                )
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .background(
            isHovered ? Color.blue.opacity(0.04) : Color.clear,
            in: RoundedRectangle(cornerRadius: 8)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.gray.opacity(0.15), lineWidth: 0.5)
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}
