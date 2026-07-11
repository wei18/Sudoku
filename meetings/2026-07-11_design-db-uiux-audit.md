# 2026-07-11 — design-db UI/UX audit (findings) + first-run/stats/daily-cal proposals

Arc: the owner approved a design-db-informed audit round, scoped as
"audit + design specs" for three new features (first-run onboarding, a Stats
screen, daily calendar/streak). Two parallel read-only lanes ran against
**main @ `382eabd`**: an `audit-designdb` lane (design-db's 549-screen pattern
database as the comparison lens, cross-referenced against
`visualHierarchy`/color-semantics/state-tiers/settlement-closure) and an
`audit-platform` lane (static scan closing the coverage gaps the 2026-07-05
audit round named as untouched: iPad regular + macOS, MS Intermediate board,
Settings sub-screens, AX3, offline). Findings below are merged and sorted
BLOCKER → MAJOR → MINOR. Three companion proposals were originally drafted
(`docs/v2/first-run-guide-proposal.md`, `docs/v2/stats-screen-proposal.md`,
`docs/v2/daily-calendar-streak-proposal.md`) to turn a subset of this into
buildable specs. **`docs/v2/first-run-guide-proposal.md` was withdrawn by the
owner on 2026-07-11 and removed from this branch** — see §Adjudicated
2026-07-11 (owner-delegated) below. The remaining two,
`docs/v2/stats-screen-proposal.md` and
`docs/v2/daily-calendar-streak-proposal.md`, are still active.

---

## BLOCKER

### B1 — Daily hub never refreshes after closing the Completion Overlay

- **Screen:** `SUD-DAILY-HUB`, `MS-DAILY-HUB`
- **Files:** `Packages/SudokuKit/Sources/SudokuUI/Daily/DailyHubViewModel.swift:53-55,82-84`,
  `Packages/MinesweeperKit/Sources/MinesweeperUI/Daily/MinesweeperDailyHubViewModel.swift:65,93-95`,
  `Packages/SudokuKit/Sources/SudokuUI/Board/BoardView+Completion.swift:137-144`
- **Problem:** both hub view models gate their state-loading write behind a
  one-shot `hasBootstrapped` latch that only runs on first mount. `exitToHub()`
  pops/dismisses the board back onto the same, un-destroyed hub instance but
  never re-triggers a load. Solving a daily puzzle and returning to the hub
  does not flip that card's checkmark until the user leaves the whole flow
  (e.g. back to Home) and re-enters.
- **Fix direction:** re-run the bootstrap fetch (or a lighter refresh) on
  `onAppear`/return-to-foreground of the hub, not just first mount — mirror the
  pattern HOME already uses for its resume pill (`refreshResumeCandidate()` on
  `dismissGame()` / path shrink, closed under #679).
- **Note:** this blocks DAILY-CAL (proposal below) — a per-day streak dot ring
  built on top of a hub that doesn't self-refresh would carry the same stale
  read forward into the new calendar row.

### B2 — `@ScaledMetric` Dynamic-Type spacing rule is unimplemented across the UI

- **Screen:** all (cross-cutting)
- **Files:** `docs/designs/design-system.md:122-131` (the rule); real
  violations across `SudokuUI`, `MinesweeperUI`, `GameShellUI`, `SettingsUI` —
  only one production call site actually wraps a literal
  (`ReminderPrimerSheet.swift:120`). The shared `Theme.swift` `SpacingTokens`
  struct itself stores un-scaled `CGFloat` constants, while its own comment
  claims "production code will wrap in `@ScaledMetric`." ~40+ literal-value
  call sites confirmed, including `BoardView.swift`, `HomeScreen.swift`,
  `CompletionOverlayScaffold.swift`, and the fixed 44×44 in
  `MinesweeperBoardView.swift:605`.
- **Problem:** the design system's own Dynamic Type policy (§Spacing scale,
  §Dynamic Type policy) is contradicted by the shipped code almost
  everywhere it applies. Layout does not breathe with type size as documented
  — a correctness gap between spec and implementation, not just a style nit.
- **Fix direction:** either wrap the ~40+ literal call sites in
  `@ScaledMetric(relativeTo: .body)` per the documented pattern, or — if the
  product decision is that fixed-pixel spacing is intentional for these
  surfaces — amend `design-system.md` to stop claiming a contract the code
  doesn't honor. Currently the doc and the code flatly disagree.

