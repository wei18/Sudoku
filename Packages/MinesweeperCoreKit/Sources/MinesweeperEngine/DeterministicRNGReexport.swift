// Re-export the shared seeded-RNG primitives from the DeterminismKit leaf
// (#446).
//
// `SplitMix64` / `DeterministicRNG` (+ `nextInt`) moved out of
// MinesweeperEngine — where they were a diverged byte-copy of the Sudoku
// originals — into the game-agnostic `DeterminismKit` leaf both cores share.
// MinesweeperEngine's consumers (mine placement in MinesweeperEngine.swift,
// `@testable` tests) reach them through `import MinesweeperEngine`;
// re-exporting here keeps those call sites byte-identical.

@_exported public import DeterminismKit
