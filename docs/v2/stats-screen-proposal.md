# Stats Screen — Design Proposal (STATS)

**Status:** PROPOSAL (design spec, not yet implemented)
**Date:** 2026-07-11
**GitHub:** #773 (feature); soft-depends on **#761** (daily-hub refresh
BLOCKER — see §2 closure-principle note)
**Author:** Developer/Designer subagent → Leader review
**Companion:** `meetings/2026-07-11_design-db-uiux-audit.md` (audit findings this
spec responds to — see finding M2)

> **Correction (2026-07-13):** the #761 soft dependency referenced above and
> in §2 is now RESOLVED — closed via PR #789 (main commit e53fdd3), which
> added a `sessionTeardownCount`-driven `refresh()` to both daily hubs. The
> dependency language elsewhere in this doc is kept verbatim for history.

---

## 1. Problem

Progress currently has no dedicated presentation surface. The 2026-07-05
audit round's F2.5 flagged a missing Statistics section with no follow-up
since. This round confirms the gap is total, and surfaces a live doc/code
contradiction:

- `docs/screen-contracts.md:474-475` lists a "stats row" and a "locale row
  (read-only)" as part of `SETTINGS`'s element inventory. Neither exists:
  `SettingsScreen.swift:76-132`'s actual row order is Purchases → GC →
  Reminders → Sound → About → Notices → Storage, and a repo-wide grep for
  "stats" inside `SettingsKit` returns nothing. **Leader has adjudicated this
  as a confirmed documentation defect** (finding M2) — the app currently has
  zero statistics-presentation surface anywhere (Game Center's own dashboard
  is external Apple UI and doesn't count).
- The only progress data that exists today lives silently in
  `PersonalRecord` (`Packages/PersistenceKit/Sources/Persistence/PersonalRecord.swift:19-32`)
  — bestTime/totalTime/completedCount/lastUpdatedAt per (mode × difficulty)
  — with no UI reading it.

## 2. Evidence from pattern database

- **Adopt — Peloton dashboard shape.** A single hero number at the top
  (their equivalent of "this week's minutes"), with a grid of secondary
  stat tiles below, each tile itself carrying a trend affordance (7/30/90
  toggle). The "one hero number, then a tile grid" hierarchy is the direct
  model for §3's layout; the trend-toggle part is explicitly **not** adopted
  in v1 (see §3.4 — no historical time series exists yet to toggle between).
- **Adopt — Ahead profile's "dashboard-ized" progress.** Level / streak /
  time-stats presented as a cohesive profile screen rather than scattered
  across settings rows — supports pulling stats out of `SETTINGS` into their
  own screen rather than trying to cram them back into the row list M2 found
  missing.
- **Adopt — Lyft rating/changing-email closed-loop pattern.** Completing an
  action returns the user to a screen where the result of that action is
  immediately visible. Applied here as a **closure principle**, not a
  literal element: finishing a puzzle should make its effect on stats
  legible without extra navigation, once B1 (the daily-hub refresh blocker
  in the findings report) is fixed — the same closure discipline that
  finding expects of the daily hub applies to stats freshness too.
- **visualHierarchy principle applied:** first = one core number (current
  streak); secondary = the per-difficulty stat tiles (completed count / best
  time / average time); tertiary = supporting caption text. This ordering
  comes directly from the design-db `visualHierarchy` audit lens already
  used elsewhere in this round's findings, not from a specific benchmark
  screen.

## 3. Proposed solution

### 3.1 Screen and entry points

A new, independent Stats screen (per-app, copy-paste-adapt like everything
else — no shared cross-app Stats abstraction). Two entry points:

- **Home:** a secondary-weight entry (a row or small card below the four
  existing mode cards) — deliberately not competing with the Daily/Practice/
  Leaderboard/Settings cards for first-glance visual weight (avoid making
  the current N1 hierarchy finding worse by adding a fifth co-equal card).
- **Settings:** the current bare "stats row" the doc wrongly claims already
  exists becomes real — a `disclosure-row` (chevron, native Settings-Form
  styling matching the rest of `SETTINGS`'s row conventions) that pushes to
  the Stats screen. This is the fix for M2: rather than patching
  `screen-contracts.md` to describe a phantom inline row, this makes the
  row real and correctly documents it as a navigation entry point, not an
  inline stat display.

### 3.2 Layout

- **Daily / Practice split:** two sections (or a segmented control at the
  top — either is acceptable; this spec doesn't force one over the other,
  see §6 open question) since `PersonalRecord` doesn't distinguish daily vs.
  practice completions today (see §3.4 dependency) — if that distinction
  isn't available at ship time, v1 ships a single unified section and the
  split becomes a v-next item once the underlying data supports it.
- **Hero number:** current streak (once DAILY-CAL's streak-count logic
  exists — see cross-reference in §6) rendered at `.largeTitle`/`.semibold`
  per the design system's "Screen title" role, the same weight class used
  elsewhere for a screen's single most important number.
- **Stat tiles (secondary):** one row of tiles per difficulty (Easy/Medium/
  Hard), each showing: games completed, best time, average time (computed
  client-side as `totalTimeSeconds / completedCount`, not stored). Minesweeper
  additionally shows win rate per difficulty (`completedCount` alone isn't
  meaningful for MS without a loss count — see §3.4 for what's actually
  available). Tiles use `.title3`/`.medium` for the number, `.caption` for
  the label — matching the existing "Card title"/"Metadata" roles.
- **Tertiary:** small caption-weight explanatory text under the tile grid
  (e.g. "Stats reset only if you reinstall" or similar factual note) —
  `.caption2`.

### 3.3 Color / brand discipline

- No trophy/medal iconography, no confetti, no celebratory flourish on this
  screen at any point — it's a factual readout, not an award ceremony,
  matching the brand's explicit no-celebration stance.
- `status.success` is the **only** status-family token this screen touches,
  and only to mark a just-set personal-best tile (e.g. a subtle
  `status.success` accent on the specific tile that changed after the most
  recent completion) — never as a background wash across the whole screen.
- `difficulty.*` tokens are used for the per-difficulty tile identification
  (matching their existing signaling-only role on `DailyHubView` puzzle
  cards and `PracticeHubView` picker chips) — **not** applied to the hero
  streak number or to any CTA, per the hard constraint that `difficulty.*`
  never promotes to general accent/CTA use.
- Numbers use `.title3`/`.medium`, never a custom oversized display font —
  no new type role is introduced for this screen.

### 3.4 Data dependency (grounded in audit findings)

`PersonalRecord.swift:19-32` today has exactly: `recordName`,
`bestTimeSeconds` (nilable), `totalTimeSeconds`, `completedCount`,
`lastUpdatedAt`, `completedPuzzleIds` (deduped) — keyed by (mode,
difficulty), **not** by day. This is sufficient for v1's fields above
(completed count, best time, average time per difficulty) with **zero
schema changes**. It is explicitly **not** sufficient for:

- **Mistake/error counts** — no such field exists on `PersonalRecord` or
  `SavedGameSummary`. **Out of v1 scope**, listed as a v-next schema-
  extension candidate, not an acceptance requirement.
- **Per-day completion history / a real trend line** — `SavedGameSummary`
  doesn't persist permanent per-completion history (`markCompleted` only
  flips a status flag; `deleteAbandoned` removes the row entirely). Peloton's
  7/30/90 trend-toggle pattern from §2 is **not** implementable in v1 for
  this reason — v1 ships static current-value tiles only, no trend charting,
  no historical toggle. This is a hard v1 limitation, not a design choice to
  revisit lightly.

### 3.5 Platform behavior

- **iOS/iPad:** pushed screen (matches every other secondary screen's
  presentation style — `push`, per `docs/screen-contracts.md` conventions);
  scrollable single column on compact width, tile grid reflows to more
  columns on iPad regular the same way other card grids in this codebase
  already do (no new reflow mechanism needed).
- **macOS:** pushed into the `NavigationSplitView` detail column, same
  960pt-clamp-and-center treatment `SUD-BOARD`/`MS-BOARD` already use — this
  screen has no board-scale content, so the clamp mostly just prevents tile
  rows from stretching absurdly wide on large displays.
- **Accessibility:** at `.accessibility3`, tiles stack vertically (same
  policy `LeaderboardView` already applies at `.accessibility3+` per
  `design-system.md` §Dynamic Type policy item 5) rather than trying to keep
  a horizontal tile row that would truncate. VoiceOver reads each tile as a
  combined element ("Easy, 14 completed, best time 3 minutes 12 seconds").

## 4. Acceptance checklist

- [ ] Home shows a Stats entry that is visually secondary to the four
      existing mode cards (not equal first-glance weight).
- [ ] Settings' stats row is a real, working disclosure row that pushes to
      the Stats screen — and `docs/screen-contracts.md:474-475` is corrected
      to describe this real row instead of the phantom inline stats/locale
      rows it currently claims.
- [ ] Stats screen renders, per difficulty, using only fields that exist on
      `PersonalRecord` today: completed count, best time, average time
      (computed, not stored) — no schema migration required to ship v1.
- [ ] No mistake/error count and no per-day history/trend chart appear
      anywhere on the v1 screen.
- [ ] No trophy, medal, confetti, or celebratory motion appears on this
      screen under any state.
- [ ] `status.success` appears only as a per-tile accent on a just-set
      personal best, never as a full-screen treatment.
- [ ] At `.accessibility3` Dynamic Type, the tile grid stacks vertically
      without truncating any label or number.
- [ ] VoiceOver reads each stat tile as one combined, correctly-labeled
      element.
- [ ] On macOS, the screen renders inside the clamped detail column, not
      full-window.

## 5. Prerequisites

- **All v1 fields are already persisted and readable with zero schema
  change.** Verified ✓ — `PersonalRecord.swift:19-32` has bestTimeSeconds/
  totalTimeSeconds/completedCount per (mode, difficulty) today; confirmed by
  this round's `audit-designdb` read of the struct.
- **The Settings row this screen needs is currently phantom, not partially
  built.** Verified ✓ — confirmed by direct grep of `SettingsKit` (no
  "stats" match) and by reading `SettingsScreen.swift:76-132`'s actual row
  order; this is finding M2, already adjudicated by Leader as a real defect.
- **MS daily-mode `PersonalRecord` data is already available; the MS
  Practice tab is what's actually blocked.** **Correction (2026-07-11, later
  same day):** this bullet previously treated MS sink-wiring as a fresh,
  newly-adjudicated blocking gap ("#468 B2") — that was wrong, verified
  against `gh`/the source tree. MS's daily-mode `PersonalRecord` submission
  already shipped
  (`submitDailyTimeIfWon()`,
  `Packages/MinesweeperKit/Sources/MinesweeperUI/MinesweeperGameViewModel+SubmitOnWin.swift:33`,
  #699, merged 2026-07-05/06) — this screen's Daily-section MS tiles can ship
  against existing data, no new wiring required. What's genuinely
  outstanding is **MS practice-mode** personal bests, a deliberate
  initial-scope exclusion at the time (MS practice `recordName`s are
  singletons per difficulty and can't dedupe per-attempt the way daily's
  puzzleId does) — already tracked as **open issue #705**, blocked on a
  per-game-unique practice id design. **This proposal's MS-side Practice tab
  is blocked on #705**, not on any new adjudication from this round; see
  `meetings/2026-07-11_design-db-uiux-audit.md` §Adjudicated 2026-07-11
  (#468 B2 entry) for the full correction.
- **MS win-rate-per-difficulty is derivable from existing fields.**
  Unconfirmed ? — independent of the correction above, `completedCount`
  alone doesn't distinguish "played and won" from "played" for Minesweeper
  the way it implicitly does for Sudoku (a Sudoku puzzle that's "completed"
  was solved; an MS board that ends in a mine hit is a loss, not a
  completion). Whether a loss count is tracked anywhere adjacent to
  `PersonalRecord` needs a direct check before this spec's MS win-rate tile
  can be built as described — flagged rather than assumed.
- **Streak number depends on DAILY-CAL.** Unconfirmed ? (by design) — the
  hero "current streak" number in §3.2 assumes the streak-counting logic
  proposed in `docs/v2/daily-calendar-streak-proposal.md` exists. If DAILY-
  CAL ships after STATS, v1 of this screen should either omit the hero
  streak number or ship it as a stub — this is an explicit sequencing
  dependency, not a blocker on STATS's own fields.

## 6. Open questions for owner

1. Daily/Practice split as two sections vs. a single segmented control at
   the top of one section — this spec is agnostic; pick per what reads
   cleaner once `PersonalRecord`'s daily/practice distinction (if any) is
   confirmed.
2. Sequencing: does STATS ship before, after, or alongside DAILY-CAL? The
   hero streak number is the one piece of this screen that depends on the
   other proposal.
3. Should the MS-specific "win rate" tile be held for a v-next schema
   extension (a loss counter) rather than guessed at from existing fields,
   given the Unconfirmed prerequisite above?

---

## 7. Scope note

Per the approved outline's hard constraints, this is a per-app screen
(Sudoku and Minesweeper each get their own Stats screen instance, no shared
cross-app component extraction), introduces no monetization surface, and
adds no celebratory visual treatment of any kind.
