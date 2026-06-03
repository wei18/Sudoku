# U15: MS AdMob bridge + banner + toast wire — impl notes

Live, in-flight notes during the U15 dispatch. Decisions / deviations / open questions captured as they happen, distinct from the post-hoc meeting log.

## Spec recap

Wire real `LiveAdMobAdProvider` (iOS) + `NoopAdProvider` (macOS) into MS, mount `BannerSlotView` on `MinesweeperBoardView`, mount `.toastOverlay(...)` on `MinesweeperRoot`. Mirror Sudoku.

## D1 — BannerSlotView reuse path

`BannerSlotView` lives in **SudokuUI** (`Packages/SudokuKit/Sources/SudokuUI/Components/BannerSlotView.swift`). It depends on:
- `MonetizationCore` (public — fine to reach from MS).
- `@Environment(\.theme)` — a **SudokuUI-internal** theme protocol.

Three options:

1. Move BannerSlotView into MonetizationUI. **Rejected**: requires extracting the theme env from SudokuUI (out of U15 scope, would break "Sudoku byte-identical").
2. Add SudokuUI dep to MinesweeperUI. **Rejected**: would couple the two apps' UI layers — defeats the modularization shape.
3. Create a MS-local BannerSlotView that mirrors the Sudoku one, but uses plain SwiftUI styling (`Color.secondary`, `.regularMaterial`) instead of theme tokens.

**Chosen: option 3.** Mirror shape verbatim; styling uses SwiftUI primitives since MS has no theme system yet. Documented as a future consolidation candidate when MS theme tokens land.

## D2 — Toast tints

Dispatch said "use `.green` / `.red` SwiftUI defaults until MS theme tokens land". Will pass `.green` / `.red` directly.

## D3 — adProvider/adGate threading

MS `LiveRouteFactory` currently doesn't take `adProvider`/`adGate`. Two paths:

- Pass through `LiveRouteFactory.init` (mirrors Sudoku).
- Pass through directly when MS Root mounts BoardView.

Looking at MS shape: BoardView mounts via the route factory (case `.board`). So **route factory must thread** them. Mirror Sudoku's `LiveRouteFactory`. Will add optional params keeping backward compat.

## D4 — Banner mount point in MinesweeperBoardView

Sudoku BoardView mounts `BannerSlotView` between grid and digit pad, suppressed while paused. MS has no pause concept yet — it has `statusBar`, `boardGrid`, no digit pad. Mount the banner **below the grid** (`boardGrid`), suppressed when `viewModel.isTerminal` (mirror "intentional quiet" contract — banner on a "Boom" screen would be tone-deaf).

## D5 — Info.plist GADApplicationIdentifier swap

Mirror Sudoku's pattern: ship the **TEST App ID** verbatim in plist (Google universal test app ID), since the production swap is a paired flip at TestFlight build time. **Wait** — dispatch explicitly says "user approved wiring them now since MS Phase 3 monetization just landed". So I should ship MS production App ID directly:
- `ca-app-pub-8986741979385138~3575413966`

But the LiveAdMobBridge banner unit ID is still wrapped in `#if DEBUG` swap. So DEBUG builds connect to MS production App ID + Google test banner unit — same shape Sudoku will arrive at on v2.5.3. OK.

Actually re-reading: dispatch says "Mirror Sudoku's `#if DEBUG` conditional pattern". Sudoku still has the test App ID in plist + test banner unit ID in DEBUG. The dispatch is ambiguous on whether App ID should also be DEBUG-gated.

**Decision**: ship MS **production** App ID in plist (user explicitly approved), but DEBUG-gate the banner unit ID. This mirrors what Sudoku will look like post-v2.5.3. The reason: GADApplicationIdentifier is a plist (no `#if DEBUG`); it can only have one value per build product. The banner unit ID is the one with risk of accidental real-impression-on-debug, and that's what `#if DEBUG` protects.

## D6 — SKAdNetworkItems

Dispatch says "copy verbatim from Sudoku". But Sudoku's Info.plist has **none**. Confirmed via `grep -rn SKAdNetworkItems Sudoku/ Packages/`: no matches. So nothing to copy — skipping. Will note in return for Leader.

## Open questions for Leader

- Q1: Confirm production App ID in MS plist (no `#if DEBUG` gate) is the desired final shape, not the deferred-flip-at-v2.5.3 pattern Sudoku uses.
- Q2: SKAdNetworkItems missing from both apps. Apple recommends including SKAN IDs for ad attribution. Defer to a separate dispatch?
