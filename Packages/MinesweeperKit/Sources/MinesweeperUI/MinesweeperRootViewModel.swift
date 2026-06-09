// MinesweeperRootViewModel — Minesweeper's app-launch bootstrap coordinator.
//
// #448 step 1b: the bespoke class (deps gameCenter / persistence /
// errorReporter, bootstrap = persistence.bootstrap + GC authenticate, no
// resume) was byte-identical to the launch coordinator Sudoku already shares,
// so it is now just an alias of `GameAppKit.GameRootViewModel<Route>`. The only
// game-specific bit — the resume mapping — is omitted at construction
// (AppComposition passes no `resumeRoute`), so resume stays off: Minesweeper
// can't build its `.board(difficulty:seed:mode:)` route from a
// `SavedGameSummary` (which carries no seed) yet — that's #448 item ① part-b.
//
// MinesweeperRoot, LiveRouteFactory, and the tests keep using the
// `MinesweeperRootViewModel` name unchanged.

public import GameAppKit

public typealias MinesweeperRootViewModel = GameRootViewModel<AppRoute>
