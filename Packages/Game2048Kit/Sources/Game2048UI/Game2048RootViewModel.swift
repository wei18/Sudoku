// Game2048RootViewModel — Tiles2048's app-launch bootstrap coordinator.
//
// Mirrors MinesweeperRootViewModel: the bespoke class was byte-identical to
// the launch coordinator Sudoku/MS already shares, so it is now just an alias
// of `GameAppKit.GameRootViewModel<Route>`. The only game-specific bit —
// the resume mapping — is injected at construction: `.live()` passes
// `fetchResume` (the closure now lives inline in `Live.swift`'s `GameConfig`
// after the migration), which maps the latest `Game2048SavedGameSummary` onto
// the `.resumeBoard` route; `.preview()` passes none.
//
// LiveRouteFactory and tests keep using the `Game2048RootViewModel` name
// unchanged (Game2048Root was retired by the migration).

public import GameAppKit

public typealias Game2048RootViewModel = GameRootViewModel<AppRoute>
