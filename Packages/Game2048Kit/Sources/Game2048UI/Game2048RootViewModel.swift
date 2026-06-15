// Game2048RootViewModel — Tiles2048's app-launch bootstrap coordinator.
//
// Mirrors MinesweeperRootViewModel: the bespoke class was byte-identical to
// the launch coordinator Sudoku/MS already shares, so it is now just an alias
// of `GameAppKit.GameRootViewModel<Route>`. The only game-specific bit —
// the resume mapping — is injected at construction: `.live()` passes
// `fetchResume` (Live+Resume.swift), which maps the latest
// `Game2048SavedGameSummary` onto the `.resumeBoard` route; `.preview()`
// passes none.
//
// Game2048Root, LiveRouteFactory, and tests keep using the
// `Game2048RootViewModel` name unchanged.

public import GameAppKit

public typealias Game2048RootViewModel = GameRootViewModel<AppRoute>
