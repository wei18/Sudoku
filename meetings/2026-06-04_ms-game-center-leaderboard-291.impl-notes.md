# MS Game Center leaderboard (#291) — impl notes

Live design decisions captured during implementation. Distinct from the post-hoc
meeting log.

## Context / mirror sources

- Shared GC layer: `Packages/GameCenterKit/Sources/GameCenterClient/*` — protocol
  + `LiveGameCenterClient`, `GameCenterTesting/FakeGameCenterClient`.
- Sudoku dashboard: `SudokuUI/Leaderboard/GameCenterDashboard.swift` (#49 native
  GC modal side-effect, NOT an AppRoute). Mirrored verbatim into MinesweeperUI.
- Sudoku submit path: `GameCenterSink` (Telemetry `puzzleCompleted` → typed
  `submitScore(puzzleId:difficulty:leaderboardKind:)`).
- Sudoku leaderboard IDs: `SudokuEngine/GameCenterIdentifiers.swift`.

## 設計決定

### Decision 1 — submit seam: raw leaderboard-ID method, NOT the Sudoku-typed one

The shared `GameCenterClient.submitScore(puzzleId:elapsedSeconds:difficulty:
leaderboardKind:)` is **Sudoku-coupled**: it imports `SudokuEngine.Difficulty`
and `LeaderboardKind` only enumerates `.dailyEasy/.dailyMedium/.dailyHard`
mapping to `com.wei18.sudoku.*` strings. Reusing it for MS would either submit
to Sudoku boards or force MS difficulty/kinds into the shared (SudokuEngine-
importing) `GameCenterClient`.

**Chosen:** add a genuinely game-agnostic primitive to the shared protocol:

```
func submitScore(leaderboardId: String, elapsedSeconds: Int) async throws
```

- Imports nothing game-specific (raw String + Int). Both apps can call it.
- Sudoku's typed `submitScore(puzzleId:...)` stays untouched; its
  `LiveGameCenterClient` impl now delegates to the raw method after computing
  the leaderboard ID (DRY — one centisecond-conversion + hook call site).
- `FakeGameCenterClient` records a new `.submitRawScore(leaderboardId:
  elapsedSeconds:)` op so MS tests can assert submit-on-win.

Rejected alternative: a MinesweeperUI-local `MinesweeperGameCenterClient`
protocol + Live impl backed by GameKit directly — would duplicate the GameKit
auth/observe/centisecond machinery that already lives in `LiveGameCenterClient`.
Violates "reusable targets over duplication" (memory).

### Decision 2 — submit-on-win site: MinesweeperGameViewModel, non-blocking

MS `MinesweeperGameViewModel` is MVP with no telemetry, so there is no
`GameCenterSink`/`puzzleCompleted` funnel to hook (Sudoku's path). Mirroring the
*intent* (submit on completion, swallowed-error, never crash gameplay):

- VM gains an optional `gameCenter: (any GameCenterClient)?` + `errorReporter`.
- After every `reveal(...)` that transitions to `.won`, fire-and-forget a
  detached `Task` that submits elapsed seconds to the difficulty's best-time
  leaderboard. Errors are caught and routed to the injected `ErrorReporter`
  (non-blocking, same no-retry policy as `GameCenterSink`). nil client = no-op
  (previews / MVP callsites).
- Submit fires exactly once per win (guard on a `didSubmitWin` flag).

### Decision 3 — leaderboard ID scheme

Per-difficulty best-time leaderboards, mirroring Sudoku's `.v1`-suffixed family
(every generator-version bump opens a new family). MS has no daily/practice
split for v1 leaderboards — one best-time board per difficulty:

```
com.wei18.minesweeper.leaderboard.beginner.besttime.v1
com.wei18.minesweeper.leaderboard.intermediate.besttime.v1
com.wei18.minesweeper.leaderboard.expert.besttime.v1
```

Held in a new `MinesweeperLeaderboardID` enum inside MinesweeperUI (MS has no
shared engine-level identifier file like SudokuEngine's; the IDs are UI-layer
config consumed only by the VM + dashboard). **ASC registration of these 3 IDs
is a separate user-owned / ASCRegister step — out of scope here.**

### Decision 4 — dashboard present: mirror Sudoku verbatim

`MinesweeperGameCenterDashboard.present(leaderboardId:)` is a near-verbatim copy
of Sudoku's `GameCenterDashboard` (iOS `GKGameCenterViewController` modal /
macOS `GKAccessPoint` collapse). Home `.leaderboard` card now calls
`present(leaderboardId: nil)` → full listing. Card un-`.disabled`-ed; subtitle
"Coming soon" → "Best times". Stays a modal side-effect, never an AppRoute (#49).

### Decision 5 — auth handshake

MS has no `RootViewModel` GC auth like Sudoku's `RootView.task`. The native GC
dashboard self-prompts sign-in, and `submitScore` no-ops server-side when
unauthenticated. To make submit actually land, the VM kicks a best-effort
`authenticate()` once before first submit (swallowed). Kept minimal — no auth
state surfaced in MS UI for v1.

## Open questions for Leader

- Auth: should MS adopt Sudoku's `RootView.task` authenticate-on-launch pattern
  instead of lazy auth-before-submit? Deferred — lazy is sufficient for v1 and
  avoids touching MinesweeperRoot's shell.
- The raw `submitScore(leaderboardId:elapsedSeconds:)` addition touches the
  shared GameCenterKit (core module) — CR required (Code Reviewer threshold).