---

## MAJOR

### M1 — MS-PRACTICE-HUB does not read the theme at all

- **Screen:** `MS-PRACTICE-HUB`
- **Files:** `Packages/MinesweeperKit/Sources/MinesweeperUI/Practice/MinesweeperPracticeHubView.swift:38-121`
- **Problem:** the entire view never touches `@Environment(\.theme)`. The
  difficulty picker takes the system default tint, the CTA's
  `.borderedProminent` has no `.tint()` applied (renders system blue), and
  text uses `.primary`/`.secondary` instead of `theme.text.*`. This is the
  one core entry-point screen in either app where all brand/difficulty color
  semantics are absent — the Sudoku equivalent correctly uses
  `theme.difficulty.*` and `theme.text.*`.
- **Fix direction:** thread `@Environment(\.theme)` through the view and its
  subviews the same way `SudokuUI`'s practice hub does; apply
  `theme.difficulty.*` to the picker chips and `.tint(theme.accent.primary)`
  (or the difficulty-appropriate token) to the CTA.

### M2 — Screen contract documents a Settings statistics/locale row that does not exist (adjudicated)

- **Screen:** `SETTINGS`
- **Files:** `docs/screen-contracts.md:474-475` (claim) vs.
  `Packages/SettingsKit/.../SettingsScreen.swift:76-132` (actual — no such
  block); grep for "stats" across `SettingsKit` returns nothing
- **Problem:** the as-built contract's element inventory for `SETTINGS`
  lists "stats row, locale row (read-only)" between the GC status row and the
  audio section. The real row order is Purchases → GC → Reminders → Sound →
  About → Notices → Storage. Neither app's `SettingsView` injects a
  statistics slot. **Leader has adjudicated this finding as confirmed**: the
  app currently has zero statistics-presentation surface anywhere (the Apple
  Game Center dashboard is external UI and doesn't count).
- **Fix direction:** correct `docs/screen-contracts.md:474-475` to drop the
  phantom rows, and treat the STATS proposal below as the real fix for the
  underlying gap (a Settings disclosure-row entry point into a dedicated
  Stats screen), rather than patching Settings' row list back in ad hoc.

### M3 — macOS overlay mask escapes the window: sidebar stays live under Pause/Completion

- **Screen:** `PAUSE-OVERLAY`, `SUD-COMPLETION-OVERLAY`, `MS-COMPLETION-OVERLAY`
- **Files:** `Packages/SudokuKit/Sources/SudokuUI/Board/BoardView.swift:72-96`
  (`.overlay {}` + `.ignoresSafeArea()`),
  `Packages/MinesweeperKit/Sources/MinesweeperUI/MinesweeperBoardView.swift:190-242`
- **Problem:** on iOS, board presentation is `fullScreenCover`, so an overlay
  mounted on `BoardView` covers the entire screen. On macOS, board
  presentation is a `NavigationStack` push into the detail column of a
  `NavigationSplitView` (`RootShellView` sidebar + detail). Because the
  overlay is mounted on `BoardView` itself rather than above the split view,
  `.ignoresSafeArea()` only fills the detail column — the sidebar remains
  visible **and clickable** while Pause or Completion is showing.
- **Fix direction:** hoist the overlay presentation to the
  `NavigationSplitView`'s outer container (so it spans both columns on
  macOS), or switch macOS specifically to a real window-level modal for these
  three overlays instead of an in-place `.overlay{}`.

### M4 — MS Intermediate/Expert board cells fall below the 44pt touch-target floor with no documented exception

- **Screen:** `MS-BOARD`
- **Files:** `Packages/MinesweeperKit/Sources/MinesweeperUI/MinesweeperBoardView.swift:647-693`
  (cell-sizing fallback ladder), `MinesweeperCellButton.swift:63-66` (hit-test
  == visual bounds); `docs/designs/design-system.md:176` (touch-target
  deviation table — Beginner-only)
