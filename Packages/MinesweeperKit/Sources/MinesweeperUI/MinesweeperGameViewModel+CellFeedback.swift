// MinesweeperGameViewModel+CellFeedback — the Minesweeper view-model half of
// the region-reveal wave (#1018, design.md §6 M13). A reveal that newly
// reveals MORE THAN ONE safe cell and did not lose the game begins one event
// in the shared `CellFeedbackState`; the event expires on its own after
// `CellFeedbackMotionPlan.regionRevealLifetime`.
//
// Hard constraint: feedback must never block or drop input. The view model
// only WRITES to `cellFeedback` — `reveal`, `toggleFlag` and every other input
// path neither read it nor await the expiry task. Newly revealed cells are
// found by comparing the cells before and after the reveal; the session API
// and MinesweeperCoreKit are untouched.

public import GameShellUI
import MinesweeperEngine

/// A flood reveal: the tapped origin and, for every cell this reveal newly
/// revealed, its ring (Chebyshev distance from the origin).
public struct MinesweeperRevealEvent: Sendable, Equatable {
    public let originRow: Int
    public let originColumn: Int
    /// Grid width, to map a flat index back to (row, column).
    public let columns: Int
    /// Ring of every newly revealed cell, keyed by flat index (`row * columns + col`).
    public let rings: [Int: Int]
    /// The largest ring in `rings`.
    public let maxRing: Int

    /// The cell's ring, or `nil` when this reveal did not newly reveal it.
    public func ring(row: Int, col: Int) -> Int? {
        rings[row * columns + col]
    }
}

extension MinesweeperGameViewModel {
    /// Begin one reveal-wave event if the reveal at (`row`, `col`) newly
    /// revealed more than one cell and did not lose the game. `before` is the
    /// cell array from before the reveal. Write-only: the expiry task is held by
    /// `cellFeedback` itself (`pendingExpiries`) and is never awaited here.
    func beginRevealWaveFeedback(row: Int, col: Int, before: [Cell]) {
        let after = snapshot.cells
        guard snapshot.status != .lost, before.count == after.count else { return }
        let columns = snapshot.columns
        var rings: [Int: Int] = [:]
        var maxRing = 0
        for index in after.indices where before[index].state != .revealed && after[index].state == .revealed {
            let ring = max(abs(index / columns - row), abs(index % columns - col))
            rings[index] = ring
            maxRing = max(maxRing, ring)
        }
        guard rings.count > 1 else { return }
        cellFeedback.begin(
            MinesweeperRevealEvent(originRow: row, originColumn: col, columns: columns, rings: rings, maxRing: maxRing),
            lifetime: CellFeedbackMotionPlan.regionRevealLifetime,
            sleeper: cellFeedbackSleeper
        )
    }
}
