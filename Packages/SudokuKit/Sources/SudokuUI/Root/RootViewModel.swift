// RootViewModel — Sudoku's app-launch bootstrap coordinator.
//
// #448 step 1a: the bootstrap/auth/resume logic was generalized into
// `GameAppKit.GameRootViewModel<Route>` (it was ~95% identical to
// Minesweeper's `MinesweeperRootViewModel`). Sudoku's `RootViewModel` is now a
// typealias over the generic VM specialized on `AppRoute`; the Sudoku-specific
// resume mapping (`SavedGameSummary → .board(puzzleId:)`) is injected at
// construction in AppComposition via the `resumeRoute:` closure.
//
// RootView, RouteFactory, and the tests continue to use `RootViewModel`
// unchanged — they only touch `path`, `resumeCandidate`, `authState`,
// `bootstrap()`, and `resumeTapped()`, all preserved by the typealias.

public import GameAppKit

public typealias RootViewModel = GameRootViewModel<AppRoute>
