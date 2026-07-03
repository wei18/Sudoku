// SudokuNearWinModalModifier — DEBUG-only view modifier that detects the
// `-uitest-near-win-modal` launch argument and presents a near-win board
// through the PRODUCTION modal path (path == nil fullScreenCover), so the
// #610 in-board Completion overlay fires on the winning tap.
//
// Contrast with `SudokuNearWinModifier` (`-uitest-near-win`), which also
// mounts the board with `path == nil` in a fullScreenCover since the Jul-3
// hook cleanup (its former NavigationStack-push variant exercised the
// pushed-route completion, deleted entirely in #667 2B). Both hooks now hit
// the same in-board overlay; this one exists to keep the historical
// `-uitest-near-win-modal` entry point stable for #510 E2E.
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
    // DEBUG Play Again: set to true when the user taps "Play Again" in the
    // completion overlay; the onChange handler rebuilds a fresh board once the
    // dismiss animation clears nearWinBoard to nil.
    @State private var wantsPlayAgain: Bool = false

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
                SudokuNearWinModalCoverView(
                    board: board,
                    onPlayAgain: { _ in wantsPlayAgain = true }
                )
            }
            // Rebuild a fresh near-win board after Play Again dismisses the
            // current one. nearWinBoard becomes nil when the fullScreenCover's
            // dismiss animation completes; at that point we rebuild.
            // Observe `== nil` (a Bool) rather than the board itself, so we don't
            // need SudokuNearWinBoard: Equatable. Fires when the cover's dismiss
            // animation clears nearWinBoard to nil after a Play Again tap.
            .onChange(of: nearWinBoard == nil) { _, isNil in
                guard isNil, wantsPlayAgain else { return }
                wantsPlayAgain = false
                Task { @MainActor in
                    nearWinBoard = try? await SudokuNearWinBoard.build()
                }
            }
    }
}

// MARK: - Cover content

/// Presents `BoardView` directly — NO wrapping NavigationStack.
/// `path == nil` means `BoardView.shouldPresentCompletionOverlay` returns
/// `true` on the winning tap, exercising the production #610 overlay path.
///
/// `onPlayAgain`: DEBUG-only Play Again hook. When wired, the completion
/// overlay shows "Play Again" above Close; tapping it re-presents a fresh
/// near-win board through the modifier's `wantsPlayAgain` / `onChange` cycle.
@MainActor
private struct SudokuNearWinModalCoverView: View {

    let board: SudokuNearWinBoard
    let onPlayAgain: ((Difficulty) -> Void)?

    init(board: SudokuNearWinBoard, onPlayAgain: ((Difficulty) -> Void)? = nil) {
        self.board = board
        self.onPlayAgain = onPlayAgain
    }

    var body: some View {
        BoardView(
            viewModel: board.viewModel,
            gameCenter: NearWinModalNoopGameCenterClient(),
            onPlayAgain: onPlayAgain
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
