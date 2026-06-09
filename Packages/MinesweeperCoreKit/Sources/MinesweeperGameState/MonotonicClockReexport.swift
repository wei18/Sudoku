// Re-export the shared `MonotonicClock` / `LiveMonotonicClock` from the
// TimeKit leaf (#446).
//
// The clock seam moved out of MinesweeperGameState — where it was a byte-copy
// of the Sudoku original — into the game-agnostic `TimeKit` leaf both cores
// share. MinesweeperGameState's consumers (MinesweeperSession, tests'
// `FakeClock`) reach `MonotonicClock` / `LiveMonotonicClock` through
// `import MinesweeperGameState`; re-exporting TimeKit here keeps those call
// sites byte-identical.

@_exported public import TimeKit
