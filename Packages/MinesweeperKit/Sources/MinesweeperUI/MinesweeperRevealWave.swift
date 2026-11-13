// MinesweeperRevealWave — the per-cell input of the #1018 region-reveal wave
// (design.md §6 M13). `MinesweeperBoardView` resolves one of these for every
// cell that belongs to an active `MinesweeperRevealEvent` and hands it to
// `MinesweeperCellButton`; every other cell gets `nil` and behaves exactly as
// it did before the wave existed.
//
// Only the `.wave` form produces a value. Under Reduce Motion the plan's form
// is `.simultaneous`: no delay and no added animation, so the existing
// `MotionGate` leaves the reveal instant and all cells appear in one frame.

import GameShellUI

struct MinesweeperRevealWave: Equatable {
    /// Seconds this cell waits before its reveal starts.
    let delay: Double
    /// Seconds the cell's own reveal takes.
    let fade: Double

    /// The wave input for the cell at (`row`, `col`): taken from the most
    /// recently begun event that newly revealed it, or `nil` when no active
    /// event did, or when the plan is not a wave.
    nonisolated static func resolve(
        form: CellFeedbackMotionPlan.RegionRevealForm,
        entries: [CellFeedbackState<MinesweeperRevealEvent>.Entry],
        row: Int,
        col: Int
    ) -> MinesweeperRevealWave? {
        guard case let .wave(_, cellDuration, _) = form else { return nil }
        for entry in entries.reversed() {
            if let ring = entry.event.ring(row: row, col: col) {
                return MinesweeperRevealWave(
                    delay: form.delay(ring: ring, maxRing: entry.event.maxRing),
                    fade: cellDuration
                )
            }
        }
        return nil
    }
}
