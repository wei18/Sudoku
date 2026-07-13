// MinesweeperBoardViewModalOverlayActiveTests — locks
// `MinesweeperBoardView.isModalOverlayActive` (#763): true exactly when the
// board's own `.overlay` shows the completion surface, the pause menu, or
// the pre-first-tap idle "Leave Game?" cover. `NavigationStackHost`
// (GameShellUI) masks the macOS sidebar off this signal — see
// ModalOverlayPreference.swift — so a wrong value here means the sidebar
// silently stops being masked (or gets masked when it shouldn't).
//
// Uses the `MinesweeperGameViewModel(seeded:)` snapshot seam (same one
// MinesweeperBoardTerminalOverlaySnapshotTests uses) so each state is
// constructed directly rather than driven through a live session actor.

import Testing
@testable import MinesweeperUI

import MinesweeperEngine
import MinesweeperGameState

@MainActor
@Suite("MinesweeperBoardView — isModalOverlayActive (#763)")
struct MinesweeperBoardViewModalOverlayActiveTests {

    private static let cols = Difficulty.beginner.columns
    private static let rows = Difficulty.beginner.rows

    private func hiddenCells() -> [Cell] {
        Array(repeating: Cell(state: .hidden), count: Self.rows * Self.cols)
    }

    private func snapshot(status: MinesweeperSessionStatus) -> MinesweeperSessionSnapshot {
        MinesweeperSessionSnapshot(
            difficulty: .beginner,
            cells: hiddenCells(),
            status: status,
            elapsedSeconds: 12,
            mineCount: Difficulty.beginner.mineCount,
            flagCount: 0
        )
    }

    @Test("false while playing — no overlay, sidebar stays live")
    func falseWhilePlaying() {
        let boardView = MinesweeperBoardView(
            viewModel: MinesweeperGameViewModel(seeded: snapshot(status: .playing)),
            suppressTickerForSnapshot: true
        )
        #expect(!boardView.isModalOverlayActive)
    }

    @Test("true while paused — the pause overlay is up")
    func trueWhilePaused() {
        let boardView = MinesweeperBoardView(
            viewModel: MinesweeperGameViewModel(seeded: snapshot(status: .paused)),
            suppressTickerForSnapshot: true
        )
        #expect(boardView.isModalOverlayActive)
    }

    @Test("false on a terminal (.lost) board when the completion VM has not been built yet")
    func falseWhenTerminalWithoutCompletionViewModel() {
        // Mirrors production: `.overlay` gates the completion surface on
        // `completionViewModel != nil`, not `isTerminal` alone — the VM is
        // seeded lazily via `.onChange`/`.task`, which this seam skips.
        let boardView = MinesweeperBoardView(
            viewModel: MinesweeperGameViewModel(seeded: snapshot(status: .lost)),
            suppressTickerForSnapshot: true
        )
        #expect(!boardView.isModalOverlayActive)
    }

    @Test("true on a terminal (.lost) board once the completion VM is pre-seeded")
    func trueWhenTerminalWithCompletionViewModel() {
        let completionVM = MinesweeperCompletionViewModel(
            didWin: false,
            elapsedSeconds: 12,
            leaderboardId: MinesweeperLeaderboardID.easyDaily
        )
        let boardView = MinesweeperBoardView(
            viewModel: MinesweeperGameViewModel(seeded: snapshot(status: .lost)),
            suppressTickerForSnapshot: true,
            completionViewModelForSnapshot: completionVM
        )
        #expect(boardView.isModalOverlayActive)
    }

    @Test("false while idle and the header ✕ hasn't been tapped yet")
    func falseWhileIdleWithoutLeaveOverlay() {
        // #681's `showIdleLeaveOverlay` branch (tapped via the header ✕ on a
        // pre-first-tap board) has no init-time seam — like `tapModeStore` in
        // MinesweeperBoardViewTapModeTests, this repo's test infra has no
        // SwiftUI render-tree introspection to drive that tap, and directly
        // assigning `@State` post-init is a documented no-op outside a live
        // render tree (confirmed against `completionViewModelForSnapshot`'s
        // sibling case above). This test locks the one sub-case that IS
        // reachable: idle alone must not report an active overlay.
        let boardView = MinesweeperBoardView(
            viewModel: MinesweeperGameViewModel(seeded: snapshot(status: .idle)),
            suppressTickerForSnapshot: true
        )
        #expect(!boardView.isModalOverlayActive,
                "idle alone (before the header ✕ is tapped) must not report an active overlay")
    }
}
