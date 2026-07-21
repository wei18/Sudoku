# Screen Contracts — Sudoku & Minesweeper (AS-BUILT)

**Status:** AS-BUILT · **Date:** 2026-07-05 · **main @** `9d6bf71`
**Companion to:** `docs/navigation-flows.md` (nav model + flow chains + negative
flows references the screen IDs defined here). This doc supersedes the flow
claims in `docs/v1/design.md` §How.5 and `docs/designs/01-06`.

**Scope:** iOS iPhone (`fullScreenCover` modal for the board, push for
everything else) and macOS (everything is `NavigationStack` push). iPad
regular uses the same route table via `NavigationSplitView`
(`GameShellUI/NavigationStackHost.swift`) — no separate contract needed.

**Conventions:**
- IDs are `HOME`, `SETTINGS`, … (shared) or `SUD-*` / `MS-*` (per-app).
- "Presentation" values: `push` (NavigationStack), `modal-full` (iOS
  `fullScreenCover`), `sheet(detent)`, `.alert`, `.confirmationDialog`,
  `overlay` (in-place `.overlay {}`, not a presentation at all), `external`
  (system settings / Apple GC UI / Google UMP), `side-effect` (no view
  change).
- DEBUG-only hooks (`-uitest-*` launch-arg routes, `UITestRouteModifier`,
  `UITestLaunchArg`) are **excluded** from every contract below — they exist
  only to seed E2E fixture state and have no product-facing entry point.

---

## HOME

**Entry points:** app launch (root content); "Close"/dismiss from any hub or
board; Settings back; reminder-tap when already elsewhere resets to `.daily`
(not Home) — see negative-flow table in `navigation-flows.md`.

**Code:** `GameAppKit/GameHomeView.swift`, `GameAppKit/GameHomeViewModel.swift`,
`GameShellUI/Home/HomeScreen.swift`.

**Element inventory:**

| Element | Copy (en) | a11y id |
|---|---|---|
| Resume pill (conditional) | `"Resume {Difficulty}"` / `"{m}:{ss}"` | none (combined element) |
| Daily card | title "Daily", subtitle Sudoku `"3 puzzles today"` / MS `"3 boards today"` | none¹ |
| Practice card | title "Practice", subtitle Sudoku `"Mixed difficulty pool"` / MS `"All difficulties"` | none¹ |
| Leaderboard card | title "Leaderboard", subtitle Sudoku `"Global / friends"` / MS `"Best times"` | none¹ |
| Settings card | title "Settings", subtitle Sudoku `"Account / language"` / MS `"Purchases / about"` | none¹ |
| Statistics card (conditional, `GameConfig.statsRoute != nil` — both apps wire it) | title "Statistics", subtitle `"Wins / times / averages"` (same copy both apps) | none² |
| Banner slot | ad or placeholder | — |

¹ `HomeScreen.cardAccessibilityIdentifier` defaults to `{ _ in nil }` and
neither app's `GameHomeView` callsite overrides it post-#557 — MS's older
"`MinesweeperHomeView.<mode>Card`" comment in `HomeScreen.swift` is stale for
the current shared path (CODE CONTRADICTED vs. that comment).