- **Problem:** the cell-fit formula (`minCellSide=32`, `cellSpacing=2`,
  `fitted = floor(min(availW/cols, availH/rows))`) drops to its third
  fallback branch (both axes scroll, `cellSide` pinned to 32pt) for
  Intermediate (16×16) and Expert (16×30) on 375pt-wide phones (iPhone SE
  2/3). `MinesweeperCellButton` doesn't pad its hit-test region the way
  `pauseToggle`/`modeToggle` do (`.frame(minWidth:44, minHeight:44)`), so the
  actual tappable area is the visual 32×32 cell — below HIG's 44pt floor.
  `design-system.md`'s deviation table only records the Beginner-difficulty
  36pt exception; this one is undocumented.
- **Fix direction:** either overlay a 44×44 hit-test region on top of the
  32pt visual cell (matching the pattern already used elsewhere in the same
  file), or raise `minCellSide` so the scroll fallback triggers earlier
  instead of shrinking below 44pt, and add the resulting deviation to the
  §Touch/mouse targets table.

### M5 — Game Center auth has no timeout; a stuck callback can silently withhold the resume pill for the whole session

- **Screen:** `HOME` (indirect — GC auth runs at boot, ahead of first render)
- **Files:** `Packages/GameCenterKit/.../GKAuthDriver.swift:37-48`
  (`performAuthentication()`, `withCheckedContinuation`, no timeout),
  `GameRootViewModel.swift:102-116`,
  `TelemetryKit/.../UserFacingError.swift:69-73`
- **Problem:** network failure and "not signed in" both collapse into the
  same UI state and the same telemetry bucket, and neither has a timeout
  guard on the underlying continuation. GC auth doesn't block HOME's first
  frame, but if the callback itself hangs, the app never gets a
  `resumeCandidate` for the rest of that session — there's no fallback that
  fires after N seconds.
- **Fix direction:** wrap `performAuthentication()`'s continuation in a
  timeout (e.g. `withThrowingTaskGroup` racing a `Task.sleep`), and resolve to
  the same "not signed in" degraded state on timeout rather than hanging
  indefinitely.

---

## MINOR

### N1 — HOME's four mode cards carry identical visual weight for new users

- **Screen:** `HOME`
- **Files:** `Packages/GameAppKit/Sources/GameAppKit/GameHomeView.swift:69-78`,
  `Packages/GameShellKit/Sources/GameShellUI/Home/HomeScreen.swift:192-227`
- **Problem:** when there's no resume pill (a fresh install), the header slot
  goes blank and all four `HomeModeCard`s (Daily/Practice/Leaderboard/
  Settings) render with the same `icon + title + subtitle + chevron`
  treatment — nothing marks a recommended first tap for a brand-new user.
- **Fix direction:** give the Daily card a higher-contrast treatment (or a
  small badge) specifically in the no-resume-candidate state, matching how
  design-db's benchmark home screens mark a single primary entry point for
  first-time users.

### N2 — MS-BOARD flag-mode toggle borrows `status.warning` for a normal mode switch

- **Screen:** `MS-BOARD`
- **Files:** `Packages/MinesweeperKit/Sources/MinesweeperUI/MinesweeperBoardView.swift:612`
- **Problem:** the reveal/flag mode-switch button tints itself with
  `theme.status.warning.resolved` when in flag mode. Flag mode is a normal,
  expected input mode, not a warning/degraded state — reusing the warning
  token risks reading as "something is wrong with this mode."
  `design-system.md`'s color-token table reserves `status.*` for
  success/warning/error signaling, not mode selection.
- **Fix direction:** switch the flag-mode tint to a second accent step (or
  `accent.muted`), leaving `status.warning` free for its documented use.

### N3 — `SUD-DAILY-HUB`'s `.exhausted` state uses a different failure language than its sibling `.failed`/board-load-failed states

- **Screen:** `SUD-DAILY-HUB`
- **Files:** `Packages/SudokuKit/Sources/SudokuUI/Daily/DailyHubView.swift:55-74`
  (`.exhausted`) vs. `:42-49` (`.failed`) and `SUD-BOARD-LOAD-FAILED`
- **Problem:** `.exhausted` renders `Color.clear` under a floating
  `.alert`, while every other same-tier failure state in the app (`.failed`,
  board-load-failed) uses an inline block (icon + message + action). Two
  different visual languages for what's structurally the same "this screen
  couldn't produce content" case.
- **Fix direction:** convert `.exhausted` to the same inline empty-state
  block pattern used by `.failed`, keeping its existing "Practice" /
  "Cancel" actions as inline buttons instead of alert actions.

