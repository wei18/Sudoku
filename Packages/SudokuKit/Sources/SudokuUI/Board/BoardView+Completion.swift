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
public import SudokuEngine

// MARK: - Daily "more today?" resolution (#1023)

/// Resolved once per Daily solve via `BoardView.fetchDailyProgress`, mirrors
/// `MinesweeperKit`'s equivalent MS-side type. Not `Difficulty`-generic across
/// apps because `CompletionContext` (GameShellUI) only ever sees the already-
/// formatted label + presenter closure — see `completionSurface` below.
public enum DailyCompletionProgress: Sendable, Equatable {
    /// Another difficulty is still open today.
    case moreToday(difficulty: Difficulty, puzzleId: String)
    /// Nothing left to play today.
    case allDone
}

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

    // MARK: - Overlay presentation key (#763 / #1020)

    /// Which full-screen-intent overlay this board is showing, or `nil` for
    /// none. Passed as the single `presentation` argument to
    /// `.boardModalOverlay(presentation:content:)`, which drives BOTH the
    /// rendering and — when the board is pushed inside a tab — the hoisted copy
    /// the shell shows outside its `TabView`. One value, so the two cannot
    /// drift (#763's hand-maintained invariant is now structural).
    ///
    /// The branch ORDER matters and mirrors the `content` closure's: completion
    /// wins once the session is terminal. Because the key changes on a
    /// branch-to-branch switch (not just on appear/disappear), the hoisted copy
    /// re-registers instead of stranding the previous branch's snapshot.
    var modalOverlayPresentation: BoardModalPresentation? {
        if completionViewModel != nil { return .completion }
        if viewModel.isPaused { return .pause }
        if showReadyLeaveOverlay { return .leaveConfirmation }
        return nil
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
    /// #1023: resolve the Daily "more today?" CTA row. Fire-and-await into
    /// `dailyCompletionProgress` (`@State`, starts `.allDone` — never
    /// overclaims a "Next" mid-fetch) — called from BoardView's `.onChange`
    /// on the `.completed` transition.
    func kickOffDailyProgressFetch() {
        guard SudokuLeaderboardRouting.isDaily(puzzleId: viewModel.identity.puzzleId), let fetchDailyProgress else { return }
        Task { @MainActor in
            dailyCompletionProgress = await fetchDailyProgress()
        }
    }

    @ViewBuilder
    func completionSurface(
        _ cvm: CompletionViewModel,
        dismiss: DismissAction,
        persistJoin: TerminalPersistJoin?
    ) -> some View {
        // #615: the centred-card + bottom-pinned accent-Close layout now lives in
        // the shared `CompletionOverlayScaffold` (GameShellUI) so Minesweeper and
        // future games share it instead of re-deriving it per app.
        // #1023: full-height glass panel + variant/context — the live overlay is
        // ALWAYS `.liveSolve` (this is the one path that fires right after the
        // solve that just happened); Sudoku is solve-only, so the outcome is
        // always `.success`.
        let difficulty = viewModel.identity.difficulty
        let closeAction: () -> Void = {
            self.completionViewModel = nil
            // #823: register before tearing down — synchronous, adds no
            // latency to Close — so the teardown-triggered hub refresh
            // waits (bounded) for this save to land.
            persistJoin?.register(viewModel.pendingTerminalPersistTask)
            exitToHub(dismiss: dismiss)
        }
        CompletionOverlayScaffold(
            variant: .liveSolve,
            outcomeKind: .success,
            context: completionContext(closeAction: closeAction, difficulty: difficulty),
            onClose: closeAction,
            card: {
                CompletionView(
                    viewModel: cvm,
                    reminderPrimer: completionReminderPrimer,
                    onClose: nil
                )
            }
        )
    }

    /// §3.5's 4-row CTA table, minus the MS-only `.loss` row (Sudoku is
    /// solve-only). Daily picks `.dailyMoreToday`/`.dailyAllDone` from the
    /// `dailyCompletionProgress` resolved by `fetchDailyProgress`; Practice
    /// picks `.practice`, forwarding `onPlayAgain` unchanged (nil when no
    /// presenter is wired, same fallback as before #1023).
    private func completionContext(closeAction: @escaping () -> Void, difficulty: Difficulty) -> CompletionContext {
        guard SudokuLeaderboardRouting.isDaily(puzzleId: viewModel.identity.puzzleId) else {
            return .practice(onPlayAgain: onPlayAgain.map { playAgain in
                // #652: exit the current board then start a fresh game at the
                // same difficulty. `exitToHub` tears down the presentation (cover
                // dismiss on iOS, stack pop on macOS) so the hub is visible
                // before the new board modal is presented.
                {
                    closeAction()
                    playAgain(difficulty)
                }
            })
        }
        switch dailyCompletionProgress {
        case .moreToday(let nextDifficulty, let nextPuzzleId):
            guard let onDailyNext else { return .dailyAllDone }
            return .dailyMoreToday(
                nextDifficultyLabel: LocalizedStringKey(nextDifficulty.rawValue.capitalized),
                onNext: {
                    closeAction()
                    onDailyNext(nextPuzzleId)
                }
            )
        case .allDone:
            return .dailyAllDone
        }
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
