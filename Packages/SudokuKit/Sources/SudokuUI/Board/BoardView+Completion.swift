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
    /// Layout (#610 fix *1): result card is vertically centred; the Close button
    /// is pinned to the BOTTOM safe area so content never crowds the top and the
    /// CTA is always reachable with the thumb.
    ///
    /// Background fills the whole screen via `.ignoresSafeArea()` so no board
    /// peeks through at edges; the result card and close button stay within the
    /// safe area. Mirrors MinesweeperBoardView.completionSurface (#292 / #518).
    ///
    /// Close dismisses the overlay AND the fullScreenCover so the user returns
    /// to the hub (#610 fix *2). The dismiss closure is injected by the caller
    /// (BoardView reads `@Environment(\.dismiss)`).
    @ViewBuilder
    func completionSurface(
        _ cvm: CompletionViewModel,
        dismiss: DismissAction
    ) -> some View {
        ZStack(alignment: .bottom) {
            theme.surface.background.resolved
                .ignoresSafeArea()
            VStack(spacing: 0) {
                Spacer()
                // Result card — CompletionView with no injected close button;
                // the button is rendered separately below, pinned to the bottom.
                //
                // `.fixedSize(horizontal: false, vertical: true)` prevents
                // CompletionScreen's `.frame(maxHeight: .infinity)` from expanding
                // the card to fill the available height, which would collapse the
                // top Spacer() to zero and stick the card at the top (#610 sim fix).
                CompletionView(
                    viewModel: cvm,
                    reminderPrimer: completionReminderPrimer,
                    onClose: nil
                )
                .fixedSize(horizontal: false, vertical: true)
                Spacer()
                // Close button (#610 fix *1 + *4): full-width, ~52pt tall,
                // sage-green brand accent instead of system blue.
                // Pinned to the bottom safe area.
                Button {
                    // #610 fix *2: clear the overlay then dismiss the fullScreenCover
                    // so the user returns to the hub. On macOS (path != nil) this
                    // path is never reached — the predicate gates the overlay to
                    // path == nil only.
                    self.completionViewModel = nil
                    dismiss()
                } label: {
                    Text("Close")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(theme.accent.primary.resolved)
                .controlSize(.large)
                .padding(.horizontal, 32)
                .padding(.bottom, 16)
            }
        }
    }
}
