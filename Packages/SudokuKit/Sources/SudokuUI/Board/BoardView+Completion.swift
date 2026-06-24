// BoardView+Completion — overlay surface for the post-solve Completion screen.
//
// Extracted from BoardView.swift (#610) to keep that file under SwiftLint's
// file_length ceiling (repo convention: extract a `+Feature.swift` sibling
// rather than disabling the rule).
//
// Root cause of #610: the board is presented as a fullScreenCover modal where
// `path == nil`, so the legacy `pushCompletionIfNeeded()` → `path.append(.completion)`
// was silently a no-op. Fix: present CompletionView as an in-board overlay,
// mirroring MinesweeperBoardView.completionSurface (#292 / #518).

import SwiftUI
import GameAppKit
public import SettingsUI
public import GameCenterClient
import SudokuEngine

// MARK: - Module-private noop (previews / tests with no GC wired)

/// Minimal no-op conformance used when `BoardView` is constructed without a
/// `GameCenterClient` (previews, snapshot tests, MVP callsites). Mirrors the
/// `NearWinNoopGameCenterClient` in `SudokuNearWinModifier.swift`.
private actor BoardNoopGameCenterClient: GameCenterClient {
    func authenticate() async throws -> GameCenterAuthState { .unauthenticated }
    func authStateUpdates() async -> AsyncStream<GameCenterAuthState> {
        AsyncStream { _ in }
    }
    func submitScore(puzzleId: String, elapsedSeconds: Int,
                     difficulty: Difficulty, leaderboardKind: LeaderboardKind) async throws {}
    func submitScore(leaderboardId: String, elapsedSeconds: Int) async throws {}
    func reportAchievement(_ achievement: AchievementProgress) async throws {}
    func fetchLeaderboardSlice(leaderboardId: String, scope: LeaderboardScope,
                               aroundLocalPlayer: Bool, limit: Int) async throws -> LeaderboardSlice {
        throw GameCenterError.notAuthenticated
    }
    func friendsAuthorizationStatus() async -> FriendsAuthStatus { .denied }
    func requestFriendsAuthorization() async throws -> FriendsAuthStatus { .denied }
}

// MARK: - BoardView extension

extension BoardView {

    // MARK: - Overlay eligibility predicate

    /// True when the board is in a modal context (path == nil) AND the session
    /// has reached .completed — the only condition under which we show the
    /// in-board overlay.
    ///
    /// Gating on `path` (not `#if os(iOS)`) tracks the real presentation
    /// contract: macOS boards inside a NavigationStack have a non-nil path
    /// and use `pushCompletionIfNeeded()` instead. This prevents the
    /// double-present regression where both the overlay AND the push fired.
    var shouldPresentCompletionOverlay: Bool {
        path == nil && viewModel.status == .completed
    }

    // MARK: - Factories (called once per .completed transition)

    /// Construct the post-solve CompletionViewModel from the current terminal
    /// snapshot. Called once on the `.playing → .completed` edge so the
    /// leaderboard-slice fetch + degrade state survive body recomputes.
    /// Mirrors `MinesweeperBoardView.makeCompletionViewModel()`.
    func makeCompletionViewModel() -> CompletionViewModel {
        // #381/#383: leaderboardId is nil for Practice solves → .noLeaderboard.
        let leaderboardId = LiveRouteFactory.leaderboardId(
            forPuzzleId: viewModel.identity.puzzleId
        )
        return CompletionViewModel(
            puzzleId: viewModel.identity.puzzleId,
            elapsedSeconds: viewModel.elapsedSeconds,
            mistakeCount: viewModel.mistakeCount,
            leaderboardId: leaderboardId,
            gameCenter: gameCenter ?? BoardNoopGameCenterClient()
        )
    }

    /// Build the optional Daily reminder primer (#287 Phase 2).
    /// Returns non-nil only when `makeDailyReminderPrimer` was wired AND the
    /// puzzleId is Daily. Practice solves → nil → no primer affordance shown.
    func makeReminderPrimer() -> ReminderPrimerCoordinator? {
        guard LiveRouteFactory.isDaily(puzzleId: viewModel.identity.puzzleId) else {
            return nil
        }
        return makeDailyReminderPrimer?()
    }

    // MARK: - Completion surface

    /// Themed post-solve surface. Covers the whole board on solve.
    ///
    /// Background/content split for safe-area correctness (mirrors MS #518):
    /// background `.ignoresSafeArea()` so no board peeks through at edges;
    /// CompletionView content stays within safe area so the hero icon sits
    /// below the Dynamic Island.
    ///
    /// Close dismisses the overlay by setting `completionViewModel = nil`.
    /// The session stays `.completed` — the macOS push path
    /// (`hasNavigatedToCompletion` latch + `path.append`) is unaffected.
    @ViewBuilder
    func completionSurface(_ cvm: CompletionViewModel) -> some View {
        ZStack {
            theme.surface.background.resolved
                .ignoresSafeArea()
            CompletionView(
                viewModel: cvm,
                reminderPrimer: completionReminderPrimer,
                onClose: { self.completionViewModel = nil }
            )
        }
    }
}
