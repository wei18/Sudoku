# Impl Notes — MS Home + reachable Daily/Practice hubs (#288, #289) (2026-06-04)

Status: COMPLETE
Owner: Developer
Dispatched by: Leader
Started: 2026-06-04

## 設計決定 (Design decisions)

- **HomeViewModel mirrors Sudoku's** — Sudoku's `HomeViewModel` uses `RoutePath<AppRoute>` (GameShellUI, #240) + a `select(_ mode:)` switch. MS gets the same shape: `MinesweeperHomeMode` enum (CaseIterable) + `MinesweeperHomeViewModel` with injected `Binding<[AppRoute]>?`. This makes the Home navigation unit-testable via a `RoutePathBox` mirror.
- **Mode list = 5 cards** — Per prototype M02: New Game (Pick a difficulty), Daily (3 boards today), Practice (All difficulties), Leaderboard (Game Center · best times), Settings (Purchases · about). Sudoku has only 4 (no New Game — Sudoku opens Daily/Practice/Leaderboard/Settings). MS keeps New Game because that's its primary entry today.
- **New Game card → pop to root, not a route** — MS root content IS the Home now, but `NewGameView` is still the difficulty picker. Sudoku routes New Game implicitly through Daily/Practice. For MS, the "New Game" card pushes a dedicated `.newGame` route resolving to `NewGameView`, so the picker stays reachable as its own screen (mirrors the sidebar "New Game" intent + prototype which shows New Game as a card leading to a picker).

## 偏離 (Deviations)

- **Leaderboard card = disabled stub** — MS has NO `GameCenterDashboard` (Sudoku-only). Spec says wire Leaderboard as no-op/coming-soon until GC integration (#291). Implemented: the card is present in the grid but rendered `.disabled(true)` with a "Coming soon" subtitle, and `select(.leaderboard)` is a no-op (no route, no GC). Documented in code. NOT added to AppRoute (matches Sudoku — leaderboard is never a route).

## 折衷 (Tradeoffs)

- **New Game as a route vs. reuse NewGameView as root content** — Sudoku makes Home the literal root content and has no standalone "new game" screen. MS already had `NewGameView` as root. Considered keeping NewGameView as root and only adding hub cards, but that breaks the "Home is the entry" mirror. Picked: Home becomes root content; New Game becomes a `.newGame` route reachable from the Home card + sidebar. Keeps NewGameView intact (surgical) and makes the entry surface match Sudoku's HomeView shape.

## 未決 (Open questions)

- None load-bearing. Leaderboard stub + Daily placeholder are both explicitly sanctioned by the dispatch.
