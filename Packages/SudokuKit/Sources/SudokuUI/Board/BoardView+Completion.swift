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
//
// #667 (SDD-003 2B): the macOS push branch (`pushCompletionIfNeeded()`, path
// != nil) is now gone too — it pushed a SEPARATE `.completion` route whose
// Close only popped that one route, stranding the player on the solved board
// underneath (audit P1). This overlay is the ONE completion presentation on
// every platform; `exitToHub` below picks dismiss-vs-pop by presentation
// context so Close always lands back on the hub.

import SwiftUI
import GameAppKit
import GameShellUI
public import SettingsUI
import SudokuEngine

// MARK: - BoardView extension

extension BoardView {

    // MARK: - Overlay eligibility predicate

    /// True once the live session has reached `.completed` — the in-board
    /// overlay is the ONE completion presentation on every platform.
    ///
    /// #667 (SDD-003 2B): previously gated on `path == nil` (modal-only)
    /// because macOS boards (path != nil, NavigationStack push) instead
    /// pushed a separate `.completion` route. That push's Close only popped
    /// the pushed route, stranding the player on the solved board underneath
    /// (audit P1). The push branch is gone — `path` is now read only by
    /// `exitToHub` to pop the board's own stack entry on Close.
    var shouldPresentCompletionOverlay: Bool {
        viewModel.status == .completed
    }

    // MARK: - Factories (called once per .completed transition)

    /// Construct the post-solve CompletionViewModel from the current terminal
    /// snapshot. Called once on the `.playing → .completed` edge so its state
    /// survives body recomputes. Mirrors `MinesweeperBoardView.makeCompletionViewModel()`.
    func makeCompletionViewModel() -> CompletionViewModel {
        // #381/#383: leaderboardId is nil for Practice solves → .noLeaderboard.
        let leaderboardId = SudokuLeaderboardRouting.leaderboardId(
            forPuzzleId: viewModel.identity.puzzleId
        )
        return CompletionViewModel(
            puzzleId: viewModel.identity.puzzleId,
            elapsedSeconds: viewModel.elapsedSeconds,
            mistakeCount: viewModel.mistakeCount,
            leaderboardId: leaderboardId
        )
    }

    /// Build the optional Daily reminder primer (#287 Phase 2).
    /// Returns non-nil only when `makeDailyReminderPrimer` was wired AND the
    /// puzzleId is Daily. Practice solves → nil → no primer affordance shown.
    func makeReminderPrimer() -> ReminderPrimerCoordinator? {
        guard SudokuLeaderboardRouting.isDaily(puzzleId: viewModel.identity.puzzleId) else {
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
    /// Close exits to the hub on every platform (#667 / audit P1: "Close
    /// always exits to hub"). The dismiss closure is injected by the caller
    /// (BoardView reads `@Environment(\.dismiss)`); `exitToHub` picks between
    /// it and a `path` pop depending on presentation context.
    ///
    /// #652: when `onPlayAgain` is wired, Play Again appears above Close. The
    /// exit-then-play action captures the current difficulty so the new game
    /// matches the just-finished one.
    @ViewBuilder
    func completionSurface(
        _ cvm: CompletionViewModel,
        dismiss: DismissAction
    ) -> some View {
        // #615: the centred-card + bottom-pinned accent-Close layout now lives in
        // the shared `CompletionOverlayScaffold` (GameShellUI) so Minesweeper and
        // future games share it instead of re-deriving it per app.
        let difficulty = viewModel.identity.difficulty
        CompletionOverlayScaffold(
            onClose: {
                self.completionViewModel = nil
                exitToHub(dismiss: dismiss)
            },
            onPlayAgain: onPlayAgain.map { playAgain in
                // #652: exit the current board then start a fresh game at the
                // same difficulty. `exitToHub` tears down the presentation (cover
                // dismiss on iOS, stack pop on macOS) so the hub is visible
                // before the new board modal is presented.
                {
                    self.completionViewModel = nil
                    exitToHub(dismiss: dismiss)
                    playAgain(difficulty)
                }
            },
            card: {
                CompletionView(
                    viewModel: cvm,
                    reminderPrimer: completionReminderPrimer,
                    onClose: nil
                )
            }
        )
    }

    /// #667 (SDD-003 2B): unified "return to hub" for the completion overlay's
    /// Close (and Play Again's pre-relaunch teardown), now shared by BOTH
    /// presentation contexts since the overlay is the only completion surface.
    ///
    /// - Modal context (path == nil, iOS fullScreenCover): `dismiss()` tears
    ///   down the cover, same as #610 fix *2.
    /// - Push context (path != nil, macOS NavigationStack): the board itself is
    ///   the top stack entry (no `.completion` route is pushed on top of it
    ///   anymore), so popping ONE entry lands the player back on whatever hub
    ///   pushed the board — never stranded on the solved board (audit P1).
    func exitToHub(dismiss: DismissAction) {
        guard let path else {
            dismiss()
            return
        }
        guard !path.wrappedValue.isEmpty else { return }
        path.wrappedValue.removeLast()
    }
}
