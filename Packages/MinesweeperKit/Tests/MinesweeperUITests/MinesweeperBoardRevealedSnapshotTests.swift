// MinesweeperBoardRevealedSnapshotTests — revealed-state visual baselines (#297).
//
// The covered-board baselines (MinesweeperBoardSnapshotTests) only exercise the
// covered-cell token + chrome. This suite covers the states that the in-body
// `.task { refresh() }` previously made impossible to capture deterministically:
//
//   - mid-reveal: revealed cells carrying the full 1–8 neighbor-count palette,
//     so the MS number-token hex values are verified by RENDERED PIXELS rather
//     than code inspection (#297's whole point);
//   - mineHit: a detonated mine (bold `mineHit` red) with the other mines
//     surfaced (soft `mine` fill) — the loss board;
//   - flagged: a board with flagged + revealed + covered cells mid-game.
//
// Seam (#297): `MinesweeperGameViewModel(seeded:)` installs a fixed snapshot
// whose `refresh()` is a no-op, and `MinesweeperBoardView(...,
// suppressTickerForSnapshot: true)` skips the in-body ticker so the seed
// survives NSHostingView capture and the Completion overlay isn't drawn over
// the loss board. Production never sets either — the live refresh path is
// untouched.

#if canImport(AppKit)
import Foundation
import SnapshotTesting
import SwiftUI
import Testing
@testable import MinesweeperUI

import MinesweeperEngine
import MinesweeperGameState

@MainActor
@Suite("MinesweeperBoardView — revealed-state snapshots")
struct MinesweeperBoardRevealedSnapshotTests {

    // MARK: - Fixtures

    private static let cols = Difficulty.beginner.columns // 9
    private static let rows = Difficulty.beginner.rows     // 9

    /// Build a seeded board view for a fully-formed beginner snapshot.
    private func seededBoard(
        cells: [Cell],
        status: MinesweeperSessionStatus,
        elapsedSeconds: Int = 42,
        flagCount: Int = 0
    ) -> MinesweeperBoardView {
        let snapshot = MinesweeperSessionSnapshot(
            difficulty: .beginner,
            cells: cells,
            status: status,
            elapsedSeconds: elapsedSeconds,
            mineCount: Difficulty.beginner.mineCount,
            flagCount: flagCount
        )
        return MinesweeperBoardView(
            viewModel: MinesweeperGameViewModel(seeded: snapshot),
            suppressTickerForSnapshot: true,
            tapModeDefaults: BoardTestDefaults.store
        )
    }

    /// A 9×9 board whose top two rows surface every neighbor-count 1…8 as a
    /// revealed numbered cell (verifying the full MS number palette), with the
    /// remaining rows a mix of revealed-empty + covered cells.
    private func midRevealCells() -> [Cell] {
        var cells = Array(repeating: Cell(state: .hidden), count: Self.rows * Self.cols)
        // Row 0: counts 1…8 across the first 8 columns; col 8 stays covered.
        for count in 1...8 {
            cells[index(row: 0, col: count - 1)] = Cell(
                neighborMineCount: count, state: .revealed
            )
        }
        // Row 1: a revealed-empty (0-count) run so the revealed bg token reads.
        for col in 0..<6 {
            cells[index(row: 1, col: col)] = Cell(neighborMineCount: 0, state: .revealed)
        }
        // Row 2: a few mid-range counts to balance the composition.
        cells[index(row: 2, col: 0)] = Cell(neighborMineCount: 3, state: .revealed)
        cells[index(row: 2, col: 1)] = Cell(neighborMineCount: 1, state: .revealed)
        cells[index(row: 2, col: 2)] = Cell(neighborMineCount: 2, state: .revealed)
        return cells
    }

