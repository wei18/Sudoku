// SudokuNearWinModifier — DEBUG-only view modifier that detects the
// `-uitest-near-win` launch argument and presents a near-win board as a
// fullScreenCover over the normal root (#510 uitest hook).
//
// Applied at `AppComposition.rootView` level — sits above the normal navigation
// stack. When the launch argument is absent (every non-uitest launch) the
// modifier is a transparent no-op.
//
// On iOS: a `fullScreenCover` containing a real `NavigationStack` is presented
// so the board can push `.completion` via a path binding. On macOS:
// `fullScreenCover` is unavailable; the modifier is an unconditional no-op
// (the near-win hook is an iOS simulator uitest feature).
//
// Availability: `#if DEBUG` only — stripped from Release builds entirely.

#if DEBUG

public import SwiftUI
import GameAppKit

public struct SudokuNearWinModifier: ViewModifier {

    public init() {}

    public func body(content: Content) -> some View {
        #if os(iOS)
        content.modifier(SudokuNearWinIOSModifier())
        #else
        content
        #endif
    }
}

// MARK: - iOS implementation

#if os(iOS)

import GameCenterClient
import SudokuEngine

/// iOS-only implementation that detects the launch arg and presents the cover.
@MainActor
private struct SudokuNearWinIOSModifier: ViewModifier {

    @State private var nearWinBoard: SudokuNearWinBoard?
    @State private var isPresented: Bool = false

    func body(content: Content) -> some View {
        let isNearWinLaunch = ProcessInfo.processInfo.arguments
            .contains(UITestLaunchArg.nearWin)
        return content
            .onAppear {
                guard isNearWinLaunch else { return }
                Task { @MainActor in
                    guard let board = try? await SudokuNearWinBoard.build() else { return }
                    nearWinBoard = board
                    isPresented = true
                }
            }
            .fullScreenCover(isPresented: $isPresented) {
                if let board = nearWinBoard {
                    SudokuNearWinCoverView(board: board)
                }
            }
    }
}

// MARK: - Cover content

/// NavigationStack host inside the fullScreenCover. Provides a real
/// `path` binding so `BoardView` can push `.completion` on win.
@MainActor
private struct SudokuNearWinCoverView: View {

    let board: SudokuNearWinBoard
    @State private var path: [AppRoute] = []

    var body: some View {
        NavigationStack(path: $path) {
            BoardView(
                viewModel: board.viewModel,
                path: $path
            )
            .navigationDestination(for: AppRoute.self) { route in
                nearWinDestination(for: route)
            }
        }
        .environment(\.theme, DefaultTheme())
        .environment(\.sudokuCell, DefaultTheme().cell)
    }

    @ViewBuilder
    private func nearWinDestination(for route: AppRoute) -> some View {
        if case .completion(let puzzleId, let elapsedSeconds, let mistakeCount) = route {
            CompletionView(
                viewModel: CompletionViewModel(
                    puzzleId: puzzleId,
                    elapsedSeconds: elapsedSeconds,
                    mistakeCount: mistakeCount,
                    leaderboardId: nil,
                    gameCenter: NearWinNoopGameCenterClient()
                ),
                onClose: { path.removeAll() }
            )
        }
    }
}

// MARK: - Noop Game Center (uitest: never submits, returns empty data)

/// Minimal `GameCenterClient` conformer for the near-win completion view.
/// Returns empty/degraded state for all methods — the completion screen
/// degrades gracefully (no leaderboard slice, no submit). Never ships.
private actor NearWinNoopGameCenterClient: GameCenterClient {
    func authenticate() async throws -> GameCenterAuthState { .unauthenticated }
    func authStateUpdates() async -> AsyncStream<GameCenterAuthState> { .init { _ in } }
    func submitScore(
        puzzleId: String,
        elapsedSeconds: Int,
        difficulty: Difficulty,
        leaderboardKind: LeaderboardKind
    ) async throws {}
    func submitScore(leaderboardId: String, elapsedSeconds: Int) async throws {}
    func reportAchievement(_ achievement: AchievementProgress) async throws {}
    func fetchLeaderboardSlice(
        leaderboardId: String,
        scope: LeaderboardScope,
        aroundLocalPlayer: Bool,
        limit: Int
    ) async throws -> LeaderboardSlice {
        LeaderboardSlice(
            leaderboardId: leaderboardId,
            scope: scope,
            entries: [],
            totalPlayerCount: 0,
            fetchedAt: Date()
        )
    }
    func friendsAuthorizationStatus() async -> FriendsAuthStatus { .notDetermined }
    func requestFriendsAuthorization() async throws -> FriendsAuthStatus { .notDetermined }
}

#endif // os(iOS)

#endif // DEBUG
