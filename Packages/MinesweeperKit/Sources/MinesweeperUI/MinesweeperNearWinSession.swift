// MinesweeperNearWinSession — DEBUG-only near-win session builder (#510 uitest hook).
//
// Produces a `MinesweeperGameViewModel` with all safe cells revealed except ONE,
// so a single reveal tap triggers the real win → completion flow.
//
// Strategy:
//   1. Build a fresh `MinesweeperEngine` with a deterministic seed.
//   2. Simulate one reveal (first click places mines safely) to get the full
//      mine layout via the engine's deferred placement.
//   3. Build a `cells` array where every non-mine, non-first cell is revealed.
//   4. Restore a `MinesweeperSession` from a snapshot encoding this state,
//      status `.paused`, so the player taps one safe cell to win.
//
// Determinism: the seed + first-click (0,0) are fixed, so the near-win board
// is identical on every cold launch.
//
// Availability: `#if DEBUG` only — stripped from Release builds entirely.

#if DEBUG

import Foundation
import MinesweeperEngine
import MinesweeperGameState

/// A fully-specified Minesweeper near-win scenario.
///
/// `viewModel` has a paused session where all safe cells are revealed except
/// `lastSafeRow`/`lastSafeCol`. A single tap on that cell wins the game.
@MainActor
public struct MinesweeperNearWinSession: Identifiable {
    /// Stable identity so the cover can be presented via
    /// `fullScreenCover(item:)` — atomic with the data, avoiding the
    /// `isPresented` + separate-optional-state presentation race (#523).
    public nonisolated var id: Int { lastSafeRow * 1_000 + lastSafeCol }
    public let viewModel: MinesweeperGameViewModel
    /// Row of the ONE remaining unrevealed safe cell.
    public let lastSafeRow: Int
    /// Column of the ONE remaining unrevealed safe cell.
    public let lastSafeCol: Int
}

extension MinesweeperNearWinSession {

    /// Deterministic seed for the near-win board. Well-known, collision-free
    /// with the daily seed derivation path (which folds a date string in).
    public static let nearWinSeed: UInt64 = 0xAABB_CCDD_EEFF_0011

    /// Build a near-win `MinesweeperGameViewModel`. Async because
    /// `MinesweeperSession.restore(from:)` is actor-isolated.
    public static func build() async -> MinesweeperNearWinSession {
        let difficulty = Difficulty.beginner
        // Build the engine and place mines via a simulated first reveal at (0,0).
        // `MinesweeperEngine` is a value type; mutation is synchronous.
        var engine = MinesweeperEngine(difficulty: difficulty, seed: nearWinSeed)
        // Place mines safely around (0,0) — this mutates the engine in place.
        // The first reveal returns the flood-revealed cells but we don't need them.
        _ = try? engine.reveal(row: 0, col: 0)

        // Build cells with all safe (non-mine) cells revealed except the last one.
        var cells = engine.cells
        var lastSafeRow = 0
        var lastSafeCol = 0

        // Collect safe hidden cell indices (all non-mine cells that are still
        // hidden after the first reveal / flood-fill).
        var hiddenSafeIndices: [(row: Int, col: Int)] = []
        for row in 0..<engine.rows {
            for col in 0..<engine.columns {
                let idx = engine.index(row: row, col: col)
                let cell = cells[idx]
                if !cell.isMine && cell.state == .hidden {
                    hiddenSafeIndices.append((row, col))
                }
            }
        }

        // Reveal all hidden safe cells except the last one.
        if let lastSafe = hiddenSafeIndices.last {
            lastSafeRow = lastSafe.row
            lastSafeCol = lastSafe.col
            for (row, col) in hiddenSafeIndices.dropLast() {
                let idx = engine.index(row: row, col: col)
                cells[idx].state = .revealed
            }
        }

        // Build the snapshot encoding this near-win board. Status `.paused` so
        // the board mounts under its pause-cover overlay, then the player taps
        // to resume and reveals the final safe cell.
        let snapshot = MinesweeperSessionSnapshot(
            difficulty: difficulty,
            seed: nearWinSeed,
            cells: cells,
            status: .paused,
            elapsedSeconds: 0,
            mineCount: engine.mineCount,
            flagCount: 0
        )
        let session = await MinesweeperSession.restore(from: snapshot)

        let viewModel = MinesweeperGameViewModel(
            session: session,
            mode: .practice
            // store: nil, recordName: nil — uitest boards never persist.
        )

        return MinesweeperNearWinSession(
            viewModel: viewModel,
            lastSafeRow: lastSafeRow,
            lastSafeCol: lastSafeCol
        )
    }
}

#endif
