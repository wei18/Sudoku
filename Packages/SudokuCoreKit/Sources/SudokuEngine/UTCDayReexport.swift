// Re-export the shared `UTCDay` from the TimeKit leaf (#305).
//
// `UTCDay` moved out of SudokuEngine into the game-agnostic `TimeKit` leaf so
// it can be shared with MinesweeperEngine without a wrong-direction MS→Sudoku
// coupling. SudokuEngine's existing public-API consumers (PuzzleStore,
// GameCenterClient, Persistence) reach `UTCDay` through `import SudokuEngine`;
// re-exporting TimeKit here keeps those call sites byte-identical.

@_exported public import TimeKit
