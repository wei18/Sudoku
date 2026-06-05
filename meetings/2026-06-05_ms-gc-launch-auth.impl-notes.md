# Impl Notes — MS Game Center launch-auth handshake (#313) (2026-06-05)

Status: COMPLETE
Owner: Developer subagent
Dispatched by: Leader
Started: 2026-06-05

## 設計決定 (Design decisions)

- **New `MinesweeperRootViewModel`** — Sudoku kicks GC launch auth from
  `RootView.task → RootViewModel.bootstrap() → gameCenter.authenticate()`
  (`Packages/SudokuKit/Sources/SudokuUI/Root/RootViewModel.swift:63`). MS's
  `MinesweeperRoot` was a plain `View` with no VM and no `.task`. Chose to
  mirror Sudoku by introducing `MinesweeperRootViewModel` (@MainActor
  @Observable) holding `authState` + `hasBootstrapped` + `bootstrap()`, wired
  into `MinesweeperRoot.task`. This is the exact Sudoku mechanism + placement.

- **Auth-only scope (omit persistence.bootstrap + resumeCandidate)** — Sudoku's
  `bootstrap()` does three things: `persistence.bootstrap()` (CloudKit zone
  provisioning, #196), `gameCenter.authenticate()`, and
  `persistence.latestInProgress()` (resume pill). MS has NO saved-game / resume
  flow (README: "gameplay built, no saved-game flow") and its `.live()`
  persistence puzzle-loader is a throwing stub. The issue scope is *only* the
  launch GC auth handshake (#313). Mirroring the persistence parts would invent
  behavior MS doesn't have (no ResumePill exists in MinesweeperRoot). So
  `MinesweeperRootViewModel.bootstrap()` mirrors ONLY the `authenticate()`
  block + its graceful-failure funnel. Persistence bootstrap is intentionally
  left out — if/when MS grows a saved-game flow it can be added then.

## 偏離 (Deviations)

- **Idempotency guard kept** — mirror Sudoku's `guard !hasBootstrapped` so a
  `.task` re-entry (size-class change on macOS NavigationSplitView) does not
  re-trigger GameKit auth. Same rationale as Sudoku.

- **Removed `MinesweeperRoot`'s `#Preview`** — `MinesweeperRoot.init` now
  requires a `MinesweeperRootViewModel`, which holds a `GameCenterClient`.
  Building a GC stub inside the leaf `MinesweeperUI` module would need to name
  the GC protocol's `SudokuEngine.Difficulty` parameter type, which is NOT
  importable here without adding a new SudokuEngine / GameCenterTesting dep to
  MinesweeperUI (no MS leaf source imports either today). Rather than add a
  production dep purely to satisfy a preview, removed the root-level `#Preview`
  — this MIRRORS `SudokuUI.RootView`, which has no `#Preview` either; the
  composition-root view is exercised via `MinesweeperAppComposition.preview()`
  + the app target. All per-surface previews (Home / hubs / board) are
  untouched. Downstream impact: one fewer Xcode canvas preview for the root
  shell; no test/behavior change.

## 折衷 (Tradeoffs)

- **VM held on the composition bag vs constructed inline in `rootView`** —
  Sudoku holds `rootViewModel` on `AppComposition` and passes it into
  `RootView`. Mirrored: `MinesweeperAppComposition` now holds a
  `rootViewModel` and `rootView` passes it to `MinesweeperRoot`. Keeps the bag
  shape parallel and lets future MS tests inject a scripted VM.

## 未決 (Open questions)

- None load-bearing. Auth-only scope is the faithful #313 mirror; persistence
  bootstrap deferred per design decision above.
