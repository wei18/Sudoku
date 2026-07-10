# Daily Calendar / Streak — Design Proposal (DAILY-CAL)

**Status:** PROPOSAL (design spec, not yet implemented)
**Date:** 2026-07-11
**Author:** Developer/Designer subagent → Leader review
**Companion:** `meetings/2026-07-11_design-db-uiux-audit.md` (audit findings this
spec responds to — see finding B1, hard prerequisite below)

---

## Hard prerequisite — read this before anything else in this doc

**The daily hub's post-completion refresh must be fixed before this proposal
can ship.** This audit round's findings report, finding **B1**, documents
that `DailyHubViewModel`/`MinesweeperDailyHubViewModel` gate their state load
behind a one-shot `hasBootstrapped` latch
(`Packages/SudokuKit/Sources/SudokuUI/Daily/DailyHubViewModel.swift:53-55,82-84`,
`Packages/MinesweeperKit/Sources/MinesweeperUI/Daily/MinesweeperDailyHubViewModel.swift:65,93-95`),
so closing the Completion Overlay and returning to the hub does not
re-trigger a load — the just-solved puzzle's card doesn't check off until
the user leaves the flow entirely and re-enters. A week-strip streak widget
built on top of that hub inherits the exact same staleness: the dot for
today's puzzle would not fill in on return-to-hub either, defeating the
entire "complete → see it logged immediately" loop this proposal exists to
create. **B1 must land first; everything below assumes it has.**

## 1. Problem

The daily hub shows only the current day's trio of puzzles/boards — there is
no visible record of which past days were completed and no streak concept
anywhere in the app. The daily habit loop (complete → see the accumulation →
come back tomorrow) is missing its second half: today's completion is
recorded but never made visible as part of a pattern.

## 2. Evidence from pattern database

- **Adopt — stoic/Tiimo calendar-strip pattern.** A one-week horizontal date
  picker with the selected/relevant day filled; stoic additionally
  demonstrates swapping the strip's underlying content while keeping the
  same visual template — supports reusing one strip layout across both apps'
  differing content (Sudoku's 3-difficulty trio vs. MS's 3-difficulty trio
  with a distinct failed-state badge) without needing a shared component.
- **Adopt — Duolingo's streak/widget flow.** Confirms streak-as-core-
  retention-mechanic is a validated pattern for daily-cadence products, and
  that externalizing it (e.g. widget) is a natural extension once the
  in-app number exists — this proposal only covers the in-app number; no
  widget work is in scope here.
- **Adopt — Headway/Peloton check-in dot rows.** A row of filled/unfilled
  dots for "this week" plus an adjacent streak count is the direct visual
  model for §3's week strip — a compact, glanceable format that doesn't
  require a full calendar month view to communicate the same information.
- **Reject — full month calendar view.** Not adopted for v1: a single week
  strip answers "am I keeping the habit up" without the added complexity
  (month navigation, cell-density-at-small-widths problems) of a full
  calendar grid. YAGNI — a month view can be added later if the week strip
  proves insufficient; it is out of scope for this spec.

## 3. Proposed solution

### 3.1 Placement and structure

A horizontal 7-dot week strip added to the top of `SUD-DAILY-HUB` and
`MS-DAILY-HUB`, above the existing 3-card trio, with a current-streak number
displayed alongside it (e.g. "5-day streak" as a small caption-weight label
next to or above the strip — not competing in size with the trio's own
difficulty cards).

**Dot states:**
- **Completed day (past):** filled with `accent.primary`.
- **Today:** outlined/stroked (not filled unless also completed) — a
  distinct treatment from both "completed" and "future" so the current day
  is always identifiable even before it's done.
- **Future day:** visually de-emphasized/disabled-looking (low-opacity or
  `text.tertiary`-toned outline), not interactive.
- A day counts as "completed" for strip purposes if **any** of that day's
  three difficulty puzzles/boards was completed — the strip tracks daily
  participation, not per-difficulty completion (the trio below it already
  shows per-difficulty state for the current day).

### 3.2 Interactions

