import SwiftUI

/// Menubar icon with optional token usage display.
struct MenuBarLabel: View {
    let viewModel: WorkspaceListViewModel

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "rectangle.stack.fill")

            if let tokens = todayTokens {
                Text(tokens)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
            }
        }
    }

    /// Aggregate today's token usage across all discovered sessions.
    private var todayTokens: String? {
        let sessions = viewModel.sessionService.sessions
        guard !sessions.isEmpty else { return nil }

        let calendar = Calendar.current
        let totalTokens = sessions
            .filter { calendar.isDateInToday($0.lastActivityTime) }
            .reduce(0) { $0 + $1.totalTokens }

        guard totalTokens > 0 else { return nil }

        if totalTokens >= 1_000_000 {
            return String(format: "%.1fM", Double(totalTokens) / 1_000_000)
        } else if totalTokens >= 1_000 {
            return String(format: "%.0fK", Double(totalTokens) / 1_000)
        }
        return "\(totalTokens)"
    }
}
