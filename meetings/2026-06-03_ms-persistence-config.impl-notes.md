# MS PersistenceKit config — impl notes (2026-06-03)

Mini-PR before Phase 3 of MS monetization wire. Scope: add `PrivateCKConfig.minesweeper` static + sentinel test.

## Decisions

- **Field shape**: `PrivateCKConfig` only carries `zoneName` + `subscriptionID`. The CKContainer identifier is resolved via `CKContainer.default()` inside `LivePrivateCKGateway.init`, which reads the App target's entitlements. So no container ID lives in this struct — each app picks its container by its own entitlements file. Minesweeper App target will declare `iCloud.com.wei18.minesweeper` in its entitlements.
- **MS zone/subscription naming**: Mirror Sudoku's convention exactly — `com.wei18.minesweeper.userZone` / `com.wei18.minesweeper.userZone.changes`. Distinct from Sudoku so they cannot collide if both apps ever share a process (they won't, but the contract makes it safe).
- **`LivePersistence` factory**: Already takes `PrivateCKConfig` via init — Phase 3 just passes `.minesweeper`. No code change needed here.
- **Out of scope confirmed**: No `MinesweeperAppComposition` wiring, no schema deploy, no Sudoku-side edits.

## Test approach

- Add `minesweeperConfigUsesDistinctNamespace` test alongside existing `sudokuConfigMatchesDesign`, asserting:
  - exact `minesweeper.zoneName` / `subscriptionID` strings
  - distinct from `.sudoku` (no namespace collision)

## Open questions

- None blocking. MS CK schema deploy is user-owned post-Phase-3.