- **Tap a past completed day:** navigates to that day's completion review,
  reusing the existing `SUD-COMPLETION-REVIEW`/`MS-COMPLETION-REVIEW`
  pattern already wired for the current day's completed cards
  (`docs/screen-contracts.md`'s `SUD-DAILY-HUB`/`MS-DAILY-HUB` "Completed
  card tap" row) — no new review screen, just a new entry point into the
  existing one, parameterized by the tapped day's date instead of always
  "today."
- **Tap a past incomplete day:** per the outline's explicit call, this is
  **not** implemented as a backfill-and-complete action in this spec — see
  §6 open question. The recommended default is "view only, cannot
  retroactively complete," on the reasoning that allowing backfill would
  let a streak be padded after the fact, undermining the number's honesty
  as a habit signal. This spec ships with taps on incomplete past days doing
  nothing (or, if the owner prefers a non-silent response, showing a brief
  "not completed" state rather than opening a board) — final call is the
  owner's, not decided here.
- **Tap today (incomplete):** falls through to the existing trio tap
  behavior below the strip — the dot itself is not a new alternate entry
  point to the same puzzles, just a status indicator.
- **Tap a future day:** no-op, matches its de-emphasized/disabled visual
  treatment.

### 3.3 Closure behavior

Completing today's daily puzzle and returning to the hub (via Close on the
Completion Overlay) must show today's dot filled **immediately**, with no
extra navigation required — this is the entire point of fixing B1 first.
This mirrors the same closure principle the findings report's B1 fix
direction points at (matching HOME's existing `refreshResumeCandidate()`
pattern on `dismissGame()`/path shrink).

### 3.4 Platform behavior

- **iOS/iPad:** the week strip sits inline at the top of the hub's existing
  scrollable content, above the trio; on iPad regular's wider hub layout it
  simply has more horizontal breathing room (no reflow logic needed — 7 dots
  never wrap).
