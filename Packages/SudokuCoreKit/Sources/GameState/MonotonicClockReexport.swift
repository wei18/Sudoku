// Re-export the shared `MonotonicClock` / `LiveMonotonicClock` from the
// TimeKit leaf (#446).
//
// The clock seam moved out of GameState into the game-agnostic `TimeKit` leaf
// so it can be shared with MinesweeperGameState without duplication / drift.
// GameState's existing consumers (GameSession, AppComposition, tests'
// `FakeMonotonicClock`) reach `MonotonicClock` / `LiveMonotonicClock` through
// `import GameState`; re-exporting TimeKit here keeps those call sites
// byte-identical.

@_exported public import TimeKit
