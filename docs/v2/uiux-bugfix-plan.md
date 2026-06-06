# Sudoku + Minesweeper — UI/UX & Bugfix Plan

_Synthesised 2026-06-06 from 3 read-only audits (a11y / interaction-footguns+bug-hunt /
mirror-divergence) + the user's 5 reported items. Both apps in parallel; shared-shell fixes
(GameShellUI) benefit both. Ordered P0 (bugs blocking core play) → P1 (high) → P2 (polish)._

> **Two cross-cutting truths the audits surfaced:**
> 1. Several "MS differs from Sudoku" gaps come from **two stale assumptions in MS code**:
>    "MS has no theme" (false since #278 — MinesweeperTheme ships) and "Leaderboard is a stub"
>    (false since #312 — live). Fixing these is mechanical, high-consistency payoff.
> 2. `BannerSlotView` (+ glass-card treatment) is **copy-pasted** into SudokuUI and MinesweeperUI
>    instead of living in GameShellUI/MonetizationUI — so every shared fix must be done twice.
>    Extracting it is the structural prerequisite for "fix once → both apps."

---

## P0 — Bugs blocking the core experience (fix first)

### P0-1 — Sudoku "can't end the game?" (win not detected / completion never fires)
_User item 3a._ User reports the Sudoku game never completes. Investigate the win path:
`SudokuCoreKit/Sources/GameState/GameSession.swift` (isSolved/win), `SudokuUI/Board/GameViewModel.swift`
(terminal-state transition + completion route push), `SudokuEngine/Board.swift` (isComplete).
Write a failing test that solves a board and asserts `.won` + the completion route, then fix.
**This also blocks QA of the Completion/alert screen (user item 1 "alert game PASS/FAIL").**

### P0-2 — Resume-game elapsed time ≠ actual play time
_User item 2._ On resume, the displayed timer drifts from real elapsed. Investigate
`GameSession` elapsed accounting (start/pause/resume deltas) vs the SavedGame restore +
the board ticker `.task(id:)` in `BoardView`. Likely: elapsed isn't persisted/restored
correctly, or the ticker restarts from 0 / double-counts. Repro test → fix.

---

## P1 — High (consistency, monetization, accessibility)

### P1-1 — MS screens not themed (the "many screens look different" cluster)
_User item 1 + mirror-divergence audit findings 1,2,6,7._ MS copied pre-theme code with stale
"MS has no theme tokens" comments. Thread `@Environment(\.theme)` + use `theme.accent.primary`
(slate-blue) like Sudoku:
- `MinesweeperUI/SettingsView.swift:45,49,54,60` — rows pass `.accentColor` → `theme.accent.primary.resolved`.
- `MinesweeperUI/MinesweeperBannerSlotView.swift` — `.regularMaterial`/`.secondary` → theme tokens.
- `MinesweeperUI/MinesweeperPracticeHubView.swift` + `NewGameView.swift` — un-themed; mirror
  Sudoku's `PracticeHubView` (theme bg/header + difficulty-tinted Picker & CTA). Fold `NewGameView`
  into Practice hub (it's a duplicate `.board(.practice)` entry — dedup debt).

### P1-2 — MS sidebar missing the Leaderboard item (Mac/iPad lose the affordance)
_Mirror-divergence finding 3._ `MinesweeperRoot.swift:93-119` sidebar lacks Leaderboard (its Home
grid has it; Sudoku's sidebar has it). On regular size class the sidebar is primary nav. Add a
Leaderboard `SidebarItem` → `MinesweeperGameCenterDashboard.present()`. (Also delete the stale
"Leaderboard is a no-op stub until #291" comment — #312 shipped it.)

### P1-3 — "I haven't seen the ad banner" — investigate why the banner doesn't show
_User item 4._ AdMob IDs come from gitignored `Tuist/AdMob.xcconfig` (via `$(ADMOB_APP_ID)`).
Check, in order: (a) is `Tuist/AdMob.xcconfig` filled with real/test IDs (vs the `.example`)?
(b) does `bootMonetization()` actually run + AdMob init complete (UMP→ATT→AdMob — a consent
stall yields no ad)? (c) is `AdGate` suppressing the banner (grace / purchased / dismissed)?
(d) Debug vs Release ad-unit. Tie-in: **H1 below** (bootMonetization isn't idempotency-latched).

### P1-4 — ATT tracking permission prompt is "ugly" + mistimed
_User item 5 + issue #371._ The system ATT prompt fires at **cold launch** (vs design "after Home")
with no priming pre-prompt, and `NSUserTrackingUsageDescription` is a non-localized Info.plist
literal. Add a priming sheet (explain the value) → then request ATT; move the purpose string to a
localized catalog (7 locales). Copy drafted in `docs/v2/att-permission-ux-proposal.md`.

### P1-5 — Accessibility: High-severity barriers (a11y audit)
- **MS number palette (1–8) fails contrast + dark mode broken** (`MinesweeperTheme.swift:41-50`):
  several digits < 4.5:1 on white; `light==dark` so dark revealed bg makes dark digits invisible.
  Give real light/dark pairs clearing AA. (Core game signal — high priority.)
- **Sudoku pencil notes invisible to VoiceOver** (`BoardCellView.swift:44-57`): label says "Empty"
  even with notes. Append decoded candidates ("notes 2, 4, 7").
- **Banner ✕ tap target ~24pt** (both apps, `BannerSlotView`/`MinesweeperBannerSlotView`): give a
  44×44 frame + raise glyph contrast.

---

## P2 — Polish, UX requests, a11y Med/Low, structural

### P2-1 — Sudoku digit-pad UX (user item 3b, 3c)
- **Given/locked digits should be non-selectable** — tapping a given cell shouldn't select/enter
  edit (`BoardCellView` / `GameViewModel` selection gate on `isGiven`).
- **Digit pad as a 3×3 nine-grid** layout (matches the board's 3×3 mental model) — restyle the
  digit pad from its current arrangement to a 3×3 grid.

### P2-2 — Extract shared `BannerSlotView` + glass-card treatment into GameShellUI/MonetizationUI
_Structural prerequisite (a11y S1/S2 + mirror findings 2)._ Kills the copy-paste so banner +
reduce-transparency + tap-target fixes are done once. Per the `reusable-targets-over-duplication`
principle.

### P2-3 — Accessibility Med/Low (a11y audit)
- Reduce Transparency: glass/`.ultraThinMaterial` cards + pause overlay → opaque fallback (shared modifier).
- Sudoku: expose digit as `.accessibilityValue` (announce on placement); hide covered board cells when paused.
- Sudoku selected-cell / notes contrast; MS status `Label`s ("12"/"47" → "Mines remaining, 12").
- Reduce Motion on dismiss animations.

### P2-4 — MS saved-game / resume flow (the one real feature gap)
_Mirror-divergence finding 5 + #284._ MS has no SavedGame persistence/ResumePill; Sudoku resumes
in-progress games. Build MS save-flow to match (then #284 clear-cache feedback + the prototype's
M01 ResumePill land). Bigger feature — schedule after the mechanical fixes.

### P2-5 — Cleanups surfaced (low risk)
- Correct the misleading `.task` comment (#361): the arm64 link bug is **specific to the @main
  app-body opaque chain**, NOT "every `.task`" — both apps archive fine (verified). Don't mass-convert.
- H1: latch `bootMonetization()` (unguarded vs `bootstrap()`'s `hasBootstrapped`) so a 2nd
  `.onAppear` can't re-run UMP→ATT→AdMob.
- H2: shared sidebar `Button(.plain)+Label` missing `.contentShape(Rectangle())` (Mac click-miss footgun).
- Stale MS comments ("no theme tokens", "Leaderboard stub") — delete when touching those files.

---

## Suggested execution order
1. **P0-1, P0-2** (core bugs) — verify-by-test, surgical.
2. **P2-2** (extract shared BannerSlotView) — unblocks fix-once for banner/a11y.
3. **P1-1, P1-2, P1-5** (MS theming + sidebar + a11y High) — high consistency payoff, mostly mechanical.
4. **P1-3, P1-4** (banner investigation, ATT UX) — monetization-facing.
5. **P2-1** (digit-pad UX), then **P2-3/P2-5** (a11y Med + cleanups).
6. **P2-4** (MS saved-game) — feature, last.
</content>
