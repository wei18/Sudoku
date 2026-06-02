# Minesweeper Standard Navigation Wire — Impl Notes

Track (c.1) — wire the merged `MinesweeperBoardView` into a real app launch
flow: sidebar + difficulty picker + board push.

## Architecture decisions

### AppRoute shape
- Single case: `case board(difficulty: Difficulty, seed: UInt64)`.
- No `.settings` route; Settings sidebar tap pushes a string-tag case? **No** —
  add `case settings` so Settings is a destination. Keeps shell symmetric with
  Sudoku without dragging in Daily/Practice.
- Final: `enum AppRoute: Hashable, Sendable { case board(difficulty, seed); case settings }`.
- `Codable` not adopted yet — no deep-link spec for Minesweeper this round.

### Composition root
- Lives in `MinesweeperAppComposition` as `MinesweeperAppComposition.live()`
  static factory returning a `MinesweeperAppComposition` value.
- Holds `rootPath: [AppRoute]` state externally? No — `MinesweeperRoot` owns
  the path via local `@State`. Composition just hands a `LiveRouteFactory`.
- Drop the existing `bootRootView()` enum-static method; replace with the
  `.live()` factory + a `MinesweeperRoot(composition:)` view in MinesweeperUI.
- `MinesweeperRoot` lives in MinesweeperUI (needs the SidebarItem / RootShellView
  generic types from GameShellUI, and Difficulty from MinesweeperEngine).

### Live composition split
- Sudoku splits AppComposition (value) + Live.swift (extension with factories).
- Minesweeper is dramatically simpler — combine `MinesweeperAppComposition`
  type + `.live()` factory into one file `LiveMinesweeperComposition.swift`.

### "New Game" restart from BoardView
- Option A: toolbar Button on BoardView that calls `path.removeLast()`.
- Option B: wrap BoardView in a host view that owns the toolbar + a
  difficulty-bound `path` binding.
- Choosing B — don't modify `MinesweeperBoardView`'s public API. Wrap inside
  `LiveRouteFactory.view(for: .board(...))` with `.toolbar` injection at the
  factory site. Simpler than touching the merged MVP file.

### Settings placeholder
- `SettingsView` wraps `SettingsShellView { Text("Coming soon") }`. Title
  "Settings". No rows.

### Seed strategy
- `UInt64.random(in: 0..<UInt64.max)` generated per "Start" tap on NewGameView.
- Bound as `@State` in NewGameView? No — generated at the moment of `path.append`
  so a repeated Start gets a fresh board.

## Open questions
- Project.swift doesn't seem to need touching — Minesweeper already depends on
  `MinesweeperUI` + `MinesweeperAppComposition`. Confirmed.
- `MinesweeperRootView` (the existing hello-world) is no longer the entry —
  delete the file or keep as a legacy preview? **Delete**: replaced wholesale
  by `MinesweeperRoot`. Karpathy §3 surgical: this file was a PR D placeholder,
  scope explicitly says replace.

## Deviations from dispatch spec
- Dispatch lists `MinesweeperRoot.swift` + `LiveMinesweeperComposition.swift` as
  separate files. Following exactly. `bootRootView()` method removed from
  MinesweeperAppComposition.swift — replaced by typed value-based factory.