- **macOS:** the hub renders pushed into the `NavigationSplitView` detail
  column; the week strip renders at the same width as the trio below it
  (no separate clamp needed — it inherits the hub's existing content width).
  No macOS-specific interaction differences: tap-to-review works identically
  via click, matching how the trio's own card taps already work cross-
  platform.
- **Accessibility:** each dot is a combined VoiceOver element ("Monday,
  completed" / "Wednesday, today, not yet completed" / "Friday, upcoming"),
  not seven separate unlabeled shapes. Reduce Motion: the only motion this
  adds is the immediate dot-fill on return-to-hub (§3.3) — gate that fill
  transition behind `@Environment(\.accessibilityReduceMotion)` the same way
  `ReminderPrimerSheet` already gates its own state-change animation
  (`Packages/SettingsKit/Sources/SettingsUI/Reminders/ReminderPrimerSheet.swift:92,104-105`);
  under Reduce Motion the dot simply appears filled with no transition.

### 3.5 Tokens

- Dot fill: `accent.primary` (completed) — not `status.success`; this is a
  participation record, not a success/failure signal, so it stays in the
  accent family rather than the status family.
- Today's outline: `accent.primary` stroke only, no fill, distinguishing
  "current" from "done."
- Future day: `text.tertiary`-toned, low-emphasis — never `status.warning`
  or any status token; a future day isn't a problem state.
- Streak count label: `.caption`/`.regular` per the "Metadata" type role —
  no oversized custom numeral treatment (that's reserved for the Stats
  screen's hero number in the companion STATS proposal, not duplicated
  here).
- Dot spacing/sizing follows the existing 4pt `@ScaledMetric` ladder — no
  new spacing constant introduced.
- **No confetti or celebratory motion on filling a dot or hitting a streak
  milestone** — the fill is a plain, instant (or Reduce-Motion-respecting
  short) visual update, consistent with the brand's no-celebration stance.

### 3.6 MS-specific note

Minesweeper's daily hub already distinguishes completed / failed ("Failed"
badge) / unplayed at the trio level. This proposal's week-strip "completed"
dot state, per §3.1, is participation-based (any attempt with an outcome
counts as that day being "done"), not win-only — a day where the user played
and lost still fills the dot, since the habit being tracked is "did you show
up today," not "did you win." This spec does **not** decide whether tapping
into a past failed day's review should land the way `MS-COMPLETION-REVIEW`'s
Close currently does (Home) or the way Sudoku's does (Daily-hub) — that is
the pre-existing **B4** open question from `docs/v2/att-permission-ux-proposal.md`'s
sibling findings-report open-questions list, and this proposal explicitly
does not adjudicate it. Sudoku's Close-to-Daily-hub behavior is fully
specified above; Minesweeper's equivalent destination is inherited from
whatever B4 resolves to, not redefined here.

## 4. Acceptance checklist

- [ ] Finding B1 (daily hub post-completion refresh) is fixed and verified
      **before** any of the items below are checked — this checklist is not
      satisfiable on top of the current `hasBootstrapped` latch behavior.
- [ ] Week strip renders above the existing trio on both `SUD-DAILY-HUB` and
      `MS-DAILY-HUB`, 7 dots, no wrapping, no reflow logic needed at any
      supported width.
- [ ] Completed/today/future dot states are visually distinct and use only
      `accent.primary` (completed/today-outline) and `text.tertiary`-toned
      de-emphasis (future) — no `status.*` token appears on any dot.
- [ ] Tapping a past completed day opens that day's completion review (not
      today's) via the existing review screen, parameterized by date.
- [ ] Tapping a future day is a no-op.
- [ ] Completing today's puzzle and returning to the hub fills today's dot
      immediately, with no extra navigation or app relaunch required.
- [ ] Current streak count is displayed and updates in the same immediate
      way as the dot fill.
- [ ] Under Reduce Motion, the dot-fill-on-return has no animated
      transition.
- [ ] VoiceOver reads each dot as one combined element with day name +
      state.
- [ ] No confetti, celebratory animation, or milestone popup appears at any
      streak length.
- [ ] No month-view calendar is introduced anywhere in this feature.

## 5. Prerequisites

- **Hard prerequisite (blocking, not just a dependency): finding B1 must be
  fixed first.** Unconfirmed ? until fixed — tracked as this spec's explicit
  gate, not assumed resolved. See the callout at the top of this document.
- **Per-day completion querying does not exist yet and must be added.**
  Verified ✓ (as a gap, confirmed by this round's audit) —
  `PersistenceProtocol.fetchCompletedDailyIds(for date:)`
  (`Packages/PersistenceKit/Sources/Persistence/Live/SavedGameStore.swift:184-194`)
  only supports a single-day CKQuery lookup; there is no range query across
  multiple days. `PersonalRecord` is aggregated per (mode × difficulty), not
  per day. **This proposal requires a new query capability (a 7-day range
  fetch, or a per-day aggregate record) that does not exist in
  `PersistenceKit` today** — this is real net-new backend work, not just UI,
  and should be scoped and estimated separately before implementation
  begins.
- **Streak-counting logic (consecutive completed days) does not exist
  anywhere in the codebase today.** Unconfirmed ? — needs to be designed
  alongside the new query capability above; this spec describes the
  streak number's *presentation*, not its computation algorithm (e.g.
  whether a streak breaks at end-of-day in local time vs. UTC, whether it's
  computed client-side from fetched per-day data or maintained server-side,
  is an implementation decision for whoever builds the query capability
  above).
- **The existing per-day/per-difficulty completion review screens can be
  parameterized by an arbitrary past date, not just "today."** Unconfirmed ?
  — `docs/screen-contracts.md`'s `SUD-DAILY-HUB`/`MS-DAILY-HUB` contracts
  document today's-trio tap behavior only; whether the review screens'
  current implementation already accepts an arbitrary date parameter or
  needs a signature change to do so was not verified in this round.

## 6. Open questions for owner

1. **Can a missed past day be backfilled/completed retroactively, or is it
   view-only forever once missed?** This spec's default recommendation is
   view-only (protects streak honesty), per the outline's own framing of
   this exact question. Flagged, not decided here.
2. Streak-break timezone/day-boundary rule (local time vs. UTC) — an
   implementation detail but one with real user-visible consequences
   (a streak "unfairly" breaking at midnight in the wrong timezone).
3. MS's past-day review Close-destination (Home vs. Daily-hub) — inherited
   from the pre-existing **B4** open question, not decided by this proposal.
4. Sequencing against the companion STATS proposal, whose hero "current
   streak" number depends on this proposal's streak-counting logic
   existing — see STATS §6.

---

## 7. Scope note

Per the approved outline's hard constraints: no month-view calendar, no
shared Sudoku/Minesweeper streak-widget abstraction (each app implements its
own week strip against its own hub, copy-paste-adapt), no celebratory
motion or milestone popups at any streak length, and no monetization
surface introduced by this feature.
