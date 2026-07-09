// RootViewModel — Sudoku's app-launch bootstrap coordinator.
//
// #448 step 1a: the bootstrap/auth/resume logic was generalized into
// `GameAppKit.GameRootViewModel<Route>` (it was ~95% identical to
// Minesweeper's `MinesweeperRootViewModel`). Sudoku's `RootViewModel` is now a
// typealias over the generic VM specialized on `AppRoute`; the Sudoku-specific
// resume mapping (`SavedGameSummary → .board(puzzleId:)`) is injected at
// construction in SudokuAppComposition via the `resumeRoute:` closure.
//
// #557: moved from Root/RootViewModel.swift to Navigation/ alongside AppRoute
// after RootView was retired. All consumers (`SudokuAppComposition`, `RouteFactory`,
// tests) use `RootViewModel` unchanged — the typealias is the only moved artifact.

public import GameAppKit

public typealias RootViewModel = GameRootViewModel<AppRoute>