² **AS-BUILT NOTE (2026-07-21, #773/#844):** the Statistics card is NOT a
`HomeMode` case — it is injected below the 4-card grid via `GameHomeView`'s
`secondaryLink` slot (`GameAppKit/GameHomeView.swift:59,69-89`), gated on
`GameHomeViewModel.showsStatsEntry` (`GameHomeViewModel.swift:93`, backed by
a non-nil `statsRoute`). Both apps wire it in production:
`SudokuAppComposition/Live.swift:120` / `MinesweeperAppComposition/Live.swift:132`
(`statsRoute: .stats`). Because it is deliberately not a `HomeMode`,
`HomeModeItem.sidebarItems(from:)` (`GameShellUI/Home/HomeScreen.swift:103-116`)
does not include it — the Statistics card is absent from the macOS/iPad-regular
sidebar list, even though the Home grid (where the card itself renders) still
shows in the `NavigationSplitView` detail pane alongside that sidebar. An
undocumented-until-now asymmetry, not a trap (Statistics stays reachable on
every platform via the grid). Destination contract: `## STATS` below.

**Per-interaction outcome:**

| Element → action | Destination | Presentation | Back/Close lands on |
|---|---|---|---|
| Resume pill tap | `rootViewModel.resumeTapped()` → `path.append(candidate.route)` | push (→ `GameBoardRedirect` → `modal-full` on iOS; direct push on macOS) | Board's own Close/Leave (see `SUD-BOARD`/`MS-BOARD`) |
| Daily card tap | `.daily` | push → `SUD-DAILY-HUB`/`MS-DAILY-HUB` | pop → HOME |
| Practice card tap | `.practice` | push → `SUD-PRACTICE-HUB`/`MS-PRACTICE-HUB` | pop → HOME |
| Leaderboard card tap, GC authenticated | `GameCenterDashboard.present(nil)` | external (Apple GC UI) | dismiss → HOME (side-effect, no route change) |
| Leaderboard card tap, GC signed out | none | `.alert` → `GC-SIGNED-OUT-ALERT` | OK → HOME |
| Settings card tap | `.settings` | push → `SETTINGS` | pop → HOME |
| Statistics card tap | `viewModel.selectStats()` → `rootViewModel.path.append(statsRoute)` (`GameHomeViewModel.swift:102-105`) | push → `STATS` | pop → HOME |
| Sidebar row (macOS/iPad regular) | same targets as cards, via `RootShellView` sidebar (Statistics excluded — see element inventory footnote ²) | push | same |

**Covering behavior:** HOME is root content; nothing covers it except the
universal `GC-SIGNED-OUT-ALERT` (floats, mounted in `GameAppKit/GameRoot.swift:113-123`
— see #685, and the `GC-SIGNED-OUT-ALERT` contract below) and `ATT-PRIMER`
sheet (partial detent, applied by `makeGameApp`'s `universalRootModifiers`,
`GameAppKit/MakeGameApp+Modifiers.swift`). Underlying HOME stays fully
interactive under an `.alert`; a `.sheet` blocks interaction with HOME until
dismissed.

**State variants:** single state — HOME has no loading/empty/failed of its
own (`docs/designs/02-home.md` §a, still accurate). Degraded CK/GC: resume
pill silently absent (nil `resumeCandidate`); leaderboard card still taps
through to the alert path.

---

## SUD-DAILY-HUB

**Entry points:** HOME "Daily" card; reminder-tap deep link
(`reminderTapRoute` → `.daily` — mirrored on MS by #696, see
`navigation-flows.md` M7/N18).

**Code:** `SudokuUI/Daily/DailyHubView.swift`, `DailyHubViewModel.swift`,
`GameShellUI/DailyHubShellView.swift`.

**Element inventory:** a week-strip header card (`DailyStripView`,
`SudokuUI/Daily/DailyStripView.swift`) — a 7-dot rolling
completion/streak strip, injected into `DailyHubShellView`'s `header` slot
and rendered in **every** load state (idle/loading/loaded/empty/failed —
`DailyHubView.swift:56,162-165`) — PLUS the documented 3 `DailyPuzzleCard`s
(Easy/Medium/Hard), each combined a11y element `"{difficulty}"` + completed
checkmark or chevron.

**Per-interaction outcome:**

| Element → action | Destination | Presentation | Back/Close lands on |
|---|---|---|---|
| Completed PAST day's dot tap (today/missed dots inert — `DailyStripView.isTappable`, `:110-112`) | `dayTapped(_:)` (`DailyHubViewModel.swift:297-306`) — exactly 1 completed difficulty → opens review directly; >1 → `reviewPickerChoices` | 1 choice: push → `SUD-COMPLETION-REVIEW`. >1: `.confirmationDialog("Difficulty", …)` (`DailyHubView.swift:73-88`) → row tap → same push | picker: Cancel/scrim-tap → `dismissReviewPicker()`, stays on `SUD-DAILY-HUB`. Review: Close pops → `SUD-DAILY-HUB` |
| Un-completed card tap | `.board(puzzleId:)` | `GameBoardRedirect` → `modal-full` (iOS) / push (macOS) | Close/Leave → `SUD-DAILY-HUB` (modal dismiss or 1-entry pop) |
| Completed card tap | async `openCompleted` → `.completion(puzzleId:elapsedSeconds:mistakeCount:)` | push → `SUD-COMPLETION-REVIEW` | Close pops → `SUD-DAILY-HUB` |
| Completed card tap, snapshot load fails | falls back to `.board(puzzleId:)` (funneled error) | modal-full/push | as above |

**AS-BUILT NOTE (2026-07-21, #826):** the week-strip row above (day-dot →
direct review or a confirmationDialog picker → `SUD-COMPLETION-REVIEW`) was
entirely undocumented until now — added 2026-07-16, ~2 weeks before this
pass. This is a second, independent entry point into `SUD-COMPLETION-REVIEW`
alongside the Daily hub's own completed-card tap (see that contract's
updated Entry points line).

**Covering behavior:** none — plain hub content. The `.empty` (exhausted)
state renders `Color.clear` under a floating `.alert`.

**State variants:** `idle`/`loading` → `ProgressView`; `loaded` → 3-card grid
(1-col iPhone / 3-col regular); `.exhausted` → empty backdrop + `.alert`
`"Couldn't generate today's puzzle"` / `"Try a different difficulty, or come
back tomorrow."`, buttons **"Practice"** (`tryPracticeInstead()` swaps the
last path entry `.daily` → `.practice`, landing on `SUD-PRACTICE-HUB` which
actually has the difficulty picker the old label promised — #686) and
**"Cancel"** (`role: .cancel`, `dismissExhausted()` pops back to HOME rather
than leaving a blank backdrop with no recovery); `.failed(reason)` → inline
warning icon + `reason` text (no alert). CK-degraded: phase-2
completion-overlay fetch fails silently → all 3 cards render un-completed
(never blocks phase-1 render); the SAME degrade drops the week-strip header
to `.unknown` (`weekStrip = .unknown`, `DailyHubViewModel.swift:237-243`) —
the whole header card is omitted from layout rather than showing a subdued
skeleton (#843's all-or-nothing rule).

---

## MS-DAILY-HUB

**Entry points:** HOME "Daily" card; reminder-tap deep link (`reminderTapRoute`
→ `.daily`, fixed by #696 — now mirrors Sudoku; see `navigation-flows.md`
M7/N18).

**Code:** `MinesweeperUI/Daily/MinesweeperDailyHubView.swift`,
`MinesweeperDailyHubViewModel.swift`.

**Element inventory:** week-strip header card (`MinesweeperDailyStripView`,
`MinesweeperUI/Daily/MinesweeperDailyStripView.swift`) — a 7-dot
rolling completion/streak strip, rendered in the hub's `header` slot in
**every** load state (mirrors Sudoku's `DailyStripView`, see
`SUD-DAILY-HUB`'s own element inventory for the shared #826 design note) —
PLUS the 3 `MinesweeperDailyCardView`s, each combined a11y element; trailing
indicator is checkmark (completed) / `"Failed"` badge (mine hit) / chevron
(unplayed).

**Per-interaction outcome:**

| Element → action | Destination | Presentation | Back/Close lands on |
|---|---|---|---|
| Completed PAST day's dot tap (today/uncompleted dots inert — `MinesweeperDailyStripView.isTappable`, `:44-46`) | `dayTapped(_:)` (`MinesweeperDailyHubViewModel.swift:333-342`) — exactly 1 completed difficulty → opens review directly; >1 → `reviewPickerChoices` | 1 choice: push → `MS-COMPLETION-REVIEW`. >1: `.confirmationDialog("Difficulty", …)` (`MinesweeperDailyHubView.swift:66-85`) → row tap → same push | picker: Cancel/scrim-tap → `dismissReviewPicker()`, stays on `MS-DAILY-HUB`. Review: Close → `path?.wrappedValue.removeLast()` → `MS-DAILY-HUB` |
| Unplayed card tap | `.board(difficulty:seed:mode:.daily)` → wrapped by `MinesweeperDailyOpenGuardView` since `mode == .daily` (#842 — see `MS-BOARD-LOAD-FAILED` Tier 2 for the full `.checking`/`.completed`/`.failed`/`.playable` state machine) | `.checking` spinner, then: `.playable` → modal-full (iOS)/push (macOS) `MS-BOARD`; `.completed` → inline Completion (redirect); `.failed` → hands off to `MinesweeperDailyReplayLoaderView` | Close/Leave → `MS-DAILY-HUB` (all outcomes) |
| Completed card tap | `.completion(difficulty:mode:.daily)` (#386 re-view) | push → `MS-COMPLETION-REVIEW` | Close → `path?.wrappedValue.removeLast()` → back to `MS-DAILY-HUB` (fixed by #697) |
| Failed card tap | `.replayDailyBoard(difficulty:seed:)` → `MinesweeperDailyReplayLoaderView` (#841 — unscored free replay, no persistence, no GC submit; see `MS-BOARD-LOAD-FAILED` Tier 3 for its own `.loading`/`.loaded`/`.failed` states) | `.loading` → modal-full/push `MS-BOARD` on `.loaded`, or Close+Retry block on `.failed` | Close/Leave → `MS-DAILY-HUB` |

**AS-BUILT NOTE (2026-07-21, #841/#842):** the prior text here ("Unplayed
card tap → `.board(…)`, modal-full/push") described a direct, synchronous
mount with no loader in front of it. That was true pre-#842 and is corrected
above — see `MS-BOARD-LOAD-FAILED` for the full three-tier loader/guard
breakdown this hub's opens now funnel through.

**Covering behavior:** none. MS has **no `.empty`/`.exhausted` state** —
`dailyTrio(date:)` is synchronous and non-throwing (unlike Sudoku's
generator, which can exhaust).

**State variants:** `idle`/`loading` → `ProgressView`; `loaded` → 3-card grid
(`MinesweeperDailyHubState` truly has only these three cases — no
`.exhausted`/`.failed`, confirmed 2026-07-21). No `.failed`/`.empty` case
exists on `MinesweeperDailyHubState`. CK-degraded: phase-2 completed/failed-id
fetch errors silently → cards render unplayed; the same degrade drops the
week-strip header to `.unknown` (card omitted from layout entirely, mirrors
Sudoku's `weekStrip` degrade).

---

## SUD-PRACTICE-HUB

**Entry points:** HOME "Practice" card.

**Code:** `SudokuUI/Practice/PracticeHubView.swift`, `PracticeHubViewModel.swift`.

**Element inventory:**

| Element | Copy | a11y id |
|---|---|---|
| Difficulty segmented picker | Easy / Medium / Hard | none |
| "New Game" button (#885, 2026-07-18 — unified CTA copy; was "Draw new puzzle") | `Label("New Game", systemImage: "play.fill")` | none |
| Hint row (state-dependent) | `"{difficulty} · ready"` / redacted shimmer / `"{difficulty} · {puzzleId}"` / failure `reason` | none |

**Per-interaction outcome:**

| Element → action | Destination | Presentation | Back/Close lands on |
|---|---|---|---|
| Difficulty picker change | `selectDifficulty(_:)` — resets `loadingState` to `.idle` | side-effect (same screen) | — |
| "New Game" tap | ONE tap runs `drawPuzzle()` then `playTapped()` in the same `Task` — **not** a separate draw-then-play step; a `.failed` draw leaves the user on the hub (guarded by `.drawn` check) | on success: `.board(puzzleId:)` → modal-full (iOS) / push (macOS) | Close/Leave → `SUD-PRACTICE-HUB` |

**Covering behavior:** none.

**State variants:** `idle` (picker only) / `drawingQuiet` (<100ms, no
indicator) / `drawingShimmer` (>100ms, `.redacted` placeholder) / `drawn` /
`failed(reason)` (inline caption, button re-enabled, no navigation).

Anchors: CTA copy — `SudokuUI/Practice/PracticeHubView.swift:130-138` (both
`idle`/`drawn` branches render `Label("New Game", …)`).

---

## MS-PRACTICE-HUB

**Entry points:** HOME "Practice" card.

**Code:** `MinesweeperUI/Practice/MinesweeperPracticeHubView.swift`.

**Element inventory:**

| Element | Copy | a11y id |
|---|---|---|
| Difficulty segmented picker | Beginner / Intermediate / Expert | none |
| "New Game" button (#885, 2026-07-18 — unified CTA copy; was "Start") | `Label("New Game", systemImage: "play.fill")` + board-summary caption `"{rows} × {cols} · {mines} mines"` | `minesweeper.practiceHub.start` |

**Per-interaction outcome:**

| Element → action | Destination | Presentation | Back/Close lands on |
|---|---|---|---|
| "New Game" tap | synchronous — no draw/shimmer step at all (CODE CONTRADICTED vs. a Sudoku-mirrored assumption): mints a random seed and appends `.board(difficulty:seed:mode:.practice)` directly, wrapped by `MinesweeperFreshBoardLoaderView` (#910 — see `MS-BOARD-LOAD-FAILED` Tier 4) | `.loading` (brief) → modal-full (iOS) / push (macOS) | Close/Leave → `MS-PRACTICE-HUB` |

Anchors: CTA copy — `MinesweeperUI/Practice/MinesweeperPracticeHubView.swift:122-129`
(renders `Label("New Game", …)`).

**Covering behavior:** none. **State variants:** single state (no
loading/shimmer machinery exists — MS generation is synchronous).

---

## SUD-BOARD

**Entry points:** `SUD-DAILY-HUB` / `SUD-PRACTICE-HUB` card tap; HOME resume
pill; Play Again (from a prior `SUD-BOARD`'s completion overlay, practice
only).

**Code:** `SudokuUI/Board/BoardView.swift` (+`BoardView+Completion.swift`),
`GameViewModel.swift`, `BoardLoaderView.swift` (async wrapper, see
`SUD-BOARD-LOAD-FAILED`).

**Element inventory:** header (difficulty · elapsed timer · pause toggle),
9×9 grid, undo/redo, pencil toggle, 1-9 digit pad + delete, optional banner
(hidden while paused or terminal).

**Per-interaction outcome:**

| Element → action | Destination | Presentation | Back/Close lands on |
|---|---|---|---|
| Pause toggle tap, `.leaveReady` (#849/#868 — `status == .playing`, `elapsedSeconds == 0`, `!canUndo`: a freshly-opened board with nothing accrued to freeze) | `showReadyLeaveOverlay = true` (view-local flag; does **not** call `viewModel.pause()`) | `overlay` → `PAUSE-OVERLAY` | see `PAUSE-OVERLAY` |
| Pause toggle tap, `.pause` (elapsed time has ticked or a move was made) | `viewModel.pause()` | `overlay` → `PAUSE-OVERLAY` | see `PAUSE-OVERLAY` |
| Pause toggle tap, `.resume` | `viewModel.resume()` | `overlay` → `PAUSE-OVERLAY` | see `PAUSE-OVERLAY` |
| Digit / cell taps | in-place board mutation | — | — |
| Solve (session → `.completed`) | `makeCompletionViewModel()` | `overlay` → `SUD-COMPLETION-OVERLAY` | see that contract |

**AS-BUILT NOTE (2026-07-21, #849/#868):** the three rows above all branch on
the shared `leaveOrPauseState` (`BoardLeaveOrPauseState`,
`GameShellUI/BoardLeaveOrPauseControl.swift:26-34`),
`SudokuUI/Board/BoardView+AccessibilityHeader.swift:132-137`. Both
`viewModel.isPaused || showReadyLeaveOverlay` mount the same `PAUSE-OVERLAY`
(`SudokuUI/Board/BoardView.swift:106-119`); Resume from the `.leaveReady`
branch just clears the local flag rather than calling `resume()` — see
`PAUSE-OVERLAY`'s Resume row. This is Sudoku's analogue of MS-BOARD's
`.idle`-pre-first-tap gap (#681, same shared enum), just triggered by a
narrower time+undo condition instead of session status, because
`BoardLoaderView.startOrResume()` always drives Sudoku's session straight to
`.playing` at mount (no true `.idle` to mirror one-for-one).

**Covering behavior:** Board fills the whole screen
(`.frame(maxWidth:.infinity, maxHeight:.infinity)` applied *before* the
overlay attaches, #388/#610 fix) so `PAUSE-OVERLAY` / completion overlay can
truly cover edge-to-edge. Banner suppressed under both overlays.

**State variants:** N/A here — the async-load state machine lives in
`SUD-BOARD-LOAD-FAILED` (the loader wraps `BoardView`, not `BoardView` itself).

---

## MS-BOARD

**Entry points:** `MS-DAILY-HUB` card tap (fresh, replay, or re-view);
`MS-PRACTICE-HUB` Start; HOME resume pill (→ `.resumeBoard`, loads via
`MS-BOARD-LOAD-FAILED`'s loader); Play Again (practice only).

**Code:** `MinesweeperUI/MinesweeperBoardView.swift`.

**Element inventory:** status bar (mine count / status / elapsed,
`ViewThatFits` 1-row/2-row), reveal/flag mode toggle
(`minesweeper.board.pauseToggle` is actually the **pause** toggle a11y id —
verified unique 2026-07-05 (repo-wide grep)), grid, optional banner.

**Per-interaction outcome:**

| Element → action | Destination | Presentation | Back/Close lands on |
|---|---|---|---|
| Pause toggle tap (`.playing`) | `viewModel.pause()` | `overlay` → `PAUSE-OVERLAY` | see `PAUSE-OVERLAY` |
| Pause toggle tap (`.idle`, pre-first-tap — #681) | `showIdleLeaveOverlay = true` (view-local flag; does **not** call `viewModel.pause()`, which no-ops on `.idle` by design). Button renders as ✕ (`xmark`) with visible/a11y label `leave.game.leave` ("Leave"), not the pause glyph — the tap opens a leave-confirm, not a pause | `overlay` → `PAUSE-OVERLAY` | see `PAUSE-OVERLAY` |
| Cell reveal/flag | in-place mutation | — | — |
| Terminal (win or loss) | `makeCompletionViewModel()` | `overlay` → `MS-COMPLETION-OVERLAY` | see that contract |

**Covering behavior:** same full-screen-before-overlay pattern as Sudoku
(#388 fix, shared root cause). Banner suppressed while `isTerminal` or
`isPaused`.

**State variants:** N/A (see `MS-BOARD-LOAD-FAILED` for the loader's states).
**#681 (2026-07-05):** the pause toggle now mounts in `.idle` too — prior to
this fix the pre-first-tap board (mine placement defers to first reveal) had
NO exit: no back, no pause control, edge-swipe a no-op (#660), leaving
force-quit as the only escape from a fat-fingered difficulty pick. Sudoku is
immune (`SUD-BOARD`'s `BoardLoaderView.startOrResume()` drives the session to
`.playing` at mount, so it never renders in `.idle`); MS's first-click-safe
architecture makes `.idle` a real, reachable UI state.

---

## SUD-BOARD-LOAD-FAILED

**Entry points:** any `.board(puzzleId:)` route, wrapped by
`BoardLoaderView` before `SUD-BOARD` mounts.

**Code:** `SudokuUI/Board/BoardLoaderView.swift`.

**Element inventory:** warning icon, `"Couldn't load puzzle."`, classified
error caption, `Label("Close", systemImage: "xmark")` button (`.bordered`) +
`Label("Retry", systemImage: "arrow.clockwise")` button (`.bordered`).

**Per-interaction outcome:**

| Element → action | Destination | Presentation | Back/Close lands on |
|---|---|---|---|
| Close tap (#719) | `dismiss()` | modal dismiss (iOS) / pop (macOS) | HOME/hub that pushed the board — on iOS the board's `fullScreenCover` has no interactive dismiss otherwise, so Retry used to be the only affordance (a dead end for a player whose fetch keeps failing, e.g. offline) |
| Retry tap | re-runs `load()` in place | — (no navigation change) | success swaps to `SUD-BOARD`, repeat failure stays on this block |

Anchors: `SudokuUI/Board/BoardLoaderView.swift:210-247` (`failedBlock`, Close
`:236-241`, Retry `:242-247`).

**Covering behavior:** replaces the loader's content entirely (not an
overlay) — this is the state machine's `.failed` branch, not a covering
surface.

**State variants:** `.loading` (`ProgressView`) → `.loaded` (mounts
`SUD-BOARD`) or `.failed(UserFacingError)` (this block). Same shape for
`MS-BOARD-LOAD-FAILED` (`MinesweeperBoardLoaderView.swift`, copy: `"Couldn't
load saved game."` — only reachable via `.resumeBoard`, not fresh `.board`).

---

## MS-BOARD-LOAD-FAILED

**AS-BUILT NOTE (2026-07-21, #841/#842/#910):** this section previously
claimed "fresh `.board` / `.replayDailyBoard` mount `MS-BOARD` directly with
no async loader — no persistence fetch needed." That claim is **factually
wrong** as of the three issues above (confirmed live in production, not
dead/preview-only code) and is corrected below rather than merely extended —
it was superseded, not just stale.

Every daily board open, failed-daily replay, and now every fresh board open
(including Practice) funnels through one of four loader/guard tiers before
`MS-BOARD` mounts (or, for a completed daily, before an inline Completion
surface mounts instead). All are dispatched unconditionally from
`MinesweeperAppComposition/LiveRouteFactory+DailyBoardOpen.swift:44-131`
(`boardOpenDestination`, called from `LiveRouteFactory.swift`'s `.board`
case).

**Entry points:** `.resumeBoard(recordName:mode:)` (HOME resume pill — tier 1,
unchanged from pre-#841). `.board(mode: .daily)` (`MS-DAILY-HUB` unplayed
card — tier 2). `.replayDailyBoard` (`MS-DAILY-HUB` failed card, or a
`.daily` open tier 2 resolves `.failed` — tier 3). `.board(mode: .practice)`
(`MS-PRACTICE-HUB` Start, board Play Again — tier 4; tier 2's `.playable`
outcome also mounts through tier 4's sibling construction path, see below).

**Code:** `MinesweeperUI/MinesweeperBoardLoaderView.swift` (tier 1),
`MinesweeperUI/MinesweeperDailyOpenGuardView.swift` (tier 2, 267 lines, #842),
`MinesweeperUI/MinesweeperDailyReplayLoaderView.swift` (tier 3, #841),
`MinesweeperUI/MinesweeperFreshBoardLoaderView.swift` (tier 4, #910).

### Tier 1 — `.resumeBoard` (`MinesweeperBoardLoaderView`, unchanged pre-#841 shape)

**Element inventory:** warning icon, `"Couldn't load saved game."`,
classified error caption, `Label("Close", systemImage: "xmark")`
(`.bordered`) + `Label("Retry", systemImage: "arrow.clockwise")` (`.bordered`).

**Per-interaction outcome:**

| Element → action | Destination | Presentation | Back/Close lands on |
|---|---|---|---|
| Close tap (#719) | `dismiss()` | modal dismiss (iOS) / pop (macOS) | HOME (resume pill's caller) |
| Retry tap | re-runs `load()` in place | — | success swaps to `MS-BOARD`; repeat failure stays on this block |

Anchors: `MinesweeperUI/MinesweeperBoardLoaderView.swift:137-172`
(`failedBlock`, Close `:161-165`, Retry `:167-171`). **State variants:**
`.loading` (`ProgressView`) → `.loaded` (mounts `MS-BOARD`) or
`.failed(UserFacingError)` (this block) — a missing record is an **honest
failure** (`.unknown`), never a silent fresh board.

### Tier 2 — `.board(mode: .daily)` (`MinesweeperDailyOpenGuardView`, #842, entirely new)

Re-verifies the store's truth for TODAY before ever mounting a playable
board. Root cause: the tapped card's `isCompleted`/`isFailed` flags are
phase-1-stale until phase 2 lands (#530/#774) — a fast tap on a stale card
could otherwise overwrite a real Failed record with a different mine layout,
or double-submit a Game Center score on an already-completed daily.

**Element inventory:** `.checking` → `ProgressView` only. `.resolved(.completed)`
→ the same Completion card `MS-COMPLETION-REVIEW` builds (hero, Close).
`.resolved(.failed)` → delegates entirely to Tier 3 (no element of its own).
`.resolved(.playable)` → mounts `MS-BOARD`.

**Per-interaction outcome:**

| Outcome | Destination | Presentation | Back/Close lands on |
|---|---|---|---|
| `.completed` → Close tap | `exitToHub()` — dual-context: `path` pop if wired, else `dismiss()` (mirrors Sudoku's `BoardLoaderView.exitToHub` #842 contract) | iOS `dismiss()` / macOS pop | `MS-DAILY-HUB` |
| `.failed` | hands off to Tier 3 | — | see Tier 3 |
| `.playable` (or a fetch failure — degrades non-blocking per #526) | mounts `MinesweeperBoardView` | modal-full (iOS) / push (macOS) | Close/Leave → `MS-DAILY-HUB` |

Anchors: `MinesweeperUI/MinesweeperDailyOpenGuardView.swift:64-78`
(`GuardState`/`DailyOpenOutcome`), `:141-192` (`content` switch), `:198-205`
(`exitToHub`), `:207-231` (`resolve` — the #526 adjudication that a fetch
failure degrades to `.playable`, never blocks daily play). **Known accepted
cosmetic trade-off** (code comment, not measured): a `.failed` outcome shows
this tier's OWN `.checking` spinner, then Tier 3's `.loading` spinner — a
brief double-spinner rather than one continuous one.

### Tier 3 — `.replayDailyBoard` (`MinesweeperDailyReplayLoaderView`, #841, entirely new)

Recovers the daily's own persisted mine layout (written by the original
failed attempt) so a retry replays the SAME board instead of re-deriving a
different one from wherever the new first tap lands.

**Element inventory:** `.loading` → `ProgressView`. `.loaded` → mounts
`MinesweeperBoardView` (unscored: `gameCenter: nil`, no store/recordName).
`.failed(UserFacingError)` → warning icon, `"Couldn't load saved game."`,
`Label("Close", …)` + `Label("Retry", …)` (byte-mirror of #719's shape).

**Per-interaction outcome:**

| Element → action | Destination | Presentation | Back/Close lands on |
|---|---|---|---|
| Close tap (`.failed` block) | `dismiss()` | modal dismiss (iOS) / pop (macOS) | `MS-DAILY-HUB` |
| Retry tap | re-runs `load()` in place | — | success swaps to unscored `MS-BOARD`; repeat failure stays on this block |

Anchors: `MinesweeperUI/MinesweeperDailyReplayLoaderView.swift:73-77`
(`LoadState`), `:145-174` (`failedBlock`, Close `:159-164`, Retry `:165-170`),
`:223-247` (`makeReplaySession` — a `loadSnapshot` THROW propagates to
`.failed` instead of silently falling back, so a transient network blip
can't reintroduce the #841 bug; a confirmed-nil/corrupt snapshot falls back
to the ordinary deferred/first-click-safe layout).

### Tier 4 — `.board(mode: .practice)` (`MinesweeperFreshBoardLoaderView`, #910, entirely new)

Fixes a same-tick dismiss+represent bug: Play Again could silently keep
rendering the just-exploded board, because SwiftUI's `@State` `initialValue`
is honored only on first creation, and a same-position remount discarded
the fresh seed.

**Element inventory:** `.loading` → `ProgressView`. `.loaded` → mounts
`MinesweeperBoardView`, forced to a fresh identity via
`.id(BoardKey(difficulty:seed:))`. **No `.failed` case exists here** —
construction is fully synchronous (`MinesweeperGameViewModel.init` has no
async work), so unlike Tiers 1–3 this loader never renders a Close/Retry row
and was never a doc gap for one.

Anchors: `MinesweeperUI/MinesweeperFreshBoardLoaderView.swift:87-90`
(`LoadState`), `:139-146` (`.task(id:)` reload), `:159-178`
(`boardContent(viewModel:)`, the `.id()` fix). Cross-referenced from
`MS-PRACTICE-HUB` (Start tap) and `MS-COMPLETION-OVERLAY` (Play Again).

---

## PAUSE-OVERLAY

**Entry points:** pause toggle tap on `SUD-BOARD` or `MS-BOARD` (`MS-BOARD`
also mounts this from `.idle` pre-first-tap — #681).

**Code:** `GameShellUI/PauseOverlayView.swift` (shared component, mounted by
both boards).

**Element inventory:**

| Element | Copy | a11y id |
|---|---|---|
| Backdrop (mask-tap) | — | — |
| Title | `"leave.game.title"` (localized key, default text "Leave Game?"-style copy per app catalog) | — |
| Message | `"leave.game.message"` | — |
| Resume button | "Resume" | `game.pause.resume` |
| Leave button (destructive) | `"leave.game.leave"` | none |

**Per-interaction outcome:**

| Element → action | Destination | Presentation | Back/Close lands on |
|---|---|---|---|
| Mask tap (anywhere outside the card) | `onResume()` | side-effect | dismiss overlay → same board, `.playing` (or `.idle` — see next row) |
| Resume button tap | `onResume()` → `viewModel.resume()` on `SUD-BOARD` and `MS-BOARD` from `.paused`; on `MS-BOARD` from `.idle` (#681) OR `SUD-BOARD` from `.leaveReady` (#849/#868) `onResume()` instead just clears the view-local flag (`showIdleLeaveOverlay` / `showReadyLeaveOverlay`) — no session call, since `resume()` no-ops unless `.paused` | side-effect | same board, `.playing` (or unchanged `.idle`/`.leaveReady`) |
| Leave button tap | `dismiss()` (SwiftUI environment action — pops push OR dismisses `fullScreenCover`, same call either context) | modal dismiss (iOS) / pop (macOS) | HOME (iOS: cover collapses) or the hub that pushed the board (macOS: 1-entry pop) |

**Covering behavior:** full-screen `.ultraThinMaterial` blur, `.ignoresSafeArea()`
— hides the entire board (anti-cheat: can't study the puzzle while paused).
Board underneath is NOT interactive (mask intercepts all taps except its own
tap-to-resume gesture). Timer is stopped (frozen), not merely hidden.

**State variants:** single state; `onLeave` is only rendered when the host
wires it (both boards always wire it — no host omits it in production).

---

## SUD-COMPLETION-OVERLAY

**Entry points:** `SUD-BOARD` session reaching `.completed`.

**Code:** `SudokuUI/Board/BoardView+Completion.swift`,
`GameShellUI/Completion/CompletionOverlayScaffold.swift`,
`SudokuUI/Completion/CompletionView.swift`.

**Element inventory:**

| Element | Copy | a11y id |
|---|---|---|
| Hero | "Solved!" + elapsed `m:ss` + mistake count | `game.completion.hero` |
| Reminder affordance (Daily only, pre-#287-grant) | `"Remind me when tomorrow's puzzle is ready"` + subcopy | none |
| Play Again (practice only, iOS only — `onPresentBoard` wired) | "Play Again" `.borderedProminent` | none |
| Close | "Close" — `.borderedProminent` if alone, `.bordered` if Play Again present | none |

There is no leaderboard slice UI — #698 deleted the dead leaderboard-fetch
state machine (both apps hardcoded `state: .hidden` since v2.6 and it never
rendered). `docs/designs/06-completion.md`'s "Top 3 + Around you + View full
leaderboard" section is **CODE CONTRADICTED** — none of that renders today.

**Per-interaction outcome:**

| Element → action | Destination | Presentation | Back/Close lands on |
|---|---|---|---|
| Reminder affordance tap | `presentPrimer()` | `sheet(detent)` → `REMINDER-PRIMER` | dismiss → same overlay |
| Play Again tap | clears overlay, `exitToHub()`, then `playAgain(difficulty)` draws a fresh practice puzzle and re-presents | modal-full (new board instance) | new `SUD-BOARD` instance |
| Close tap | clears overlay, `exitToHub()` | iOS: `dismiss()` (cover collapses) · macOS: pop 1 path entry | HOME/hub that pushed the board (never the solved board — #667 fix) |

**Covering behavior:** in-board `.overlay` — background `.ignoresSafeArea()`,
card + CTAs stay within the safe area (so the hero icon clears the Dynamic
Island, #518). Board underneath is torn down on Close, not merely hidden.

**State variants:** single visible state — #698 deleted the VM's dead
loading/authenticated/unauthenticated/fetchFailed leaderboard states along
with the rendering machinery, so there is nothing left to vary.

---

## MS-COMPLETION-OVERLAY

**Entry points:** `MS-BOARD` reaching a terminal state (win or loss).

**Code:** `MinesweeperUI/MinesweeperBoardView.swift` `completionSurface`,
`MinesweeperUI/Completion/MinesweeperCompletionView.swift`.

**Element inventory:**

| Element | Copy | a11y id |
|---|---|---|
| Hero (win) | "You won" + elapsed | `game.completion.hero` |
| Hero (loss) | "Boom" (no elapsed shown in the loss hero per `CompletionOutcome`) | `game.completion.hero` |
| Reminder affordance (Daily win only, pre-authorization — #814, mirrors Sudoku) | `"Remind me when tomorrow's boards are ready"` + subcopy | none |
| Play Again (practice only, iOS only — `onPlayAgain` wired) | "Play Again" | none |
| Close | "Close" | none |

Same "no leaderboard zone" note as Sudoku — #698 deleted the dead fetch state
machine on this VM too.

**AS-BUILT NOTE (2026-07-21, #814):** the reminder affordance row above was
entirely undocumented until now — added to give MS's completion overlay the
same daily-win reminder priming Sudoku's `SUD-COMPLETION-OVERLAY` has had
since #287, closing a previously-real Sudoku-only asymmetry.
`MinesweeperCompletionView.swift:22-93` wires `ReminderPrimerCoordinator`/
`ReminderPrimerSheet` into the view's public init, gates the footer row on
`reminderPrimer.status == .notDetermined` (`:90-91`), and presents the same
`ReminderPrimerSheet` `SUD-COMPLETION-OVERLAY` uses with the identical
`[.medium, .large]` detent (`:76`, byte-parity confirmed against Sudoku's
`CompletionView.swift:62-68`). Wired daily-only:
`MinesweeperAppComposition/LiveRouteFactory.swift:308` (`mode == .daily ?
makeDailyReminderPrimer?() : nil`).

**Per-interaction outcome:**

| Element → action | Destination | Presentation | Back/Close lands on |
|---|---|---|---|
| Reminder affordance tap | `presentPrimer()` | `sheet(detent: [.medium, .large])` → `REMINDER-PRIMER` | dismiss → same overlay |
| Play Again tap | clears overlay VM, `dismiss()`, then `playAgain(difficulty)` with a fresh random seed, mounted via `MinesweeperFreshBoardLoaderView` (#910 — see `MS-BOARD-LOAD-FAILED` Tier 4; still `modal-full`, just with a brief `.loading` frame first, not the direct construction the row previously implied) | modal-full (new board instance) | new `MS-BOARD` instance |
| Close tap | clears overlay VM, `dismiss()` | iOS: cover collapses · macOS: pops the push (same `dismiss()` call both contexts — MS never branches on `path`) | HOME/hub that pushed the board |

**Covering behavior:** identical ZStack background/content split as Sudoku
(#518). Loss state: `"burst.fill"` icon, `status.failure` outcome kind.

**State variants:** win / loss (`didWin`); no mistake-count row (MS has no
mistakes concept, `mistakeCount: nil`).

---

## SUD-COMPLETION-REVIEW

**Entry points:** `SUD-DAILY-HUB` completed-card tap (#379) **OR** its
week-strip day-dot tap (direct, or via the confirmationDialog picker — #826,
see `SUD-DAILY-HUB`'s element inventory). **Never** reachable from a live
board — the live solve uses `SUD-COMPLETION-OVERLAY`, not this pushed route.

**Code:** `SudokuAppComposition/LiveRouteFactory.swift` `.completion` case
(wraps `CompletionView` in `CompletionOverlayScaffold` for push-context
parity with the overlay).

**Element inventory / outcome:** same `CompletionView` as
`SUD-COMPLETION-OVERLAY` but **no Play Again** (only ever constructed
without `onPlayAgain`) and the reminder primer is re-derived fresh
(`makeDailyReminderPrimer?()`).

| Element → action | Destination | Presentation | Back/Close lands on |
|---|---|---|---|
| Close tap | `path?.wrappedValue.removeLast()` | pop | `SUD-DAILY-HUB` |

**Covering behavior:** same `CompletionOverlayScaffold` shape as the overlay
(centred card, warm-paper background) — visually indistinguishable from
`SUD-COMPLETION-OVERLAY` even though this is a genuine stack push, not an
in-board overlay. **State variants:** none; frozen snapshot values passed at
construction (no live VM).

---

## MS-COMPLETION-REVIEW

**Entry points:** `MS-DAILY-HUB` completed-card tap (#386) **OR** its
week-strip day-dot tap (direct, or via the confirmationDialog picker — #826,
see `MS-DAILY-HUB`'s element inventory). Same non-reachability-from-live-board
note as Sudoku.

**Code:** `MinesweeperAppComposition/LiveRouteFactory.swift` `.completion` case.

**Element inventory:** `MinesweeperCompletionView` seeded `didWin: true`,
`elapsedSeconds: 0`, **`showsElapsedTime: false`** — the hero omits the time
row entirely (MS has no stored elapsed for a past daily, #284); there is no
leaderboard zone to show a real ranked time in (#698).

| Element → action | Destination | Presentation | Back/Close lands on |
|---|---|---|---|
| Close tap | `path?.wrappedValue.removeLast()` | pop one entry | `MS-DAILY-HUB` — fixed by #697, now mirrors Sudoku |

**Covering behavior / state variants:** same scaffold shape as
`SUD-COMPLETION-REVIEW`; no Play Again; no mistake row.

---

## STATS

**Added 2026-07-21 (#773/#844) — closes F-HOME-1: this screen shipped in both
apps with no contract until now.**

**Entry points:** HOME Statistics card only (see `HOME`'s element inventory
footnote ² — not a `HomeMode`, injected via `GameHomeView`'s `secondaryLink`
slot). No other entry point exists (not reachable from Settings, Daily, or
Practice).

**Code:** `SudokuUI/Stats/StatsView.swift`, `SudokuUI/Stats/StatsViewModel.swift`;
`MinesweeperUI/Stats/MinesweeperStatsView.swift`,
`MinesweeperUI/Stats/MinesweeperStatsViewModel.swift`; route wiring
`SudokuAppComposition/LiveRouteFactory.swift:275-286` (`.stats` case) /
`MinesweeperAppComposition/LiveRouteFactory.swift:326-327` +
`LiveRouteFactory+Stats.swift`.

**Element inventory:**

| Element | Copy | a11y id |
|---|---|---|
| "Daily" section header + 3 tiles (Easy/Medium/Hard, or MS Beginner/Intermediate/Expert) | section title "Daily"; each tile: difficulty-tinted dot + name, completed count, best time (`m:ss` or `—`), average time | none (each tile is one combined a11y element, e.g. "Easy, 14 completed, best time 3 minutes 12 seconds, average time 4 minutes 2 seconds") |
| "Practice" section header + 3 tiles | same shape, section title "Practice" | same pattern |
| Footer caption | `"Stats sync with your iCloud account."` | none |

**Per-interaction outcome:** **none — this screen has no forward
navigation.** Every tile (`StatsTileView`) is a static, non-interactive
`VStack` (no `Button`/tap gesture in either app's tile view). The only
navigation is the system back (push pop → `HOME`).

**Covering behavior:** none — plain push content, no sheet/overlay of its own.

**State variants:** seeded EMPTY on first render (`Difficulty.allCases.map(StatsTile.empty)`,
`StatsViewModel.swift:74-76`) so the screen never blocks, then filled
tile-by-tile as the async CloudKit reads land (`bootstrap()`,
`StatsViewModel.swift:96-102`). CK-degraded: a per-difficulty fetch failure
(offline / iCloud signed-out) reports through `errorReporter` and that one
tile stays at its empty placeholder (`0` completed, `—` best/average) — the
screen never surfaces a blocking error state of its own, mirroring the Daily
hubs' phase-2 graceful-degrade posture (`StatsViewModel.swift:107-123`). No
monetization surface (explicit scope exclusion, `docs/v2/stats-screen-proposal.md`
§7).

---

## SETTINGS

**Entry points:** HOME "Settings" card / sidebar row.

**Code:** `SudokuUI/Settings/SettingsView.swift`,
`MinesweeperUI/SettingsView.swift`, `SettingsKit/Sources/SettingsUI/Settings/*`.

**Element inventory (row order):** Purchases section (host-injected IAP
rows), GC status row (`settings.gameCenter`), reminders section (see
`REMINDER-*` ids under it), Sound section (mute/music-volume/sfx-volume/
music-enabled/haptics toggles, ids `audio.settings.*`), About section
(Version row +, Sudoku-only, Generator row), Notices section
(acknowledgements deep-link, copyright), Storage section "Clear cache"
button.

**Per-interaction outcome:**

| Element → action | Destination | Presentation | Back/Close lands on |
|---|---|---|---|
| GC status row tap (`settings.gameCenter`) | `resolvedOnGameCenter()` → `presentGameCenter` closure → `GameRootViewModel.presentGameCenterOrAlert` (same guard the Home leaderboard card uses) | authenticated: external → `GC-DASHBOARD`. Signed out: `.alert` → `GC-SIGNED-OUT-ALERT` | authenticated: dismiss → `SETTINGS` (side-effect). Signed out: OK → `SETTINGS` |
| Reminders "Enable"/"Turn On" row tap | `model.enable()` | `sheet(detent: .medium)` → `REMINDER-PRIMER` | dismiss → `SETTINGS` |
| Reminders denied-status row tap | `model.showDeniedExplainer()` | `sheet(detent: .medium)` → `REMINDER-DENIED` | dismiss → `SETTINGS` |
| Reminders "Turn off reminders" tap | `model.disable()` | side-effect | `SETTINGS` (status row switches back to enable row) |
| "Clear cache" tap | `showClearCacheConfirmation = true` | `.confirmationDialog` → `CLEAR-CACHE-DIALOG` | see that contract |
| Acknowledgements deep-link tap (iOS only) | `UIApplication.shared.open(UIApplication.openSettingsURLString)` | external (system Settings.app) | user manually returns via app-switcher — no in-app back |

**AS-BUILT NOTE (2026-07-21):** the GC status row was listed in this
contract's element inventory but had NO interaction row at all until now —
it is a second, equally real entry point into `GC-DASHBOARD` /
`GC-SIGNED-OUT-ALERT` alongside the Home leaderboard card (#685/#714;
guard-parity #832). Anchors: `GameAppKit/Sources/GameAppKit/SettingsView.swift:65-99`
(`presentGameCenter` injection + `resolvedOnGameCenter()`'s debug assert),
`GameAppKit/Sources/GameAppKit/GameRootViewModel.swift:271-278`
(`presentGameCenterOrAlert`, the shared guard).

**Covering behavior:** since #516, `SettingsShellView` paints the app's
warm-paper theme background behind the native `Form`
(`.background(theme.surface.background.resolved.ignoresSafeArea())`) — a
deliberate tonal-continuity exception to the "unbranded Settings" rationale
in `docs/designs/08-settings.md` §f (structure/rows remain native).

**State variants:** single state (all reads are synchronous/memoized) except
the reminders sub-section, which branches on
`.notDetermined`/`.authorized`/`.provisional`/`.denied`.

---

## REMINDER-PRIMER

**Entry points:** `SETTINGS` enable row; `SUD-COMPLETION-OVERLAY` reminder
affordance (Daily solve only); `MS-COMPLETION-OVERLAY` reminder affordance
(Daily solve only, #814 — now mirrors Sudoku, see that contract's dated
note. Prior text here read "MS's completion overlay has no reminder
affordance, only Settings-initiated" — that asymmetry is closed as of #814).

**Code:** `SettingsKit/Sources/SettingsUI/Reminders/ReminderPrimerSheet.swift`
(shared component, both apps inject their own `ReminderPrimerCopy`).

**Element inventory:** icon tile, title, lede, 3-bullet promise block, accept
CTA (primary), decline CTA "Not now" (repeatable), fineprint.

**Per-interaction outcome:**

| Element → action | Destination | Presentation | Back/Close lands on |
|---|---|---|---|
| Accept | `model.acceptPrimer()` → fires the ONE-SHOT system notification permission prompt, then schedules | dismiss sheet; on `.denied` result no further in-app surface fires automatically — user must revisit `SETTINGS` to see the denied row | `SETTINGS` or the Completion overlay it was opened from |
| Decline "Not now" | `model.declinePrimer()` — repeatable, does not ask iOS | dismiss sheet | same origin, primer re-offerable next time |

**Covering behavior:** `.sheet(detent: .medium)` for the Settings-initiated
case (single fixed detent, drag indicator hidden, R6.3); the
Completion-initiated case uses `.presentationDetents([.medium, .large])`
(drag allowed) — a genuine, intentional divergence between the two call
sites. Origin screen stays mounted underneath but not interactive.

**State variants:** `isRequesting` shows a spinner on the accept button while
the system prompt is in flight.

---

## REMINDER-DENIED

**Entry points:** `SETTINGS` denied-status row only (no Completion-overlay
entry point exists).

**Code:** `ReminderDeniedExplainer` (same file as `REMINDER-PRIMER`).

**Element inventory:** icon, title, message, iOS: `Label("Open Settings",
systemImage:"gearshape")` deep-link button; macOS: static `macOSGuidance`
text (no deep-link, P12 gap) — dismiss row.

**Per-interaction outcome:**

| Element → action | Destination | Presentation | Back/Close lands on |
|---|---|---|---|
| "Open Settings" (iOS) | opens `UIApplication.openNotificationSettingsURLString`-style system URL | external | user returns manually |
| Dismiss | `model.dismissDeniedExplainer()` | dismiss sheet | `SETTINGS` |

**Covering behavior:** `.sheet(detent: .medium)`, drag indicator hidden.
**State variants:** platform-conditional body (iOS button vs. macOS text),
otherwise single state.

---

## CLEAR-CACHE-DIALOG

**Entry points:** `SETTINGS` "Clear cache" button.

**Code:** `SettingsKit/Sources/SettingsUI/Settings/SettingsAboutStorage.swift`
`SettingsStorageSection`.

**Element inventory:** title `"Reset session cache"` (`titleVisibility:
.visible`), message `"Generated puzzles will be re-derived next play. Saved
games are not affected."`, "Clear cache" (destructive), "Cancel".

**Per-interaction outcome:**

| Element → action | Destination | Presentation | Back/Close lands on |
|---|---|---|---|
| "Clear cache" confirm | `clearCache()` async → success toast `"Cache cleared"` or failure toast `"Couldn't clear cache"` + error-funnel report | dismiss dialog; toast overlay (`ToastController`, floats above `SETTINGS`) | `SETTINGS` |
| "Cancel" | no-op | dismiss dialog | `SETTINGS` |

**Covering behavior:** system `.confirmationDialog` (action sheet on iPhone,
popover-anchored on macOS/iPad) — floats above `SETTINGS`, which stays
visible but non-interactive until dismissed.

**State variants:** none.

---

## GC-DASHBOARD

**Entry points:** HOME leaderboard card (authenticated only); `SETTINGS` GC
status row (authenticated only, #685/#714 — same
`presentGameCenterOrAlert` guard as the Home card, see `SETTINGS`'s
interaction table). No behavioral drift between the two entry points, only
a prior documentation gap (this contract undercounted its own entry points).

**Code:** `GameCenterKit/Sources/GameCenterClient/GameCenterDashboard.swift`.

**Per-interaction outcome:** `present(leaderboardId: nil)` →
`GKAccessPoint.shared.trigger(state: .leaderboards)` (both platforms; no
focused-ID variant is reachable from a nav-flow entry point today — the
focused-ID path exists in the API but nothing in either app's flow calls it
with a non-nil id, since the Completion "View full leaderboard" CTA that
would have used it is removed, see `SUD-COMPLETION-OVERLAY`).

**Covering behavior:** external, fully modal Apple UI; app content
underneath is suspended, not merely covered.

**State variants:** entirely Apple-owned (auth, scope, time-range, profile
drill-through) — out of this repo's contract.

---

## GC-SIGNED-OUT-ALERT

**Entry points:** HOME leaderboard card tap, OR `SETTINGS` GC status row tap
(#685/#714, same guard — see `SETTINGS`'s interaction table), while
`authState != .authenticated`.

**Code:** `GameAppKit/GameRoot.swift:113-123` — bound via a hand-rolled
`Binding(get:set:)` off the stable `GameRootViewModel.showGameCenterSignedOutAlert`
flag, not a transient per-render VM (deliberate fix for the "alert never
fires" computed-property footgun).

**AS-BUILT NOTE (2026-07-21, #685):** this contract previously cited
`GameAppKit/MakeGameApp+Modifiers.swift` `universalRootModifiers` as the
alert's home. That file's own header comment documents why the alert moved:
`universalRootModifiers` is called exactly once from the plain `makeGameApp`
function, never from inside a SwiftUI View's own `body`, so the Observable
flag flip was never picked back up by the render graph (confirmed via
instrumented sim repro). The alert now lives directly in `GameRoot.body`,
alongside the `fullScreenCover` binding that already worked via the same
`@Observable`-flag pattern.

**Element inventory:** title "Sign in to Game Center", message "Sign in to
Game Center to compare with others.", "OK" (cancel role).

**Per-interaction outcome:** OK → dismiss, no route change.

**Covering behavior:** system `.alert` — floats, HOME stays visible but
non-interactive until dismissed.

---

## ATT-PRIMER

**Entry points:** first ad-relevant moment — `GameHomeView`'s banner slot
`.task` calls `attPrimer.maybePresentOnAdContext()` (i.e., the **first Home
banner load**, not app launch). One-offer-per-launch latch
(`hasOffered`). **Does not block Home interaction** — Home is already
rendered and tappable when this sheet appears (CODE CONTRADICTED vs. a
"boot-time gate" assumption).

**Code:** `AppMonetizationKit/Sources/MonetizationUI/ATTPrimerSheet.swift`,
`ATTPrimerCoordinator.swift`.

**Element inventory:** icon, `att.primer.title`, `att.primer.body`,
`att.primer.continue` (primary), `att.primer.notNow`.

**Per-interaction outcome:**

| Element → action | Destination | Presentation | Back/Close lands on |
|---|---|---|---|
| Continue | dismiss this sheet → `requestSystemPrompt()` → **external** system ATT dialog | sheet → external | HOME, banner now resolves per the ATT-determined state |
| Not now | `declinePrimer()` — no system prompt fired; latched for the rest of the session | dismiss sheet | HOME |

**Covering behavior:** `.sheet` with `[.medium, .large]` detents, drag
indicator visible — HOME stays mounted but non-interactive underneath.

**State variants:** only presented while ATT status is `.notDetermined`;
already-determined statuses skip the sheet entirely (silent).

---

## UMP-CONSENT (external, no in-app UI)

**Entry points:** app launch, inside `bootMonetization()`'s boot sequence
(`UMP → ATT-no-op → AdMob init`, `MakeGameApp+Helpers.swift` /
`MonetizationBootCoordinator`). Runs concurrently with first-frame rendering
via `.onAppear { Task { … } }` — **never blocks Home** (CODE CONTRADICTED vs.
a "consent dialog before Home interaction" assumption: Home renders
immediately; Google's UMP SDK may present its own EEA/UK-only consent form as
a system-level surface this repo's code does not construct or own).

**Code:** `GameAppKit/MakeGameApp+Helpers.swift` `bootMonetization`,
`AppMonetizationKit` `MonetizationBootCoordinator` (UMP/ATT/AdMob strict
ordering, non-blocking, every step attempted regardless of an earlier
failure).

**State variants:** N/A — outside this repo's UI surface; documented here
only so the boot-sequence claim in `navigation-flows.md` §2 has a concrete
anchor.
