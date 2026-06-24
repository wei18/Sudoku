// SudokuNearWinModalModifier — DEBUG-only view modifier that detects the
// `-uitest-near-win-modal` launch argument and presents a near-win board
// through the PRODUCTION modal path (path == nil fullScreenCover), so the
// #610 in-board Completion overlay fires on the winning tap.
//
// Contrast with `SudokuNearWinModifier` (`-uitest-near-win`), which wraps the
// board in its own NavigationStack (path != nil) — that exercises the push
// completion path, NOT the #610 overlay. This modifier is the modal sibling:
// the fullScreenCover has no inner NavigationStack, so `path == nil` and
// `BoardView.shouldPresentCompletionOverlay` returns `true` on the win.
//
// Applied at `AppComposition.rootView` alongside `SudokuNearWinModifier` —
// when the launch argument is absent every launch, the modifier is a no-op.
//
// Availability: `#if DEBUG` only — stripped from Release builds entirely.

#if DEBUG

public import SwiftUI

public struct SudokuNearWinModalModifier: ViewModifier {

    public init() {}

    public func body(content: Content) -> some View {
        #if os(iOS)
        content.modifier(SudokuNearWinModalIOSModifier())
        #else
        content
        #endif
    }
}

// MARK: - iOS implementation

#if os(iOS)

import GameAppKit
import GameCenterClient
import SudokuEngine

/// iOS-only implementation: detects the launch arg and presents a
/// `fullScreenCover` WITHOUT a NavigationStack, so `path == nil`
/// and the #610 in-board overlay fires on the winning tap.
@MainActor
private struct SudokuNearWinModalIOSModifier: ViewModifier {

    @State private var nearWinBoard: SudokuNearWinBoard?

    func body(content: Content) -> some View {
        let isModalLaunch = ProcessInfo.processInfo.arguments
            .contains(UITestLaunchArg.nearWinModal)
        return content
            .onAppear {
                guard isModalLaunch else { return }
                Task { @MainActor in
                    nearWinBoard = try? await SudokuNearWinBoard.build()
                }
            }
            // item: (not isPresented:) — driven by the board itself, same
            // presentation-race fix as SudokuNearWinModifier (#523).
            .fullScreenCover(item: $nearWinBoard) { board in
                SudokuNearWinModalCoverView(board: board)
            }
    }
}

// MARK: - Cover content

/// Presents `BoardView` directly — NO wrapping NavigationStack.
/// `path == nil` means `BoardView.shouldPresentCompletionOverlay` returns
/// `true` on the winning tap, exercising the production #610 overlay path.
@MainActor
private struct SudokuNearWinModalCoverView: View {

    let board: SudokuNearWinBoard

    var body: some View {
        BoardView(
            viewModel: board.viewModel,
            gameCenter: NearWinModalNoopGameCenterClient()
            // path: nil (default) — the load-bearing distinction from the
            // push-context hook in SudokuNearWinModifier.
        )
        .environment(\.theme, DefaultTheme())
        .environment(\.sudokuCell, DefaultTheme().cell)
    }
}

// MARK: - Noop Game Center

/// Minimal `GameCenterClient` conformer for the modal near-win completion
/// overlay. Mirrors `NearWinNoopGameCenterClient` in SudokuNearWinModifier.
private actor NearWinModalNoopGameCenterClient: GameCenterClient {
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
