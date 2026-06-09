// Re-export the shared `UTCDay` from the TimeKit leaf (#305).
//
// `UTCDay` moved out of SudokuEngine into the game-agnostic `TimeKit` leaf so
// it can be shared with MinesweeperEngine without a wrong-direction MS→Sudoku
// coupling. SudokuEngine's existing public-API consumers (PuzzleStore,
// GameCenterClient, Persistence) reach `UTCDay` through `import SudokuEngine`;
// re-exporting TimeKit here keeps those call sites byte-identical.

@_exported public import TimeKit

// Re-export the shared seeded-RNG primitives from the DeterminismKit leaf
// (#446). `SplitMix64` / `DeterministicRNG` (+ `nextInt` / `shuffleInPlace`)
// moved out of SudokuEngine into the game-agnostic `DeterminismKit` leaf so
// they can be shared with MinesweeperEngine without duplication / drift.
// SudokuEngine's existing consumers (PuzzleGenerator, tests) reach them
// through `import SudokuEngine`; re-exporting here keeps those call sites
// byte-identical.
@_exported public import DeterminismKit
