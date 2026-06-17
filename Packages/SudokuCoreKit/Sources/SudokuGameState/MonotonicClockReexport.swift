// Re-export the shared `MonotonicClock` / `LiveMonotonicClock` from the
// TimeKit leaf (#446).
//
// The clock seam moved out of SudokuGameState into the game-agnostic `TimeKit` leaf
// so it can be shared with MinesweeperGameState without duplication / drift.
// SudokuGameState's existing consumers (GameSession, SudokuAppComposition, tests'
// `FakeMonotonicClock`) reach `MonotonicClock` / `LiveMonotonicClock` through
// `import SudokuGameState`; re-exporting TimeKit here keeps those call sites
// byte-identical.

@_exported public import TimeKit