### N4 — `docs/designs/01-root.md` documents a macOS sidebar selected-state that the code doesn't implement

- **Screen:** `HOME` / root shell (macOS)
- **Files:** `docs/designs/01-root.md:157` (claim) vs.
  `RootShellView.sidebarList` (actual — plain buttons, no selection state)
- **Problem:** the as-built root doc says the Mac sidebar row shows a
  selected-state tint for the current section; the implementation is a plain
  `Button` list with no selection tracking or tint logic.
- **Fix direction:** either add the selected-row tint the doc promises, or
  correct `01-root.md:157` to describe the current no-selection-state
  behavior.

### N5 — Settings' Acknowledgements row disappears on macOS with no documented hidden-vs-disabled contract

- **Screen:** `SETTINGS`
- **Files:** conditional `if let onAcknowledgements` render branch (macOS:
  nil → row does not render)
- **Problem:** on macOS the whole Acknowledgements list row is omitted
  (rather than shown-but-disabled) because the closure is `nil` on that
  platform. Neither `docs/screen-contracts.md` nor the design docs state
  whether "hidden" or "disabled-but-visible" is the intended cross-platform
  behavior for this row.
- **Fix direction:** document the intended behavior explicitly (this audit
  recommends keeping "hidden" — it matches the existing pattern for other
  platform-conditional rows) so a future contributor doesn't "fix" it either
  direction without knowing it was a choice.

---

## Explicitly out of scope / already settled

Carried over verbatim from the approved design outline — none of these are
reopened by this audit or the three proposals below:

- **Brand:** "Calm graph paper, lit by daylight" — no confetti, no
  slot-machine-style celebration, low chroma / high contrast, one accent
  color used sparingly. Any proposal element that reads as a celebratory
  burst is out.
- **Token discipline:** `difficulty.*` tokens are never to be promoted to
  general accent/CTA use (signaling-only, per `design-system.md`); all
  spacing must resolve through the 4pt `@ScaledMetric` ladder (4/8/12/16/24/
  32/48/64) once B2 above is fixed; type uses SwiftUI semantic font roles,
  never fixed point sizes (cell digit is the one documented exception).
- **#468 B1-B4 and the ATT Path A/B decision** — not audit findings; these
  were owner-only product calls, not something this audit adjudicates on its
  own authority. All five were subsequently adjudicated by Leader under
  explicit owner delegation on 2026-07-11 — see §Adjudicated 2026-07-11
  (owner-delegated) below for the recorded decisions and rationale.
- **Architecture:** MS and Sudoku are settled on a copy-paste-adapt model;
  no shared-hub extraction/refactor is in scope for any of the three
  proposals.
- **Monetization:** no subscription, no interstitial/rewarded ad units, no
  paid hints — none of the three proposals introduce or depend on any of
  these.

## Adjudicated 2026-07-11 (owner-delegated)

Owner explicitly delegated adjudication of the following open questions to
Leader ("裁定的給你選", 2026-07-11). Each decision below is a Leader call made
under that delegation, not an owner decision in its own right — individually
reversible if the owner later overrides it.

### FIRST-RUN — proposal withdrawn (owner, 2026-07-11)

**Decision:** owner withdrew the first-run coach-marks proposal in full on
2026-07-11; no first-run/onboarding feature ships in this round. The spec
file (`docs/v2/first-run-guide-proposal.md`) was removed from this branch.
**Note:** the underlying findings that motivated the proposal remain valid
findings, unaffected by the withdrawal — MS's tap-mode toggle still has zero
visual affordance for a first-time user, and the repo still has no
first-run/"seen before" flag anywhere.
This is an owner decision made directly, not a Leader call under delegation
— recorded here for the project's history, not reversible-by-Leader the way
the delegated items below are.

### #468 B1 — Completion-screen leaderboard zone — **SUPERSEDED 2026-07-11**

**[SUPERSEDED — kept verbatim for history, no longer the controlling
decision; see the superseding decision below]**

