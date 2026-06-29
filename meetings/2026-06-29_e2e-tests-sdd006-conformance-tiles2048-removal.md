# 2026-06-29 — XCUITest E2E, SDD-005 closeout, three-game conformance, Tiles2048 removal

Long session. Arc: finish #510 (E2E test harness) → close out SDD-005 platform
convergence (residual + spec) → audit the three games' conformance → act on the one
drift → **remove Tiles2048 entirely** → reconcile two stale App-Store tracking issues.

## Goals (as they arrived from the user)

1. Continue #510 Phase 2 (screen-tour) then Phase 3 (E2E flow regression).
2. After SDD-005 RFC, **verify** the three games actually conform to the spec.
3. Open an issue + migrate the one drift (Sudoku `LiveRouteFactory`).
4. Merge the SDD-006 RFC as recorded planning; scaffold generator → **pending**.
5. **Remove Tiles2048 (game 3), delete the source** — keep MS + Sudoku the focus.
6. Check #132 then #236 for gaps vs current state.

## Shipped (PRs, all merged to main)

| PR | What |
|---|---|
| #632 | `mise run ui:tour` — deep-link + screenshot every screen × light/dark for designer review (#510 Phase 2) |
| #634 | XCUITest E2E targets + dedicated `<App>-E2E` schemes + `mise run test:ui` runner; **Sudoku** full win→completion (#510 Phase 3 PR1) |
| #635 | **Minesweeper** win→completion via a DEBUG winning-cell beacon + shared-flow extraction (`App/UITestsShared/`) (#633) |
| #637 | remove dead `GameConfig.settingsNotices` field (SDD-005 residual) |
| #638/#641 | SDD-006 new-game-scaffold RFC + §2 three-game conformance audit |
| #640 | move Sudoku `LiveRouteFactory` SudokuUI → SudokuAppComposition (#639) |
| #642 | **remove Tiles2048** — 71 files / −8112 lines |

Issues closed: **#510** (E2E done), **#633**, **#639**, **#501** (2048 ship, won't-do),
**#132** (v2.5 ops, superseded), **#236** (submission epic, completed). Opened: **#639**, **#633**.

## Key decisions (+ rejected alternatives)

- **E2E scheme, not test plan.** A Tuist `.uiTests` target wired into an existing
  scheme's `.xctestplan` builds but produces **no `.xctest` bundle** ("no test bundles
  available"). Fix: a dedicated `<App>-E2E` scheme with `.targets([...])`. (Rejected:
  adding the UI target to the default plan — Tuist doesn't cross-link a native test
  target into a plan's buildables the way it does SPM package tests.)
- **Winning move per game.** Sudoku is brute-forced (tap empty cell, cycle digits 1–9,
  no mistake limit). Minesweeper **can't** — a wrong hidden-cell tap hits a mine = loss
  — so a DEBUG **winning-cell beacon** surfaces the safe cell's runtime (row,col) and
  the test taps it by unique a11y label. (Rejected: brute-forcing MS; rejected: tagging
  the cell directly — would thread into the production board signature.)
- **Locale-stable queries only** (7 locales): hardcoded "Digit N" / "…Empty" labels +
  `game.completion.hero` / `game.pause.resume` identifiers, never localized strings.
- **C4 proof deferred** (user): ship the SDD-006 generator + docs without standing up a
  throwaway game 4; empirical proof waits for a real new game.
- **Scaffold form left as RFC OQ** (user): wrote the RFC, deferred the mise-generator-vs-
  checklist decision; generator is **pending**.
- **Remove Tiles2048 entirely** (user): delete code + close issues, keep MS + Sudoku.
  Verified **no reverse dependency** (shared modules only named Game2048 in comments)
  before deleting — so MS/Sudoku build untouched.
- **Sudoku `LiveRouteFactory` migration is not a plain `git mv`**: SudokuUI's board
  completion calls its `isDaily`/`leaderboardId` statics, so moving the type to
  AppComposition would create a UI→composition cycle. Extracted the statics to
  `SudokuLeaderboardRouting` (SudokuUI) first, then moved the factory.
- **Stale-issue handling**: #132 (v2.5) and #236 (v2.5+MS-v1) both superseded by the
  shipped v2.6 with every child closed → updated + closed with gap explanations rather
  than left as misleading OPEN trackers.

## Findings / lessons

- **Three-game conformance audit**: all axes conformant (CoreKit/Kit/composition/ckdb/
  App-shell) except **one real drift** — Sudoku's `LiveRouteFactory` lived in the UI
  module while MS/2048 had theirs in composition. Fixed in #640. 2048's Preview/Audio/
  StoreKit/E2E gaps were **pre-ship**, not drift.
- **`scan:l10n` blind spot reconfirmed**: validates per-key locale completeness but not
  that a required key *exists* — orthogonal to this session but reaffirmed.
- **AdMob isolation invariant**: `mise run scan:admob` enforces exactly one real
  `import GoogleMobileAds` (LiveAdMobBridge). A bare `grep -l "import GoogleMobileAds"`
  over-matches **comments** (3 files mention the string; only 1 imports) — used when
  gap-checking #132.
- **dual-model CR earned its keep**: on #642, Haiku caught a real BLOCKER (zh-Hant README
  not updated) that Sonnet listed only as a NIT; took the union.

## State at session end

- main clean; both apps build; full unit suites green (Sudoku 260 / MS 173 / GameShellKit
  21 / PersistenceKit 74 / ASCRegisterKit 156); `mise run test:ui all` green; scan:l10n
  passes (now **2** catalogs).
- Repo is a **two-game** platform. SDD-004 abandoned, SDD-005 complete, SDD-006 drafted.

## Open / next

- **#479** new-game scaffold — generator is **pending**; template source is now
  **Minesweeper** (2048 removed). Form decision (RFC §5 OQ) still open.
- Backlog: #286 (CaptureGuardKit, parked), #166 (Android portability), #631 (Upkeep),
  #615 (user-owned device verify).