    /// A loss board: one detonated mine (revealed + isMine → bold mineHit),
    /// one still-hidden mine (surfaced as soft `mine` fill because
    /// `revealMines` is on for `.lost`), and one correctly-flagged mine
    /// (also surfaced on `mine` fill, but drawing the flag glyph in
    /// `tokens.lostMineFlagInk` rather than the mine glyph — #876 / #874 F-1),
    /// surrounded by revealed numbers.
    private func mineHitCells() -> [Cell] {
        var cells = midRevealCells()
        // Detonated cell (the one the player hit): revealed mine → mineHit red.
        cells[index(row: 4, col: 4)] = Cell(isMine: true, state: .revealed)
        // Still-hidden mine: surfaced on loss via the board's revealMines path.
        cells[index(row: 5, col: 2)] = Cell(isMine: true, state: .hidden)
        // Correctly-flagged mine, surfaced on loss (#876 combo).
        cells[index(row: 6, col: 7)] = Cell(isMine: true, state: .flagged)
        return cells
    }

    /// A mid-game board with flagged cells alongside revealed numbers + covers.
    private func flaggedCells() -> [Cell] {
        var cells = midRevealCells()
        cells[index(row: 3, col: 0)] = Cell(state: .flagged)
        cells[index(row: 3, col: 2)] = Cell(state: .flagged)
        cells[index(row: 4, col: 1)] = Cell(state: .flagged)
        return cells
    }

    private func index(row: Int, col: Int) -> Int { row * Self.cols + col }

    // MARK: - Mid-reveal (1–8 palette)

    @Test(.enabled(if: !SnapshotEnv.isXcodeCloud))
    func snapshotMidReveal_iPhone_light() {
        let view = seededBoard(cells: midRevealCells(), status: .playing)
        assertUISnapshot(
            of: hostingView(view, size: SnapshotLayouts.iPhone, colorScheme: .light),
            as: .tolerantImage,
            named: "Board-iPhone-light-beginner-midReveal",
            record: SnapshotMode.recordMode
        )
    }

    @Test(.enabled(if: !SnapshotEnv.isXcodeCloud))
    func snapshotMidReveal_iPhone_dark() {
        let view = seededBoard(cells: midRevealCells(), status: .playing)
        assertUISnapshot(
            of: hostingView(view, size: SnapshotLayouts.iPhone, colorScheme: .dark),
            as: .tolerantImage,
            named: "Board-iPhone-dark-beginner-midReveal",
            record: SnapshotMode.recordMode
        )
    }

    // MARK: - mineHit (loss board)

    @Test(.enabled(if: !SnapshotEnv.isXcodeCloud))
    func snapshotMineHit_iPhone_light() {
        let view = seededBoard(cells: mineHitCells(), status: .lost)
        assertUISnapshot(
            of: hostingView(view, size: SnapshotLayouts.iPhone, colorScheme: .light),
            as: .tolerantImage,
            named: "Board-iPhone-light-beginner-mineHit",
            record: SnapshotMode.recordMode
        )
    }

    @Test(.enabled(if: !SnapshotEnv.isXcodeCloud))
    func snapshotMineHit_iPhone_dark() {
        let view = seededBoard(cells: mineHitCells(), status: .lost)
        assertUISnapshot(
            of: hostingView(view, size: SnapshotLayouts.iPhone, colorScheme: .dark),
            as: .tolerantImage,
            named: "Board-iPhone-dark-beginner-mineHit",
            record: SnapshotMode.recordMode
        )
    }

    // MARK: - Flagged cells

    @Test(.enabled(if: !SnapshotEnv.isXcodeCloud))
    func snapshotFlagged_iPhone_light() {
        let view = seededBoard(cells: flaggedCells(), status: .playing, flagCount: 3)
        assertUISnapshot(
            of: hostingView(view, size: SnapshotLayouts.iPhone, colorScheme: .light),
            as: .tolerantImage,
            named: "Board-iPhone-light-beginner-flagged",
            record: SnapshotMode.recordMode
        )
    }

    @Test(.enabled(if: !SnapshotEnv.isXcodeCloud))
    func snapshotFlagged_iPhone_dark() {
        let view = seededBoard(cells: flaggedCells(), status: .playing, flagCount: 3)
        assertUISnapshot(
            of: hostingView(view, size: SnapshotLayouts.iPhone, colorScheme: .dark),
            as: .tolerantImage,
            named: "Board-iPhone-dark-beginner-flagged",
            record: SnapshotMode.recordMode
        )
    }
}
#endif