**Decision:** Expose. When Game Center is authenticated,
`SUD-COMPLETION-OVERLAY`/`MS-COMPLETION-OVERLAY` show a leaderboard row; when
signed out, the row is hidden entirely rather than rendered as a dead/
disabled button (echoes this round's concern about #685's GC signed-out dead
buttons).
**Rationale:** leaderboard localization and supporting infrastructure are
already invested in (recent commits); surfacing social proof on the
completion screen reinforces the daily habit loop the DAILY-CAL/STATS
proposals are trying to strengthen.
Delegated by owner; reversible if owner overrides.

**Superseding decision (owner, 2026-07-11, same day):** keep as-built — the
completion screen does **not** grow a leaderboard row. #698 already removed
the leaderboard-rendering mechanism from the completion path; this decision
is to *not* reintroduce it, not to leave a half-built feature in place.
**Rationale:** owner directly overrode Leader's delegated call above the
same day; recorded as a superseding entry rather than edited in place so the
reversal stays visible in the document's history.
This is the current, controlling decision for #468 B1 — an owner decision
made directly, not a Leader call under delegation.

### #468 B2 — MS `makeCompletionSinks` unwired

**Decision:** Confirmed gap. Wire `makeCompletionSinks` to the
`PersonalRecord`/achievements sinks the same way Sudoku's completion path
already does.
**Rationale:** `docs/v2/stats-screen-proposal.md`'s Minesweeper side depends
entirely on `PersonalRecord` data; leaving the sink unwired means the Stats
screen would ship with no MS data at all. Now recorded as a hard (blocking)
prerequisite in that proposal's §5.
Delegated by owner; reversible if owner overrides.

### #468 B3 — MS `reminderTapRoute` missing

**Decision:** Add it. MS reminder taps should route to the daily hub,
matching Sudoku's existing `reminderTapRoute` behavior.
**Rationale:** pure platform-parity gap; no design disagreement to resolve.
Delegated by owner; reversible if owner overrides.

### #468 B4 — MS re-view Close destination

**Decision:** Close lands on the Daily hub (matching Sudoku), not Home.
**Rationale:** matches the settlement-closure principle this round's
findings apply elsewhere (B1 above) — closing a re-view should return to a
screen where the completed state is visible; also keeps DAILY-CAL's
week-strip visually consistent across both apps' review flows.
Delegated by owner; reversible if owner overrides.

### ATT Path A vs. Path B

**Decision:** Stay on Path B (keep the ATT prompt, serve personalized ads on
consent) and fix the two defects `docs/v2/att-permission-ux-proposal.md`
already identified — cold-launch prompt timing, and the unlocalized purpose
string.
**Rationale:** adopts that document's own §7 recommendation; Path A would
mean deliberately removing already-shipped infrastructure (a materially
larger change surface) rather than polishing what's live.
Delegated by owner; reversible if owner overrides.

### DAILY-CAL — can a missed day be back-filled?

**Decision:** No. Past incomplete days remain view-only forever; there is no
retroactive completion path. Recorded directly in
`docs/v2/daily-calendar-streak-proposal.md` §Open questions for owner.
**Rationale:** a backfillable streak carries no integrity as a habit signal,
and the brand's monetization exclusions already rule out any streak-repair
mechanic that might otherwise motivate backfill.
Delegated by owner; reversible if owner overrides.

## What was not verified

Merged from both audit lanes; treat these as gaps in this round's evidence,
not confirmed non-issues:

- No on-device or simulator/screenshot verification was performed anywhere
  in this round — both lanes are 100% static source-reading. Confidence is
  medium-high, not proven.
- `GameRootViewModel.swift` was only read in the sections relevant to GC
  auth and resume-candidate flow, not in full.
- `CompletionViewModel` itself was not read directly — its behavior above was
  inferred from call sites, not its own implementation.
- Whether `MinesweeperAchievementID.swift` depends on `PersonalRecord` was
  not verified.
- iPad `regular` size-class rendering was inferred from `sizeClass` branch
  logic, not observed — no actual iPad or Split View/Slide Over layout was
  checked.
- The `@ScaledMetric` literal-value scan (finding B2) was limited to the four
  UI packages (`SudokuUI`, `MinesweeperUI`, `GameShellUI`, `SettingsUI`); it
  did not extend to every package in the repo.
- MS cell-size pixel values in M4 are derived from the sizing formula's logic
  branches, not measured on a rendered device.
- #468 / ATT-related code paths were intentionally skipped per the outline's
  instruction not to adjudicate those open questions.
