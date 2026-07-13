// MinesweeperBoardTerminalOverlaySnapshotTests — terminal board WITH the
// Completion overlay mounted (#388 / #315).
//
// Keeps `.tolerantImage` (#487/#517): a COMPOSITION guard over a live AA-heavy
// `.lost` board (strict would false-fail on cell antialiasing). The overlay's
// TEXT content is gated strictly by MinesweeperCompletionSnapshotTests.
//
// The existing CompletionView baselines (MinesweeperCompletionSnapshotTests)
// render the surface in ISOLATION. The existing loss-board baseline
// (MinesweeperBoardRevealedSnapshotTests `mineHit`) renders the exploded board
// WITHOUT the overlay (the in-body `.task` is suppressed, so the overlay VM is
// never seeded). Neither exercised the actual production composition — the
// Completion surface overlaid on the live terminal board — which is exactly
// where #388's "16pt border / board shows through" bug lived.
//
// This suite renders that composition: a seeded `.lost` board + a pre-seeded
// Completion VM (via the `completionViewModelForSnapshot` seam), so the overlay
// mounts over the board. The baseline is the regression guard for #388: the
// surface must fully cover the board with no inset border revealing the live
// exploded grid underneath.
//
// VERIFICATION LIMIT (honest): NSHostingView has no safe-area insets on macOS,
// so `.ignoresSafeArea()` is a no-op in this harness — this snapshot proves the
// surface fills its CONTAINER FRAME edge-to-edge (the 16pt-border regression),
// but it CANNOT prove status-bar / home-indicator safe-area coverage. That part
// still needs visual confirmation in an iOS simulator.
//
// #396 (intentional byte-identity, NOT false coverage): these two goldens are
// byte-identical to `MinesweeperCompletionSnapshotTests.snapshotLoss_iPhone_*`
// — and that equality IS the assertion. Both render the SAME completion VM
// (didWin:false, elapsed:65, easyDaily, `.unauthenticated`); the difference is
// the COMPOSITION — here the surface is overlaid on a live `.lost` board, there
// it is the bare surface. If the overlay fully covers the board (the #388 fix),
// the board cannot bleed through, so the composited pixels MUST equal the bare
// surface. A future regression that lets the board show through the border
// would make this golden differ from its own recorded baseline → red. Kept as a
// distinct composition guard; the equality with the bare loss golden is the
// pass condition, not a redundant duplicate.

#if canImport(AppKit)
import Foundation
import SnapshotTesting
import SwiftUI
import Testing
@testable import MinesweeperUI

import MinesweeperEngine
import MinesweeperGameState

@MainActor
@Suite("MinesweeperBoardView — terminal overlay snapshots")
struct MinesweeperBoardTerminalOverlaySnapshotTests {

    private static let cols = Difficulty.beginner.columns // 9
    private static let rows = Difficulty.beginner.rows     // 9

    private func index(row: Int, col: Int) -> Int { row * Self.cols + col }

    /// A loss board: a detonated mine plus a couple of surfaced mines and a few
    /// revealed numbers, so the live grid underneath is clearly non-empty. If the
    /// overlay ever fails to cover, this grid would show through the border.
    private func mineHitCells() -> [Cell] {
        var cells = Array(repeating: Cell(state: .hidden), count: Self.rows * Self.cols)
        for count in 1...8 {
            cells[index(row: 0, col: count - 1)] = Cell(neighborMineCount: count, state: .revealed)
        }
        cells[index(row: 4, col: 4)] = Cell(isMine: true, state: .revealed)
        cells[index(row: 5, col: 2)] = Cell(isMine: true, state: .hidden)
        cells[index(row: 6, col: 7)] = Cell(isMine: true, state: .hidden)
        return cells
    }

    /// A seeded `.lost` board with the Completion overlay pre-mounted via the
    /// snapshot seam, so the rendered tree is the production overlay composition.
    private func terminalBoardWithOverlay(colorScheme: ColorScheme) -> some View {
        let snapshot = MinesweeperSessionSnapshot(
            difficulty: .beginner,
            cells: mineHitCells(),
            status: .lost,
            elapsedSeconds: 65,
            mineCount: Difficulty.beginner.mineCount,
            flagCount: 0
        )
        let completionVM = MinesweeperCompletionViewModel(
            didWin: false,
            elapsedSeconds: 65,
            leaderboardId: MinesweeperLeaderboardID.easyDaily
        )
        return MinesweeperBoardView(
            viewModel: MinesweeperGameViewModel(seeded: snapshot),
            suppressTickerForSnapshot: true,
            completionViewModelForSnapshot: completionVM,
            tapModeDefaults: BoardTestDefaults.store
        )
    }

    @Test(.enabled(if: !SnapshotEnv.isXcodeCloud))
    func snapshotTerminalOverlay_iPhone_light() {
        assertUISnapshot(
            of: hostingView(
                terminalBoardWithOverlay(colorScheme: .light),
                size: SnapshotLayouts.iPhone,
                colorScheme: .light
            ),
            as: .tolerantImage,
            named: "Board-iPhone-light-terminal-overlay",
            record: SnapshotMode.recordMode
        )
    }

    @Test(.enabled(if: !SnapshotEnv.isXcodeCloud))
    func snapshotTerminalOverlay_iPhone_dark() {
        assertUISnapshot(
            of: hostingView(
                terminalBoardWithOverlay(colorScheme: .dark),
                size: SnapshotLayouts.iPhone,
                colorScheme: .dark
            ),
            as: .tolerantImage,
            named: "Board-iPhone-dark-terminal-overlay",
            record: SnapshotMode.recordMode
        )
    }
}
#endif
