// RootView — app entry container.
//
// Owns the NavigationStackHost shape, mounts HomeView as the root content,
// and renders the (optional) Resume pill at the top per design 01-root.md.
// Also resolves `AppRoute` pushes into concrete `View+VM` instances via the
// inline `destination` switch (design.md §How.5.1, issue #45).

public import SwiftUI
public import GameCenterClient
public import Persistence
public import PuzzleStore
public import Telemetry

public struct RootView: View {
    @State private var viewModel: RootViewModel
    @Environment(\.theme) private var theme

    private let puzzleProvider: any PuzzleProviderProtocol
    private let persistence: any PersistenceProtocol
    private let gameCenter: any GameCenterClient
    private let telemetry: Telemetry

    public init(
        viewModel: RootViewModel,
        puzzleProvider: any PuzzleProviderProtocol,
        persistence: any PersistenceProtocol,
        gameCenter: any GameCenterClient,
        telemetry: Telemetry
    ) {
        self._viewModel = State(initialValue: viewModel)
        self.puzzleProvider = puzzleProvider
        self.persistence = persistence
        self.gameCenter = gameCenter
        self.telemetry = telemetry
    }

    public var body: some View {
        NavigationStackHost(
            path: Binding(get: { viewModel.path }, set: { viewModel.path = $0 }),
            sidebar: { sidebarPlaceholder },
            content: { rootContent },
            destination: { route in destinationView(for: route) }
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
        // Sidebar mirrors HomeView's mode list. Daily / Practice / Settings push
        // an `AppRoute`; Leaderboard is a side effect — it presents Apple's
        // native Game Center dashboard modally (issue #49, 2026-05-20) rather
        // than pushing onto the stack.
        List {
            NavigationLink(value: AppRoute.daily) {
                Label("Daily", systemImage: "calendar")
            }
            NavigationLink(value: AppRoute.practice) {
                Label("Practice", systemImage: "dice")
            }
            Button {
                GameCenterDashboard.present()
            } label: {
                Label("Leaderboard", systemImage: "trophy.fill")
            }
            .buttonStyle(.plain)
            NavigationLink(value: AppRoute.settings) {
                Label("Settings", systemImage: "gear")
            }
        }
        .navigationTitle("Sudoku")
    }

    // MARK: - Destination resolution
    //
    // Inline `switch` over AppRoute that constructs the matching View + its
    // owning ViewModel synchronously per push. Pure construction — no IO,
    // no async — so each fresh push gets a fresh VM (matches HomeViewModel's
    // ctor shape: bindings + protocol deps only). `.board` is the lone
    // exception: it routes through `BoardLoaderView` which does the async
    // puzzle fetch before mounting `BoardView` (see BoardLoaderView.swift).

    @ViewBuilder
    private func destinationView(for route: AppRoute) -> some View {
        switch route {
        case .home:
            // `.home` is never pushed (root content already renders HomeView).
            // Defensive case kept so the switch stays total.
            EmptyView()
        case .daily:
            DailyHubView(
                viewModel: DailyHubViewModel(
                    provider: puzzleProvider,
                    persistence: persistence
                )
            )
        case .practice:
            PracticeHubView(
                viewModel: PracticeHubViewModel(provider: puzzleProvider)
            )
        case .board(let puzzleId):
            BoardLoaderView(
                puzzleId: puzzleId,
                puzzleProvider: puzzleProvider,
                persistence: persistence
            )
        case .completion(let puzzleId, let elapsedSeconds):
            CompletionView(
                viewModel: CompletionViewModel(
                    puzzleId: puzzleId,
                    elapsedSeconds: elapsedSeconds,
                    leaderboardId: LeaderboardIDs.id(for: .dailyEasy),
                    gameCenter: gameCenter
                )
            )
        case .settings:
            SettingsView(viewModel: SettingsViewModel(persistence: persistence))
        }
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
