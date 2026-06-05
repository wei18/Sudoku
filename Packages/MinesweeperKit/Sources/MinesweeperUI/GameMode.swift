// GameMode — coarse Minesweeper game-mode classification (daily vs practice).
//
// Mirror of Sudoku's `SudokuEngine.Mode` (daily / practice), introduced for
// #329 so the GC best-time submit can be gated to daily-mode only — the same
// gate Sudoku's `GameCenterSink` applies (`guard mode == .daily`). Sudoku's
// `Mode` lives in `SudokuCoreKit`, which MinesweeperUI does not depend on; a
// local 2-case leaf enum keeps the cross-game coupling out while preserving
// the identical daily/practice semantics.
//
// Threaded into `AppRoute.board(difficulty:seed:mode:)` so it originates at the
// navigation seam (Daily hub → `.daily`, Practice hub / New Game → `.practice`)
// and reaches `MinesweeperGameViewModel`, mirroring how Sudoku threads its mode
// from the puzzle's origin down to the submit gate.

public enum GameMode: String, Sendable, Equatable, Hashable, CaseIterable {
    case daily
    case practice
}
