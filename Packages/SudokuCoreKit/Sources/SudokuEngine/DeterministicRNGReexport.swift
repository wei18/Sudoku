// Re-export the shared seeded-RNG primitives from the DeterminismKit leaf
// (#446).
//
// `SplitMix64` / `DeterministicRNG` (+ `nextInt` / `shuffleInPlace`) moved out
// of SudokuEngine into the game-agnostic `DeterminismKit` leaf so they can be
// shared with MinesweeperEngine without duplication / drift. SudokuEngine's
// existing consumers (PuzzleGenerator, tests) reach them through
// `import SudokuEngine`; re-exporting here keeps those call sites
// byte-identical. Mirrors MinesweeperEngine's `DeterministicRNGReexport.swift`
// (#459: previously folded into `UTCDayReexport.swift`, unfindable by name).

@_exported public import DeterminismKit
