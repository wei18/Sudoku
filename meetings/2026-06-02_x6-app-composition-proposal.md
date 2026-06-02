# X6 AppComposition Extraction — Proposal

**Status**: PROPOSAL_DRAFT
**Author**: Developer (Track X6, dispatched 2026-06-02)
**Date**: 2026-06-02
**Predecessors**: X1 (#224 NavigationStackHost), X2 (#226 RouteFactory), X3 (#232 RootShellView), X4 (#239 SettingsShellView), X5 (skipped, Option C — see `meetings/2026-06-02_x5-hubs-proposal.md`)

> Note: original full proposal doc lost to worktree cleanup race. This file is reconstructed from the Developer's structured return summary. Decision and evidence preserved verbatim; full per-construct table omitted.

---

## Recommendation

**Option C — Skip X6.** Verbatim shared surface across the two AppComposition bags is exactly one field (`routeFactory: any RouteFactory<Route>`), and that seam is already extracted by X2. Below the X4 "chrome-only, non-trivial shared surface" bar.

---

## Key findings

1. **Massive size disparity between the two consumers.**
   - SudokuKit `AppComposition` stores 13 fields (12 game/monetization-typed) + 3 factories + `bootMonetization()` (`AppComposition.swift:32-61`)
   - MinesweeperKit stores **1 field** + `.live()` + `rootView` accessor — no `.preview()` / `.tests()`, no boot, no telemetry (`MinesweeperAppComposition.swift:22-28`)

2. **Verbatim overlap is a single record.**
   - Reduces to `let routeFactory: any RouteFactory<Route>` + `@MainActor public struct` decoration
   - Even `Route` is two distinct types both named `AppRoute`

3. **Even `rootView` shape diverges.**
   - Sudoku's App-target does NOT use a `rootView` accessor (`SudokuApp.swift:11-18` inlines 6-arg `RootView(...)`)
   - Minesweeper's does (`composition.rootView`, post-#242)
   - The two consumers have opposite shapes, so the convenience itself is not verbatim-shared

4. **A protocol would be a tautology.**
   - An `AppCompositionBase` protocol would codify a one-field contract with no compile-time benefit beyond `any RouteFactory<Route>` itself
   - X4's "extracted three modifiers with a baked-in macOS Form quirk fix" was a much higher bar than this

5. **All cross-cutting candidates are absent from Minesweeper today.**
   - `GameCenterClient`, `Telemetry`, `ErrorReporter`, `PersistenceProtocol` — none present in MinesweeperAppComposition
   - Forcing them into a base now means Noop-wiring or making them optional — both worse than the status quo

---

## When to revisit

Re-evaluate X6 when **all three** of:

- (a) Minesweeper grows its second protocol dep (e.g. `PersistenceProtocol` for high-score store)
- (b) At least one cross-cutting App-level lifecycle method (`bootMonetization`-like) becomes shared
- (c) Both apps want a uniform `preview()` / `tests()` factory shape

Until then, two separate value-type bags is cheaper than any base type.

---

## Adjacent backlog items surfaced (not X6)

- **#244** — add `rootView: some View` accessor to Sudoku's `AppComposition`. Cuts `SudokuApp.body` from ~8 lines to 1, matches the Minesweeper shape. Standalone micro-refactor, not X6.

---

## Status

- X-series effectively closes here.
- X1-X4 shipped (#224, #226, #232, #239).
- X5 (Daily/Practice hubs) skipped via Option C — `meetings/2026-06-02_x5-hubs-proposal.md`.
- X6 (AppComposition) skipped via Option C — this doc.
- One follow-up filed: #244.
