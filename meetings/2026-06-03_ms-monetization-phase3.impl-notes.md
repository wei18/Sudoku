# Impl Notes — MS Monetization Phase 3 wire (2026-06-03)

Status: COMPLETE
Owner: Senior Developer (Sub-agent)
Dispatched by: Leader
Started: 2026-06-03

## 設計決定 (Design decisions)

- **MonetizationStateController productId param — option (a)** — Spec dispatch
  §"MonetizationStateController productId handling" calls for (a) parameterize
  with `productId: String` (preferred per the existing in-source TODO at
  `MonetizationStateController.swift:46-48`) or (b) thin wrapper. Picked (a):
  the controller's internal references (`removeAdsProductId`) are all
  filter/match predicates — parameterising at init keeps one type per app.
  Public top-level `let removeAdsProductId` is **retained** as a back-compat
  symbol for SudokuKit tests that already import it. Sudoku call sites
  (Live.swift + Preview.swift) explicitly pass `productId: removeAdsProductId`
  so the spelling stays grep-able.

- **MS productId constant** — Defined `minesweeperRemoveAdsProductId` as a
  module-level `public let` in MinesweeperAppComposition (mirrors Sudoku's
  symbol layout) so MS tests can import it later.

- **MS persistence: real LivePersistence wire** — Mini-PR #257 shipped
  `PrivateCKConfig.minesweeper`; using it for `LivePersistence(ckConfig:
  .minesweeper, ...)`. Puzzle loader closure is a no-op stub
  (`{ _ in throw … }`) because Minesweeper has no PuzzleProvider yet — the
  loader only fires when a SavedGameStore record exists, which can't happen
  until MS persistence + saved-game flow lands (separate dispatch).

- **MS AdProvider: NoopAdProvider on all platforms** — Per dispatch §Required
  edits 2 "(NOT LiveAdMobBridge — U15 deferred)". Sudoku uses
  `LiveAdMobAdProvider` on iOS; MS skips that entire branch.

- **Telemetry no-op closures** — `AdGate(onPersistenceError:)` and
  `LiveStoreKit2IAPClient(onCatalogDesync:)` STILL wire into Telemetry —
  dispatch §"Telemetry prerequisite" pre-decision item 7 says "no-op
  closures for Telemetry this round". Re-reading the controller-level
  prerequisite: real Telemetry IS already wired into MinesweeperAppComposition
  (PR #250). So I CAN reuse it. Going with the Sudoku-shape Telemetry
  fan-out into AdGate / IAPClient — matches "mirror" intent.

- **MS SettingsView tint** — Spec says "just use `.blue` or `.tint` SwiftUI
  default — no MS theme tokens yet". Picked `.accentColor` via
  `Color.accentColor` so the rows inherit whatever SwiftUI tint the host
  scene declares (GameShellUI may set one). Falls back to system blue if
  unset. Mirrors zero MS theme tokens.

## 偏離 (Deviations)

- **MS removeAdsProductId visibility** — Defined as `public let` (not file-
  private) inside MinesweeperAppComposition so future MS test fixtures can
  import the same symbol the way Sudoku tests import `removeAdsProductId`.
  Not requested explicitly but consistency-driven.

## 折衷 (Tradeoffs)

- **Controller parameterization vs new init overload** — Considered: (1) add
  `productId:` REQUIRED param (breaks Sudoku tests), (2) add `productId:` w/
  default = `removeAdsProductId` (compatible), (3) MS wraps a private
  controller. Picked **(2)** — default = `removeAdsProductId` keeps Sudoku
  call sites and tests byte-identical, MS explicitly passes its own ID.
  Three Sudoku tests at `SettingsIAPRowTests`, `MonetizationStateControllerUpdatesTests`,
  `HomeViewRemoveAdsCardTests`, `SettingsViewTests` continue to compile with
  zero diffs.

- **SettingsView injection path** — Considered: (A) thread
  `monetizationController` through `LiveRouteFactory.init`, (B) make
  `SettingsView(monetizationController:)` take it directly via factory
  closure. Picked (A) — mirrors Sudoku's LiveRouteFactory shape and gives
  MS a clean expansion point for future Game Center / About / Storage rows.

## 未決 (Open questions)

- **Localization** — Toast / row strings ("Ads removed", "Remove Ads",
  "Restore Purchases") are hardcoded English in MonetizationUI rows. Sudoku
  inherits the same. Not asked to translate this dispatch; flagging only.

Final: COMPLETE — MS build clean, Sudoku build clean, MS tests 30/30 pass,
Sudoku tests 209/209 pass (no SettingsIAPRowTests snapshot drift triggered).
