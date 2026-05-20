// RootView — app entry container.
//
// Owns the NavigationStackHost shape, mounts HomeView as the root content,
// and renders the (optional) Resume pill at the top per design 01-root.md.

public import SwiftUI
import Persistence

public struct RootView: View {
    @State private var viewModel: RootViewModel
    @Environment(\.theme) private var theme

    public init(viewModel: RootViewModel) {
        self._viewModel = State(initialValue: viewModel)
    }

    public var body: some View {
        NavigationStackHost(
            path: Binding(get: { viewModel.path }, set: { viewModel.path = $0 }),
            sidebar: { sidebarPlaceholder },
            content: { rootContent },
            destination: { _ in EmptyView() }
        )
        .task { await viewModel.bootstrap() }
    }

    @ViewBuilder
    private var rootContent: some View {
        VStack(spacing: 0) {
            if let candidate = viewModel.resumeCandidate {
                ResumePill(candidate: candidate) {
                    viewModel.resumeTapped()
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
            }
            HomeView(
                viewModel: HomeViewModel(
                    path: Binding(get: { viewModel.path }, set: { viewModel.path = $0 })
                )
            )
        }
        .background(theme.surface.background.resolved)
    }

    @ViewBuilder
    private var sidebarPlaceholder: some View {
        // Sidebar pushes the same `AppRoute` as the matching HomeView card.
        // Mapping lives on `HomeMode.appRoute` so both entry points stay in sync.
        List {
            NavigationLink(value: HomeMode.daily.appRoute) {
                Label("Daily", systemImage: "calendar")
            }
            NavigationLink(value: HomeMode.practice.appRoute) {
                Label("Practice", systemImage: "dice")
            }
            NavigationLink(value: HomeMode.leaderboard.appRoute) {
                Label("Leaderboard", systemImage: "trophy.fill")
            }
            NavigationLink(value: HomeMode.settings.appRoute) {
                Label("Settings", systemImage: "gear")
            }
        }
        .navigationTitle("Sudoku")
    }
}

// MARK: - Resume pill

struct ResumePill: View {
    let candidate: SavedGameSummary
    let onTap: () -> Void
    @Environment(\.theme) private var theme

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Image(systemName: "arrow.clockwise")
                    .foregroundStyle(theme.accent.primary.resolved)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Resume \(candidate.difficulty.capitalized)")
                        .font(.body.weight(.medium))
                        .foregroundStyle(theme.text.primary.resolved)
                    Text(elapsedLabel)
                        .font(.caption)
                        .foregroundStyle(theme.text.secondary.resolved)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(theme.text.tertiary.resolved)
            }
            .padding(12)
            .background(theme.surface.primary.resolved, in: .rect(cornerRadius: 14))
            .contentShape(Rectangle())
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
        }
        .buttonStyle(.plain)
    }

    private var elapsedLabel: String {
        let total = candidate.elapsedSeconds
        let minutes = total / 60
        let seconds = total % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

