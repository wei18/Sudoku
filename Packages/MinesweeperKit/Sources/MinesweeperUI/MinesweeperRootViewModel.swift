// MinesweeperRootViewModel — Minesweeper's app-launch bootstrap coordinator.
//
// #448 step 1b: the bespoke class (deps gameCenter / persistence /
// errorReporter, bootstrap = persistence.bootstrap + GC authenticate) was
// byte-identical to the launch coordinator Sudoku already shares, so it is
// now just an alias of `GameAppKit.GameRootViewModel<Route>`. The only
// game-specific bit — the resume mapping — is injected at construction:
// `.live()` passes `fetchResume` (the closure now lives inline in `Live.swift`'s
// `GameConfig` after the #572 migration, #455 step 4), which maps the latest
// `MinesweeperSavedGameSummary` onto the `.resumeBoard` route; `.preview()`
// passes none, so previews stay resume-free.
//
// LiveRouteFactory and the tests keep using the `MinesweeperRootViewModel`
// name unchanged (MinesweeperRoot was retired in #572).

public import GameAppKit

public typealias MinesweeperRootViewModel = GameRootViewModel<AppRoute>
