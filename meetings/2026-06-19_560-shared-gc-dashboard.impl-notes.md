# Impl Notes — 560 shared GameCenterDashboard (2026-06-19)

Status: COMPLETE
Owner: Developer (Sonnet)
Dispatched by: Leader
Started: 2026-06-19T00:00:00Z

## 結果 (Result)

- Moved `GameCenterDashboard.swift` SudokuUI/Leaderboard → GameCenterClient (git tracks it as a rename). Deleted MS + 2048 copies.
- Repointed 5 call sites; 4 caller files needed an added `internal import GameCenterClient` (Sudoku Settings, MS Settings, 2048 Home, 2048 Settings); MS Home/Completion + Sudoku Live/Completion already imported it.
- No Package.swift dependency additions needed — every consuming target (SudokuUI, MinesweeperUI, Game2048UI) already deps `GameCenterClient` for the submit-on-win protocol.
- Verify: GameCenterKit/SudokuKit/MinesweeperKit/Game2048Kit all `swift build` green; tests green (2048 26/3, MS 183/27, Sudoku exit 0, GC pending-read); 0 snapshot PNG changes; `git grep` zero `MinesweeperGameCenterDashboard`/`Game2048GameCenterDashboard`; swiftlint --strict 0 violations across 10 changed files.

## 設計決定 (Design decisions)

- **Home package: GameCenterClient (GameCenterKit)** — Three candidates were considered (see §折衷). `GameCenterClient` already encapsulates GameKit behind `#if canImport(GameKit)` guards; its Live subdir is the only place GameKit is allowed. Adding `GameCenterDashboard` here keeps the seam principle intact: all GameKit surface area in one package. Neither `MinesweeperUI` nor `Game2048UI` gain a new dep; they already `import GameCenterClient`. SudokuUI loses its bespoke copy and will import `GameCenterClient` instead.

- **File location: `Sources/GameCenterClient/GameCenterDashboard.swift`** — sits alongside `GameCenterClient.swift`, `AchievementEvaluator.swift`, etc. Not inside `Live/` because the public `enum GameCenterDashboard` type is the exported API; the `#if canImport(GameKit)` guards inside the file gate the GameKit calls, matching existing conventions in the package.

- **Dismiss proxy name: `GameCenterDashboardDismissProxy`** — matches the Sudoku original (which was the reference copy per the task spec); no rename needed since the class is `private`.

- **SudokuUI now imports `GameCenterClient`** — `SudokuUI` didn't previously list `GameCenterClient` as a dep (it had the type locally). Added it as a new dependency to `SudokuKit/Sources/SudokuUI/` target in `SudokuKit/Package.swift`.

## 偏離 (Deviations)

- **None** — all three callers (`SudokuAppComposition/Live.swift`, `MinesweeperUI/*.swift`, `Game2048UI/*.swift`) already pattern `GameCenterDashboard.present(leaderboardId:)` or `present()`. No call shape change required.

## 折衷 (Tradeoffs)

- **GameCenterKit vs GameAppKit** — GameAppKit was the alternative (already deps on GameCenterClient, UIKit-free shell). Rejected: GameAppKit is the "composition allowed deps" layer but GameCenterDashboard is a pure GameKit side-effect with no composition logic; GameCenterKit is the canonical GameKit seam. Putting it in GameAppKit would break the seam discipline.

- **GameCenterKit vs per-game UI modules** — rejected: copy-paste-and-adapt was the bug to fix; any per-game host would still leave 2 copies.

## 未決 (Open questions)

- None blocking. SudokuKit Package.swift does not yet list `GameCenterClient` as an explicit dep for `SudokuUI` target — verified by reading the file; adding it is the correct fix (not a gap in the spec).
