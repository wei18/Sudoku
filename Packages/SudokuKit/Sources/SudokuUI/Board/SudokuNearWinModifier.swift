// SudokuNearWinModifier — DEBUG-only view modifier that detects the
// `-uitest-near-win` launch argument and presents a near-win board as a
// fullScreenCover over the normal root (#510 uitest hook).
//
// Applied at `AppComposition.rootView` level — sits above the normal navigation
// stack. When the launch argument is absent (every non-uitest launch) the
// modifier is a transparent no-op.
//
// On iOS: a `fullScreenCover` presents the board with `path == nil`, so a win
// uses the same in-board completion OVERLAY as the normal flow (Close dismisses
// the cover). On macOS: `fullScreenCover` is unavailable; the modifier is an
// unconditional no-op (the near-win hook is an iOS simulator uitest feature).
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

    func body(content: Content) -> some View {
        let isNearWinLaunch = ProcessInfo.processInfo.arguments
            .contains(UITestLaunchArg.nearWin)
        return content
            .onAppear {
                guard isNearWinLaunch else { return }
                Task { @MainActor in
                    nearWinBoard = try? await SudokuNearWinBoard.build()
                }
            }
            // item: (not isPresented:) — the cover is driven by the board
            // itself, so the content closure always receives the built board.
            // Splitting presentation (Bool) from data (optional) raced: the
            // cover presented before the board propagated → blank cover (#523).
            .fullScreenCover(item: $nearWinBoard) { board in
                SudokuNearWinCoverView(board: board)
            }
    }
}

// MARK: - Cover content

/// Host for the near-win board inside the fullScreenCover. Presents the board
/// with `path == nil` so a win uses the SAME in-board completion OVERLAY as the
/// normal iPhone flow (Close → `dismiss()` → this cover closes). Previously it
/// wrapped a `NavigationStack` and pushed `.completion`, which routed through the
/// pushed-route completion whose Close popped back to the solved board (a trap)
/// and diverged from MS's inline near-win. Now consistent with MS.
@MainActor
private struct SudokuNearWinCoverView: View {

    let board: SudokuNearWinBoard

    var body: some View {
        BoardView(
            viewModel: board.viewModel,
            gameCenter: NearWinNoopGameCenterClient()
        )
        .environment(\.theme, DefaultTheme())
        .environment(\.sudokuCell, DefaultTheme().cell)
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
