# Screen Contracts — Sudoku & Minesweeper (AS-BUILT)

**Status:** AS-BUILT · **Date:** 2026-07-05 · **main @** `9d6bf71`

> ⚠️ **Partially superseded by 3.0 (#1020, 2026-08-25).** The HOME screen
> (`GameHomeView` / `GameHomeViewModel` / `HomeScreen`), the hand-authored
> sidebar (`SidebarItem` / `NavigationStackHost`) and the `home` / `daily` /
> `practice` / `stats` routes no longer exist. The root is a `sidebarAdaptable`
> TabView (`GameShellUI/RootShellView.swift`) with one path per tab
> (`GameAppKit/GameRootViewModel.swift`); ATT-PRIMER's entry point is the Today
> tab's banner slot (`GameAppKit/TodayTabHost.swift`, C-33); the HOME
> Leaderboard card is gone (C-35) and Progress gained an `Achievements` row
> (`GameAppKit/AchievementsRow.swift`, C-36); resume-pill refresh follows
> design.md §3.6.2 (C-34 / N-AB). Current model: `docs/designs/v3/design.md`
> §2.1–§2.3, §3.6, §9.4. Rows below that cite the retired screens are kept as
> the pre-3.0 as-built record until this doc is regenerated for 3.0.
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
| Banner slot | ad or placeholder | `monetization.banner.slot` (#933) |
| (root container) | — | `game.home.root` (#936 — E2E landing anchor) |

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
`HomeModeItem.sidebarItems(from:)` (`GameShellUI/Home/HomeScreen.swift:115-127`)
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

> **Re-anchored to the as-built 3.0 shape (2026-09-03, #1021 Phase A/B).**
> The pre-3.0 record below (the retired per-app week-strip card and puzzle
> card view, HOME "Daily"
> card entry) is superseded — HOME is retired (#1020), the week-strip is now
> the shared `StreakHeaderView`, and the trio is the shared `DailyCardContent`.
> Routes/destinations are unchanged; visuals and the state machine are not.

**Entry points:** Today tab root (`AppTab.today` — no HOME); reminder-tap
deep link (`reminderTapRoute` → resets to the Today tab, mirrored on MS by
#696, see `navigation-flows.md` M7/N18).

**Code:** `SudokuUI/Daily/DailyHubView.swift`, `DailyHubViewModel.swift`,
`SudokuUI/Daily/TodayMapper.swift`, `GameShellUI/DailyHubShellView.swift`,
`GameShellUI/TabRoots/StreakHeaderView.swift`,
`GameShellUI/TabRoots/DailyCardView.swift`,
`GameShellUI/TabRoots/TodayAllDoneBlock.swift`,
`GameShellUI/TabRoots/TodayPresentation.swift`.

**Element inventory:**

| Element | Copy (en) | a11y id |
|---|---|---|
| Streak header row (`StreakHeaderView`, plain content-layer text, NOT a card — injected into the shell's `header` slot at `DailyHubView.swift:228-239`, rendered in every load state) | `"{current} day streak"` + conditional `"Best {longest}"`; combined a11y label `"{current} day streak, best {longest}"` (`StreakHeaderView.swift:136-149`) | none (`.accessibilityElement(children: .contain)`) |
| Streak pips (7, oldest→newest); completed-PAST-day pips are tappable Buttons (`StreakHeaderView.swift:96-119`) | per-pip a11y `"{weekday}, completed"` / `"{weekday}, missed"` (`TodayMapper.pipAccessibilityLabel`, `TodayMapper.swift:116-121`) + hint `"View this day's result"` | none per-pip; non-tappable pips are `.accessibilityHidden` |
| 3 `DailyCardContent` rows (`DailyCardView.swift:71-139`, `HubCard` standard material) | title = difficulty name; status `"Solved"` / `"Solved · {m:ss}"` / `"In progress · {m:ss}"` / `"Not started · {N} givens"` (`TodayMapper.statusText`, `TodayMapper.swift:171-188`); combined a11y `"{title}, {statusText}"` (`DailyCardView.swift:157-159`) | `sudoku.dailyHub.card.completed` on a completed card, else none |
| `TodayAllDoneBlock` (`allDone` state only) | `"All done for today"` / `"Come back tomorrow for 3 new puzzles."` | none (`.accessibilityElement(children: .combine)`) |
| Exhausted inline block (`.empty` lift of `.exhausted`, `DailyHubView.swift:159-226`) | `"Couldn't generate today's puzzle"` / `"Try a different difficulty, or come back tomorrow."` + buttons `"Practice"` / `"Cancel"` | message: `sudoku.dailyHub.exhausted`; buttons: `sudoku.dailyHub.exhausted.practice` / `.exhausted.cancel` (id on the leaf `Text`, not the container — an id on the enclosing `VStack` cascades down and clobbers the buttons' own ids) |
| Root anchor (zero-size marker, sibling to the header, `DailyHubView.swift:255-259`) | — | `sudoku.dailyHub.root` |

**Per-interaction outcome:** (routes unchanged from the pre-3.0 record — the
rebuild changed the visuals and state machine, not the destinations)

| Element → action | Destination | Presentation | Back/Close lands on |
|---|---|---|---|
| Completed PAST day's pip tap (today/missed pips inert — `tappablePipIndices`, `StreakHeaderView.swift:100`) | `dayTapped(_:)` (`DailyHubViewModel.swift`) — exactly 1 completed difficulty → opens review directly; >1 → `reviewPickerChoices` | 1 choice: push → `SUD-COMPLETION-REVIEW`. >1: `.confirmationDialog("Difficulty", …)` (`DailyHubView.swift:89-104`) → row tap → same push | picker: Cancel/scrim-tap → `dismissReviewPicker()`, stays on `SUD-DAILY-HUB`. Review: Close pops → `SUD-DAILY-HUB` |
| Un-completed/in-progress card tap | `.board(puzzleId:)` | `GameBoardRedirect` → `modal-full` (iOS) / push (macOS) | Close/Leave → `SUD-DAILY-HUB` (modal dismiss or 1-entry pop) |
| Completed card tap | async `openCompleted` → `.completion(puzzleId:elapsedSeconds:mistakeCount:)` | push → `SUD-COMPLETION-REVIEW` | Close pops → `SUD-DAILY-HUB` |
| Completed card tap, snapshot load fails | falls back to `.board(puzzleId:)` (funneled error) | modal-full/push | as above |
| Exhausted block "Practice" tap | `tryPracticeInstead()` swaps the last path entry `.daily` → `.practice` (#686 — the label promised a difficulty picker this hub doesn't have) | push (in place) → `SUD-PRACTICE-HUB` | — |
| Exhausted block "Cancel" tap | `dismissExhausted()` drops to an empty `.loaded` state | side-effect | stays on `SUD-DAILY-HUB` (Today is a tab root now, not a route to pop from — #1020) |

**Covering behavior:** none — plain tab-root content, no HOME to cover. The
`.confirmationDialog` picker is the only transient presentation this screen
owns.

**State variants** (`TodayMapper.present(state:inProgress:isPhase2Degraded:)`,
`TodayMapper.swift:59-81`; `TodayPresentation<Card>`, `TodayPresentation.swift`):

| Variant | Trigger | Render |
|---|---|---|
| `loading` | `.idle`/`.loading` | 3 grid-preserving skeleton `DailyCardContent` rows (shell's `loading:` slot, `DailyHubView.swift:262-274`) — NOT a bare spinner (design.md §3.1 "保留格線結構,不是空白方塊") |
| `loaded` | `.loaded`, not all completed, not phase-2-degraded | 3 `DailyCardContent` rows, 1-/3-column grid |
| `allDone` | `.loaded`, every card `isCompleted` | `TodayAllDoneBlock` replaces the 3 cards, below the streak header |
| `degraded` | phase-2 completion-overlay fetch fails (`isPhase2Degraded`), or phase-1 `.failed` | thumbnails still render (seed-derived, no CK dependency) but every card is forced to "not started" (`TodayMapper.swift:19-26`); a phase-1 `.failed` renders `skeletonCards()` in place of real cards |
| `exhausted` | `.exhausted` — Sudoku only, generator can run out | inline icon+message+action block, see Element inventory above |

MS structurally has no `exhausted` case (`TodayPresentation.swift:8-10`) — see
`MS-DAILY-HUB`.

**Glass status:** content-layer glass retired — `HubCard`
(`GameShellUI/TabRoots/HubCard.swift:23-27`) renders on `theme.surface.primary`,
a standard material, never `glassEffect` (design.md §4.2: content-layer cards
are not eligible for the Slider/Toggle transient-interaction glass exception).
The streak header row is plain content-layer text with no container at all
(`StreakHeaderView.swift:1-6`).

---

## MS-DAILY-HUB

> **Re-anchored to the as-built 3.0 shape (2026-09-03, #1021 Phase A/B).**
> The pre-3.0 record below (the retired per-app week-strip card and board
> card view, HOME "Daily" card entry) is superseded — see
> `SUD-DAILY-HUB`'s callout for the shared rationale. Routes/destinations are
> unchanged; visuals and the state machine are not.

**Entry points:** Today tab root (`AppTab.today` — no HOME); reminder-tap
deep link (`reminderTapRoute` → resets to the Today tab, mirrors Sudoku; see
`navigation-flows.md` M7/N18).

**Code:** `MinesweeperUI/Daily/MinesweeperDailyHubView.swift`,
`MinesweeperDailyHubViewModel.swift`,
`MinesweeperUI/Daily/MinesweeperTodayMapper.swift`,
`GameShellUI/DailyHubShellView.swift`,
`GameShellUI/TabRoots/StreakHeaderView.swift`,
`GameShellUI/TabRoots/DailyCardView.swift`,
`GameShellUI/TabRoots/TodayAllDoneBlock.swift`.

**Element inventory:**

| Element | Copy (en) | a11y id |
|---|---|---|
| Streak header row (shared `StreakHeaderView`, `MinesweeperDailyHubView.swift:144-151`) | same shape as Sudoku's — see `SUD-DAILY-HUB` | none (combined element) |
| Streak pips | per-pip a11y `"{weekday}, completed"` / `"{weekday}, missed"` (`MinesweeperTodayMapper.pipAccessibilityLabel`, `MinesweeperTodayMapper.swift:114-119`) | none per-pip |
| 3 `DailyCardContent` rows (shared component; `MinesweeperTodayMapper.statusText`, `MinesweeperTodayMapper.swift:165-189`) | title = difficulty name; status `"Solved"` / `"Solved · {m:ss}"` / `"Failed"` / `"In progress · {m:ss}"` / `"Not started · {R} × {C} · {M} mines"` | `minesweeper.dailyHub.card.completed` on a completed card, else none |
| `TodayAllDoneBlock` (`allDone` state only) | `"All done for today"` / `"Come back tomorrow for 3 new boards."` | none |
| Root anchor (`MinesweeperDailyHubView.swift:167-171`) | — | `minesweeper.dailyHub.root` |

MS has **no exhausted/empty block** — `dailyTrio(date:)` is synchronous and
non-throwing (`TodayPresentation.swift:8-10`,
`MinesweeperTodayMapper.swift:6-10`).

**Per-interaction outcome:**

| Element → action | Destination | Presentation | Back/Close lands on |
|---|---|---|---|
| Completed PAST day's pip tap (`tappablePipIndices`) | `dayTapped(_:)` (`MinesweeperDailyHubViewModel.swift`) — exactly 1 completed difficulty → opens review directly; >1 → `reviewPickerChoices` | 1 choice: push → `MS-COMPLETION-REVIEW`. >1: `.confirmationDialog("Difficulty", …)` (`MinesweeperDailyHubView.swift:81-100`) → row tap → same push | picker: Cancel/scrim-tap → `dismissReviewPicker()`, stays on `MS-DAILY-HUB`. Review: Close → `path?.wrappedValue.removeLast()` → `MS-DAILY-HUB` |
| Unplayed card tap | `.board(difficulty:seed:mode:.daily)` → `MinesweeperDailyOpenGuardView` (#842, see `MS-BOARD-LOAD-FAILED` Tier 2) | `.checking` spinner, then: `.playable` → modal-full (iOS)/push (macOS); `.completed` → inline Completion; `.failed` → hands off to `MinesweeperDailyReplayLoaderView` | Close/Leave → `MS-DAILY-HUB` (all outcomes) |
| Completed card tap | `.completion(difficulty:mode:.daily)` (#386 re-view) | push → `MS-COMPLETION-REVIEW` | Close → `path?.wrappedValue.removeLast()` → back to `MS-DAILY-HUB` (fixed by #697) |
| Failed card tap | `.replayDailyBoard(difficulty:seed:)` (#841 — unscored free replay, no persistence, no GC submit; see `MS-BOARD-LOAD-FAILED` Tier 3) | `.loading` → modal-full/push on `.loaded`, or Close+Retry block on `.failed` | Close/Leave → `MS-DAILY-HUB` |

**Covering behavior:** none — plain tab-root content.

**State variants** (`MinesweeperTodayMapper.present`,
`MinesweeperTodayMapper.swift:72-90`): `loading` (skeleton grid, one card per
daily difficulty at its real board dims — `MinesweeperTodayMapper.
skeletonCards()`, `:53-70`) / `loaded` / `allDone` / `degraded` (phase-2 fetch
failure — cards forced to unplayed) — **no `exhausted`**, structurally
unreachable (`TodayPresentation.swift:8-10`).

**Glass status:** same as Sudoku — `HubCard` standard material, streak header
plain content-layer text.

---

## SUD-PRACTICE-HUB

> **Re-anchored to the as-built 3.0 shape (2026-09-03, #1021 Phase A/C).** The
> pre-3.0 "Difficulty picker" row below is superseded — replaced by
> 3 `PracticeDifficultyCardView` rows (density-preview thumbnails, design.md
> §3.2). HOME "Practice" card entry is retired (#1020).

**Entry points:** Practice tab root (`AppTab.practice` — no HOME).

**Code:** `SudokuUI/Practice/PracticeHubView.swift`,
`PracticeHubViewModel.swift`,
`SudokuUI/Practice/SudokuPracticeCardsMapper.swift`,
`GameShellUI/PracticeHubShellView.swift`,
`GameShellUI/TabRoots/PracticeDifficultyCardView.swift`.

**Element inventory:**

| Element | Copy (en) | a11y id |
|---|---|---|
| 3 `PracticeDifficultyCardView` rows (filter slot, `PracticeHubView.swift:57-70`, replaces the retired difficulty `Picker`) | title = Easy/Medium/Hard; detail `"~{N} givens"` (`SudokuPracticeCardsMapper.detail`, `SudokuPracticeCardsMapper.swift:61-64`); combined a11y `"{title}, {detail}"` (`PracticeDifficultyCardView.swift:92-94`); selected card shows a trailing checkmark | none; `isSelected` adds `.isSelected` trait |
| Draw/CTA card (`HubCard`, `PracticeHubView.swift:72-142`) | title `"Ready to play"`; hint row (state-dependent, see State variants); button `Label("New Game", systemImage: "play.fill")` | button `sudoku.practiceHub.start`; failure hint `sudoku.practiceHub.failure` |

**Per-interaction outcome:**

| Element → action | Destination | Presentation | Back/Close lands on |
|---|---|---|---|
| Difficulty card tap | `viewModel.selectDifficulty(_:)` — SELECTS only, does not draw (Phase C — the old difficulty `Picker` also reset `loadingState`; that reset behavior is now folded into `selectDifficulty` itself, not a picker-change side effect) | side-effect (same screen) | — |
| "New Game" tap | ONE tap runs `drawPuzzle()` then `playTapped()` in the same `Task` — **not** a separate draw-then-play step; a `.failed` draw leaves the user on the hub (guarded by `.drawn` check) | on success: `.board(puzzleId:)` → modal-full (iOS) / push (macOS) | Close/Leave → `SUD-PRACTICE-HUB` |

**Covering behavior:** none.

**State variants (5-state draw machine, unchanged from pre-3.0 —
`PracticeHubView.swift:144-176`):** `idle` (hint `"{difficulty} · ready"`) /
`drawingQuiet` (<100ms, no indicator) / `drawingShimmer` (>100ms, `.redacted`
placeholder, a11y label `"Loading"`, `.updatesFrequently`) / `drawn` (hint
`"{difficulty} · {puzzleId}"`) / `failed(reason)` (inline caption, button
re-enabled, no navigation — a11y id `sudoku.practiceHub.failure`; anchors
`App/SudokuE2ETests/SudokuE2ETests.swift`'s host-driven E2E coverage). The
difficulty CARDS above are a separate, always-visible selection UI (Phase C)
layered on top of this same 5-state CTA machine.

**Glass status:** content-layer glass retired — both the difficulty cards and
the draw CTA card render on `HubCard` (`theme.surface.primary`, standard
material), replacing the pre-3.0 custom glass surface (design.md §4.2:
content-layer cards don't get the Slider/Toggle glass exception).

Anchors: CTA copy — `PracticeHubView.swift:120-127` (both `idle`/`drawn`
branches render `Label("New Game", …)`).

---

## MS-PRACTICE-HUB

> **Re-anchored to the as-built 3.0 shape (2026-09-03, #1021 Phase A/C).** The
> pre-3.0 "Difficulty picker" row below is superseded — replaced by
> 3 `PracticeDifficultyCardView` rows, mirroring Sudoku. HOME "Practice" card
> entry is retired (#1020).

**Entry points:** Practice tab root (`AppTab.practice` — no HOME).

**Code:** `MinesweeperUI/Practice/MinesweeperPracticeHubView.swift`,
`MinesweeperUI/Practice/MinesweeperPracticeCardsMapper.swift`,
`GameShellUI/PracticeHubShellView.swift`,
`GameShellUI/TabRoots/PracticeDifficultyCardView.swift`.

**Element inventory:**

| Element | Copy (en) | a11y id |
|---|---|---|
| 3 `PracticeDifficultyCardView` rows (filter slot, `MinesweeperPracticeHubView.swift:77-90`, replaces the retired difficulty `Picker`) | title = Beginner/Intermediate/Expert; detail `"{R} × {C} · {M} mines"` (`MinesweeperPracticeCardsMapper.detail`, `MinesweeperPracticeCardsMapper.swift:46-48`); combined a11y `"{title}, {detail}"`; selected card shows a trailing checkmark | none |
| Start card (`HubCard`, `MinesweeperPracticeHubView.swift:92-138`) | title `"Ready to play"`; board-summary caption `"{R} × {C} · {M} mines"` (`boardSummary`, `MinesweeperPracticeHubView.swift:165-167`); button `Label("New Game", systemImage: "play.fill")` | button `minesweeper.practiceHub.start` |

**Per-interaction outcome:**

| Element → action | Destination | Presentation | Back/Close lands on |
|---|---|---|---|
| Difficulty card tap | `difficultyBinding.wrappedValue = level` — SELECTS only; also fires `onDifficultyChanged` for persistence | side-effect (same screen) | — |
| "New Game" tap | synchronous — no draw/shimmer step at all: mints a random seed and appends `.board(difficulty:seed:mode:.practice)` directly, wrapped by `MinesweeperFreshBoardLoaderView` (#910 — see `MS-BOARD-LOAD-FAILED` Tier 4) | `.loading` (brief) → modal-full (iOS) / push (macOS) | Close/Leave → `MS-PRACTICE-HUB` |

**Covering behavior:** none.

**State variants:** single state — no loading/shimmer machinery exists (MS
board generation is synchronous, a real gameplay difference from Sudoku's
async generator, not strong-armed into parity — design.md §3.2). The
difficulty cards above are a separate, always-visible selection UI (Phase C)
with no state of their own.

**Glass status:** content-layer glass retired — both the difficulty cards and
the start CTA card render on `HubCard` (standard material), mirrors Sudoku.

Anchors: CTA copy — `MinesweeperPracticeHubView.swift:125-127`
(renders `Label("New Game", …)`).

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
error caption, `Label("Close", systemImage: "xmark")` button (`.bordered`,
`sudoku.boardLoader.close`, #936) + `Label("Retry", systemImage:
"arrow.clockwise")` button (`.bordered`, `sudoku.boardLoader.retry`, #936).

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

**State variants:** `LoadState` has **four** cases (`BoardLoaderView.swift:66-81`):
`.loading` (`ProgressView`) → `.loaded` (mounts `SUD-BOARD`),
`.completedRedirect(CompletionViewModel, ReminderPrimerCoordinator?)`, or
`.failed(UserFacingError)` (this block).

**AS-BUILT NOTE (2026-07-21, #842; updated 2026-09-01, #1023):** `.completedRedirect`
was undocumented until now. It is a race guard: when the daily open-time
precheck in `load()` finds the store's `SavedGame` already `.completed`
(stale phase-1 view-model data, e.g. a fast tap on a card that was just
finished elsewhere), the loader renders the Completion surface **inline** via
`CompletedRedirectSurface` (`BoardLoaderView.swift:196-208`, wrapping the
shared `CompletionOverlayScaffold`; state set at `:303`) instead of ever
building a playable `GameViewModel`. Rendering is byte-identical to the
`.completion` route's, so it introduces no new visual state to snapshot.
Close on this surface uses the same `exitToHub()` shape (`:215`) as the live
completion overlay — correct behavior that simply never reached the
contract. MS reaches the equivalent outcome through a separate tier instead
(`MinesweeperDailyOpenGuardView`'s `.completed` state — see
`MS-BOARD-LOAD-FAILED` Tier 2), so the two apps are
behaviorally mirrored via different structures, which is itself worth knowing
before "unifying" them.

`MS-BOARD-LOAD-FAILED` (`MinesweeperBoardLoaderView.swift`, copy: `"Couldn't
load saved game."`) is the Tier 1 counterpart — only reachable via
`.resumeBoard`, not fresh `.board`.

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
`MinesweeperUI/MinesweeperDailyOpenGuardView.swift` (tier 2, 266 lines, #842),
`MinesweeperUI/MinesweeperDailyReplayLoaderView.swift` (tier 3, #841),
`MinesweeperUI/MinesweeperFreshBoardLoaderView.swift` (tier 4, #910).

### Tier 1 — `.resumeBoard` (`MinesweeperBoardLoaderView`, unchanged pre-#841 shape)

**Element inventory:** warning icon, `"Couldn't load saved game."`,
classified error caption, `Label("Close", systemImage: "xmark")`
(`.bordered`, `minesweeper.boardLoader.close`, #936) + `Label("Retry",
systemImage: "arrow.clockwise")` (`.bordered`, `minesweeper.boardLoader.retry`,
#936).

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
(`GuardState`/`DailyOpenOutcome`), `:145-205` (`content` switch), `:207-214`
(`exitToHub`), `:216-225` (`check()`), `:244-265` (`resolve` — the #526
adjudication that a fetch failure degrades to `.playable`, never blocks daily
play). **Known accepted
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
| Leave button (destructive) | `"leave.game.leave"` | `game.pause.leave` (#936) |

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
| Streak section (#1023 — `liveSolve` daily win with a resolved `CompletionStreakAdvance` only) | 7-pip week row (`theme.streak.pipOff` → filled) + `"%lld day streak"` caption; plays M3 pip-advance + M4 count slide-replace | none |
| Reminder affordance (Daily only, pre-#287-grant) | `"Remind me when tomorrow's puzzle is ready"` + subcopy | none |
| CTA rows (#1023 — `CompletionContext`, design.md §3.5's 4-row hierarchy) | Daily-more-today: primary `"Next: <difficulty>"` + secondary `"Done"` · Daily-all-done: single `"See you tomorrow"` (the flow's ONE value-toned CTA) · Practice: primary `"Play Again"` + secondary `"Close"` (Close-only when no presenter wired) | the closing button always carries `game.completion.close` (#936), whichever context renders it |

There is no leaderboard slice UI — #698 deleted the dead leaderboard-fetch
state machine (both apps hardcoded `state: .hidden` since v2.6 and it never
rendered). `docs/designs/06-completion.md`'s "Top 3 + Around you + View full
leaderboard" section is **CODE CONTRADICTED** — none of that renders today.

**Per-interaction outcome:**

| Element → action | Destination | Presentation | Back/Close lands on |
|---|---|---|---|
| Reminder affordance tap | `presentPrimer()` | `sheet(detent)` → `REMINDER-PRIMER` | dismiss → same overlay |
| `"Next: <difficulty>"` tap (#1023, Daily-more-today) | `onDailyNext` — clears overlay and presents the next still-open daily difficulty | modal-full (new board instance) | new `SUD-BOARD` instance |
| Play Again tap | clears overlay, `exitToHub()`, then `playAgain(difficulty)` draws a fresh practice puzzle and re-presents | modal-full (new board instance) | new `SUD-BOARD` instance |
| Close / `"Done"` / `"See you tomorrow"` tap | clears overlay, `exitToHub()` | iOS: `dismiss()` (cover collapses) · macOS: pop 1 path entry | HOME/hub that pushed the board (never the solved board — #667 fix) |

**Covering behavior (updated 2026-09-01, #1023):** full-height Liquid-Glass
panel (G6 — design.md §4.4's D-3.3 explicit exception, never a system sheet)
rising over the board; the solved BOARD STAYS VISIBLE behind the glass
(§3.5 — nothing left to peek at, unlike pause), accent glow painted BEHIND
the glass, not on it. Mounted through `BoardModalPresentation.completion` →
`HoistedOverlayHost` (#1038) — this presentation key is also the seam
#1022's G4 control cluster must observe to unmount (§4.3 scene-exclusivity).
Board underneath is still torn down on Close, not merely hidden.

**State variants (updated 2026-09-01, #1023):** `CompletionVariant` —
`liveSolve` (fresh terminal event: M10 panel rise + M1 accent seep + M2 hero
reveal + M3/M4 streak ritual; the `.success` haptic fires from the VM
terminal edge, never from the panel) vs `review` (static presentation, no
ritual, no haptic). CTA layout varies by `CompletionContext` (table above).
Reduce Motion swaps each animation for its §6 fade fallback, not off.

---

## MS-COMPLETION-OVERLAY

**Entry points:** `MS-BOARD` reaching a terminal state (win or loss).

**Code:** `MinesweeperUI/MinesweeperBoardView.swift` `completionSurface`,
`MinesweeperUI/Completion/MinesweeperCompletionView.swift`.

**Element inventory:**

| Element | Copy | a11y id |
|---|---|---|
| Hero (win) | "You won" + elapsed | `game.completion.hero` |
| Hero (loss) | "Boom" (no elapsed shown in the loss hero per `CompletionOutcome`; tinted `theme.status.error`) | `game.completion.hero` |
| Streak section (#1023 — `liveSolve` daily WIN with a resolved `CompletionStreakAdvance` only; never on loss) | 7-pip week row + `"%lld day streak"` caption, mirrors Sudoku | none |
| Reminder affordance (Daily win only, pre-authorization — #814, mirrors Sudoku) | `"Remind me when tomorrow's boards are ready"` + subcopy | none |
| CTA rows (#1023 — `CompletionContext`, same shared scaffold as Sudoku) | win: Daily-more-today / Daily-all-done / Practice rows as in `SUD-COMPLETION-OVERLAY` · loss: primary `"Try Again"` + secondary `"Close"` (Close-only when no presenter wired) | the closing button always carries `game.completion.close` (#936) |

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
`CompletionView.swift:62-68`). Wired daily-only for THIS live overlay by
`MinesweeperUI/MinesweeperBoardView.swift:1110-1121`
(`shouldOfferReminderPrimer(mode:didWin:)` + `makeReminderPrimer()`, which
gates on BOTH the daily mode and an actual win). Do not confuse this with
`MinesweeperAppComposition/LiveRouteFactory.swift:308` — that near-identical
`mode == .daily ? makeDailyReminderPrimer?() : nil` line belongs to the pushed
`.completion` re-view route (`MS-COMPLETION-REVIEW`), where the mode gate alone
is the win gate because a solved-daily re-view is `didWin: true` by definition.

**Per-interaction outcome:**

| Element → action | Destination | Presentation | Back/Close lands on |
|---|---|---|---|
| Reminder affordance tap | `presentPrimer()` | `sheet(detent: [.medium, .large])` → `REMINDER-PRIMER` | dismiss → same overlay |
| Play Again tap | clears overlay VM, `dismiss()`, then `playAgain(difficulty)` with a fresh random seed, mounted via `MinesweeperFreshBoardLoaderView` (#910 — see `MS-BOARD-LOAD-FAILED` Tier 4; still `modal-full`, just with a brief `.loading` frame first, not the direct construction the row previously implied) | modal-full (new board instance) | new `MS-BOARD` instance |
| Close tap | clears overlay VM, `dismiss()` | iOS: cover collapses · macOS: pops the push (same `dismiss()` call both contexts — MS never branches on `path`) | HOME/hub that pushed the board |

**Covering behavior (updated 2026-09-01, #1023):** identical full-height
Liquid-Glass panel as `SUD-COMPLETION-OVERLAY` (same shared scaffold — the
mined/solved board stays visible behind the glass; mounted through
`BoardModalPresentation.completion` → `HoistedOverlayHost`, #1038). Loss
state: `"burst.fill"` icon, `status.failure` outcome kind — loss is still
`liveSolve` (a fresh terminal event: the `.error` haptic fires from the VM
edge) but plays NO ritual and NO streak section (§3.5 / §6.1).

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

**Covering behavior (updated 2026-09-01, #1023):** same `CompletionOverlayScaffold`
shape as the overlay — full-height Liquid-Glass panel (`.ignoresSafeArea()`),
NOT the pre-#1023 opaque warm-paper background — visually indistinguishable
from `SUD-COMPLETION-OVERLAY` even though this is a genuine stack push, not
an in-board overlay (there is no board behind a pushed route to show through,
so the glass sits over the plain page background here). `variant: .review`
— no ritual/panel-rise, no streak section (design.md §3.5). **State
variants:** none; frozen snapshot values passed at construction (no live VM).

**E2E coverage (#935 batch 3):** N12 (`docs/navigation-flows.md`) anchors
`App/SudokuE2ETests/SudokuE2ETests.swift`'s
`test_completionReviewCloseLandsOnDailyHub_N12` — Close pops exactly one path
entry back to `SUD-DAILY-HUB`. Completed-daily state lives in CloudKit
Private DB and can't be produced by real play on the CI simulator, so the
test launches with the DEBUG-only `-uitest-seed-completed-daily` flag
(`UITestSeededCompletedDailyPersistence`, `SudokuAppComposition`), which
wraps the live persistence and reports today's daily trio as already
completed (`fetchCompletedDailyIdsByDay`) with a frozen `loadIfExists`
snapshot for the async `openCompleted` hop.

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

**E2E coverage (#935 batch 3):** N13 (`docs/navigation-flows.md`) anchors
`App/MinesweeperE2ETests/MinesweeperE2ETests.swift`'s
`test_completionReviewCloseLandsOnDailyHub_N13` — Close pops exactly one path
entry back to `MS-DAILY-HUB`. Same CK-can't-seed rationale as Sudoku's N12,
but the seam differs structurally: `MinesweeperDailyHubViewModel.cardTapped`
pushes `.completion` synchronously off `card.isCompleted` alone (no snapshot
fetch, #284), so the DEBUG-only `-uitest-seed-completed-daily` flag only
needs to fake the completed-ids read. `MinesweeperSavedGameStore` had no
protocol seam prior to this batch — `MinesweeperDailyOverlayReading`
(`MinesweeperPersistence`) now narrows exactly the two methods
`MinesweeperDailyHubViewModel`'s phase-2 overlay actually calls
(`fetchFailedDailyIds(for:)` / `fetchCompletedDailyIdsByDay()`), letting
`UITestSeededCompletedDailyOverlayReading` (`MinesweeperAppComposition`)
stand in without widening the concrete store's other consumers (board
save/resume/replay, `MinesweeperDailyOpenGuardView`'s today-only re-check).

**Covering behavior / state variants:** same scaffold shape as
`SUD-COMPLETION-REVIEW`; no Play Again; no mistake row.

---

## PROGRESS

**Added 2026-07-21 (#773/#844) as STATS, closes F-HOME-1. Superseded
2026-09 (#1021 Phases D/E2): STATS is retired for real — deleted, not
merely unwired — and replaced by this contract. The screen it names is now
`AppTab.progress`'s permanent tab root (design.md §3.3), not a pushed route
off a HOME card: HOME itself was retired by #1020's 3-tab shell, so there is
no HOME card to entry-point from any more.**

**Entry points:** the `Progress` tab itself (`AppTab.progress`, one of the
three permanent sidebarAdaptable tabs alongside `Today`/`Practice` — #1020).
No other entry point exists (not reachable from Settings, Daily, or
Practice) — same non-reachability posture the retired STATS contract had,
just off a tab instead of a HOME card.

**Code:**
- `GameAppKit/Sources/GameAppKit/ProgressScreen.swift:27` — the shared
  screen, `public struct ProgressScreen<Route: Hashable & Sendable>: View`,
  composed from a `ProgressModel` value + the per-app `GameRootViewModel`.
- `GameAppKit/Sources/GameAppKit/GameCenterEntryRow.swift:23` — the shared
  `Achievements`/`Leaderboards` row, with `.achievements(rootViewModel:)`
  (line 87) and `.leaderboards(rootViewModel:)` (line 98) factories.
- `GameShellKit/Sources/GameShellUI/TabRoots/ProgressModel.swift:9` — the
  pure `ProgressModel` value (`bests`/`history`/`month`/`monthTitle`/`isLoading`).
- `GameShellKit/Sources/GameShellUI/TabRoots/PersonalBestRow.swift:7,23` —
  `PersonalBestModel` + the row view (Phase A scaffold, first consumed here
  in Phase D).
- `GameShellKit/Sources/GameShellUI/TabRoots/StreakCalendarView.swift:8` +
  `StreakHistory.swift:19,91` — the month calendar view + its `DayKey`/
  `StreakHistory` backing values (Phase A scaffold).
- Per-app data + host, Sudoku: `SudokuUI/Progress/ProgressViewModel.swift:38`
  (`bootstrap()` line 74, the daily+practice merge in `bestModel(difficulty:daily:practice:)`
  line 142) and `ProgressHostView.swift:15`; wired at
  `SudokuAppComposition/Live+TabRoots.swift:81` (`.progress` case).
- Per-app data + host, Minesweeper: `MinesweeperUI/Progress/MinesweeperProgressViewModel.swift:33`
  (`bootstrap()` line 71, the merge in `bestModel(difficulty:daily:practice:)`
  line 140) and `MinesweeperProgressHostView.swift:17`; wired at
  `MinesweeperAppComposition/Live+TabRoots.swift:88` (`.progress` case).

**Element inventory:**

| Element | Copy | a11y id |
|---|---|---|
| "Personal bests" section header + 3 `PersonalBestRow`s (Easy/Medium/Hard, or MS Beginner/Intermediate/Expert) | difficulty name + `DifficultyPips`; hero best time (`m:ss`, `.title2.monospacedDigit()`, or `—` — `PersonalBestRow.swift:50-52`) is the LARGEST element on the row, matching design.md §3.3's "best time as the hero"; footnote below the name (`"%lld solved · avg %@"` Sudoku / `"%lld cleared · avg %@"` MS, avg omitted when nil). Best/count/average MERGE both Daily and Practice records per difficulty (#1021 Phase E2 CR — a "personal best" must not silently drop daily records): best = the smaller of the two modes' times, count/average = the two modes' sums. | none (each row is one combined a11y element via `PersonalBestRow.accessibilityLabel(title:bestTimeText:footnote:)`, e.g. "Easy, best 3:12, 14 solved · avg 4:02") |
| Month streak calendar (current month, `StreakCalendarView`) | month/year header + "Current N · Best N" summary; a completed day renders a filled circle with a checkmark GLYPH (`StreakCalendarView.swift:76`) — color is not the only channel; today gets an accent ring | none on the grid itself; each day cell is its own combined a11y element via `StreakCalendarView.dayAccessibilityLabel(day:isCompleted:isToday:)` (`StreakCalendarView.swift:99`), e.g. "21, completed, today" |
| `Achievements` row | `Label` + leading `trophy` icon + trailing `arrow.up.forward` (`GameCenterEntryRow.swift:52,61`) — HIG-mandated term, never "Trophies"/"Awards"/"Medals" | `game.progress.achievements` (`GameCenterEntryRow.swift:91`, kept from #1020's retired `AchievementsRow`) |
| `Leaderboards` row | same shape, leading `list.number` icon | `game.progress.leaderboards` (`GameCenterEntryRow.swift:102`) |

**Explicit non-goal (design.md §3.3):** no in-app achievement gallery / card
list of any kind — Apple's own achievement-card format (collectible-card
images, per-achievement progress) is NOT reproduced here; the two rows exist
solely to hand off to Apple's native dashboard.

**Per-interaction outcome:**

| Element → action | Destination | Presentation | Back/Close lands on |
|---|---|---|---|
| `Achievements` tap, authenticated | native Game Center dashboard, `.achievements` state (`GameCenterDashboard.presentAchievements()`, `GameCenterDashboard.swift:62,64` → `GKAccessPoint.shared.trigger(state: .achievements)`) | external, fully modal Apple UI (same covering behavior as `GC-DASHBOARD`) | dismiss → `Progress` tab, unchanged |
| `Leaderboards` tap, authenticated | native Game Center dashboard, `.leaderboards` state (`GameCenterDashboard.present()`, same file line 44/49) — see `GC-DASHBOARD` for the full leaderboards-dashboard contract | same as above | same as above |
| Either row tap, signed out | the shared `GC-SIGNED-OUT-ALERT` (routed through `GameRootViewModel.presentGameCenterOrAlert`, `GameRootViewModel.swift:372` — the same #685 auth gate `GC-DASHBOARD`'s other entry points use) | system `.alert` | OK → dismiss, no route change |

Neither row is a navigation push — a tap is a side effect (present Apple's
UI or raise the alert), never a route change of its own; the tab's own
`path` stays empty either way (mirrors #1020 C-35's retired HOME
leaderboard card).

**Covering behavior:** none of its own — plain tab-root content, no
sheet/overlay; the two GC rows' presentations are covered above.

**State variants:**
- **Loading** — `ProgressModel.isLoading == true` (seeded on VM init before
  `bootstrap()` lands): both the bests section and the calendar section
  render `.redacted(reason: .placeholder)` (`ProgressScreen.swift:72,92`) —
  the screen never blocks on the fetch.
- **Loaded** — both `fetchPersonalRecord(mode:difficulty:)` (×6: both modes
  × 3 difficulties) and `fetchCompletedDailyIdsByDay()` have landed; a
  per-(mode, difficulty) fetch failure degrades JUST that pair to
  `PersonalRecord.empty(...)` before the merge (the other mode's real data
  for that difficulty still counts), funneled through `errorReporter` —
  never a blocking error state, mirroring the Daily hubs' phase-2
  graceful-degrade posture.
- **History-unavailable** — `fetchCompletedDailyIdsByDay()` failed outright:
  `ProgressModel.history == nil`. The calendar still renders (an empty
  `StreakHistory` — zero days marked, `ProgressScreen.swift`'s
  `emptyHistory(today:)` fallback) plus a `"Streak history unavailable"`
  footnote (`ProgressScreen.swift:87`) — never a blank calendar with no
  explanation.

No monetization surface (explicit scope exclusion carried over from the
retired STATS contract's `docs/v2/stats-screen-proposal.md` §7).

---

## SETTINGS

**Entry points:** per-tab toolbar gear (`TabRootChrome`, a11y `game.tab.settings`,
iPhone/iPad/macOS) + iPad-regular/macOS sidebar fixed row (`RootShellView.tabViewSidebarFooter`,
a11y `game.sidebar.settings`, #1041).

**Code:** `SudokuUI/Settings/SettingsView.swift`,
`MinesweeperUI/SettingsView.swift`, `SettingsKit/Sources/SettingsUI/Settings/*`.

**Element inventory (row order):** Purchases section (host-injected IAP
rows — "Remove Ads" `settings.iap.removeAds` / `AdsRemovedRow` when already
purchased, "Restore Purchases" `settings.iap.restore` — id added #950), GC
status row (`settings.gameCenter`), reminders section (see `REMINDER-*` ids
under it), Sound section (mute/music-volume/sfx-volume/music-enabled/haptics
toggles, ids `audio.settings.*`), About section (Version row +, Sudoku-only,
Generator row), Notices section (acknowledgements deep-link, copyright),
Storage section "Clear cache" button (id `settings.storage.clearCache`,
#935 batch 5 — see `CLEAR-CACHE-DIALOG`). #956: a stable, non-localized,
zero-size E2E precondition anchor `settings.storage.cacheReady` sits on a
`.background` marker sibling to that button — present only once
`SettingsViewModel.isCacheStateReady` is `true` (its async `resumeCandidate`
load has settled) — same "sibling marker, not a container id" pattern as
`sudoku.dailyHub.root`. A bottom-center toast overlay
(`ToastController`/`ToastView`, ids `monetization.toast.success` /
`monetization.toast.failure` / `monetization.toast.info` — the `.info` id
added #950 for the "nothing to restore" outcome) floats above the whole
screen for purchase/restore/clear-cache outcomes — not a Form row, mounted
once at `GameRoot`.

**Per-interaction outcome:**

| Element → action | Destination | Presentation | Back/Close lands on |
|---|---|---|---|
| GC status row tap (`settings.gameCenter`) | `resolvedOnGameCenter()` → `presentGameCenter` closure → `GameRootViewModel.presentGameCenterOrAlert` (same guard the Home leaderboard card uses) | authenticated: external → `GC-DASHBOARD`. Signed out: `.alert` → `GC-SIGNED-OUT-ALERT` | authenticated: dismiss → `SETTINGS` (side-effect). Signed out: OK → `SETTINGS` |
| Reminders "Enable"/"Turn On" row tap | `model.enable()` | `sheet(detent: .medium)` → `REMINDER-PRIMER` | dismiss → `SETTINGS` |
| Reminders denied-status row tap | `model.showDeniedExplainer()` | `sheet(detent: .medium)` → `REMINDER-DENIED` | dismiss → `SETTINGS` |
| Reminders "Turn off reminders" tap | `model.disable()` | side-effect | `SETTINGS` (status row switches back to enable row) |
| "Remove Ads" tap (`settings.iap.removeAds`) | `controller.purchaseRemoveAds()` → StoreKit 2 payment sheet | cancel: silent no-op. fail/pending: failure-style toast (`monetization.toast.failure`). success: entitlement flips, row swaps to `AdsRemovedRow` | stays on `SETTINGS` throughout — no navigation, ever (#935 batch 5 N22) |
| "Restore Purchases" tap (`settings.iap.restore`) | `controller.restorePurchases()` → StoreKit 2 receipt sync | entitlement actually restored: success toast (`monetization.toast.success`, "Purchases restored"), entitlement flips. Nothing entitled: info-style toast (`monetization.toast.info`, "No purchases to restore") — **#950 fix**, previously showed the false success claim unconditionally (N23). userCancelled: silent, no toast. Other failure: failure toast (`monetization.toast.failure`) | stays on `SETTINGS` throughout — no navigation, ever |
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

**E2E coverage (N22, #935 batch 5):** `-uitest-iap-script` (DEBUG-only,
`UITestLaunchArg.iapScript`) swaps in `UITestScriptedIAPClient`
(`GameAppKit/Sources/GameAppKit/UITestFakeSeams.swift`, resolved via
`resolveIAPClient` in `MakeGameApp+UITestOverrides.swift`) — a fake that
returns `.userCancelled`, then `.failed(reason:)`, then `.pending` on
successive `purchase()` calls, so ONE test walks all three
`purchaseRemoveAds()` branches from the "Remove Ads" row without the real
StoreKit 2 payment sheet. `App/SudokuE2ETests/SudokuE2ETests+MonetizationFlows.swift`
/ `App/MinesweeperE2ETests/MinesweeperE2ETests.swift`
`test_iapPurchaseCancelFailPendingStayInPlace_N22`. Along the way, fixed a
pre-existing tap-target-shrink bug (`RemoveAdsRow`/`RestorePurchasesRow`
lacked `.contentShape(Rectangle())` — `.buttonStyle(.plain)` + an internal
`Spacer()` left the row's middle untappable; the swiftui-interaction-footguns
"tap target shrink" pattern).

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
CTA (primary), decline CTA "Not now" (repeatable), fineprint. The sheet's own
root carries `reminders.primer.sheet` (added #940 as a locale-independent
regression anchor).

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

**AS-BUILT NOTE (2026-07-23, #940):** for the `SETTINGS`-initiated case, both
this sheet and `REMINDER-DENIED` used to be attached as `.sheet` modifiers on
`ReminderSettingsSection`'s own `Section` — a presentation host nested inside
the Settings `Form`'s List row-group, whose content (`switch model.status`)
is dynamic. The tap-time async `getNotificationSettings` status write swapped
that Section's row content mid-presentation; List's row diffing duplicated
the presentation host, UIKit rejected the second `present`, and the primer
self-dismissed ~1–1.5s after looking fully settled (reproduced 4/4 — a
recurrence of #909's symptom via a different mechanism than #909's
already-fixed model-caching bug). Both sheets now live on `SettingsScreen`'s
root (`SettingsKit/Sources/SettingsUI/Settings/SettingsScreen.swift:227-261`)
— a stable host outside any List row — via `Binding(get:set:)` reading the
same injected `ReminderSettingsModel`. `ReminderSettingsSection` itself no
longer owns either `.sheet`. The Completion-initiated case
(`SUD-COMPLETION-OVERLAY`/`MS-COMPLETION-OVERLAY`) was never affected — its
host is a plain overlay view, not a List row.

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
| "Open Settings" (iOS) | opens `UIApplication.openNotificationSettingsURLString`-style system URL | external | user returns manually; on return the status row re-polls — see AS-BUILT NOTE below |
| Dismiss | `model.dismissDeniedExplainer()` | dismiss sheet | `SETTINGS` |

**AS-BUILT NOTE (2026-07-21, #929):** returning from that system deep-link
**backgrounds** the app rather than dismissing anything, so this screen — and
the `SETTINGS` row behind it — never leave the view hierarchy and `.task`
never re-fires. Until #929 there was no foreground hook at all, so a user who
granted permission in Settings.app came back to a row still reading `denied`
until they left `SETTINGS` and re-entered. `ReminderSettingsSection` now
carries a `scenePhase` re-poll (`SettingsUI/Reminders/ReminderSettingsSection.swift:95,145`)
that re-runs `model.onAppear()` on `.active`, so the status is re-read on
every foreground return. Repeat calls are safe: the #817 one-shot migration
inside `onAppear()` is guarded by `getIsScheduled() == nil` plus a post-await
TOCTOU re-check.

**Covering behavior:** `.sheet(detent: .medium)`, drag indicator hidden.
**State variants:** platform-conditional body (iOS button vs. macOS text),
otherwise single state. macOS has no `openNotificationSettingsURLString`, so
the deep-link/return cycle above is iOS-only; the `scenePhase` hook is
harmless there.

---

## CLEAR-CACHE-DIALOG

**Entry points:** `SETTINGS` "Clear cache" button (a11y id
`settings.storage.clearCache`, #935 batch 5 — the row sits in the LAST
section of `SETTINGS`'s long `Form`, off-screen/unmaterialized until
scrolled into view).

**Code:** `SettingsKit/Sources/SettingsUI/Settings/SettingsAboutStorage.swift`
`SettingsStorageSection`.

**Element inventory:** title `"Reset session cache"` (`titleVisibility:
.visible`), message `"Generated puzzles will be re-derived next play. Saved
games are not affected."`, "Clear cache" (destructive, a11y id
`settings.storage.clearCache.confirm`, #935 batch 5), "Cancel" (`role:
.cancel`, a11y id `settings.storage.clearCache.cancel` — present in the
SwiftUI source but, on this environment's presentation below, the system
renders no separate accessibility element for it; Cancel is reachable only
via the backdrop-dismiss tap, see Covering behavior). #956: the entry-point
row (not the dialog itself) additionally carries a zero-size E2E
precondition anchor `settings.storage.cacheReady` — see `SETTINGS`'s
element inventory above.

**Per-interaction outcome:**

| Element → action | Destination | Presentation | Back/Close lands on |
|---|---|---|---|
| "Clear cache" confirm | `clearCache()` async → success toast `"Cache cleared"` (id `monetization.toast.success`) or failure toast `"Couldn't clear cache"` (id `monetization.toast.failure`) + error-funnel report | dismiss dialog; toast overlay (`ToastController`, floats above `SETTINGS`) | `SETTINGS` |
| "Cancel" / backdrop tap | no-op | dismiss dialog | `SETTINGS` |

**Covering behavior:** system `.confirmationDialog` — on iPhone-class devices
this is verified (idb `ui_describe_all`, #935 batch 5) to present as a
CENTERED POPOVER with a full-screen `PopoverDismissRegion` backdrop, NOT a
bottom action sheet — a tap anywhere outside the dialog's centered box
dismisses it (equivalent to Cancel); the `role: .cancel` button itself
renders no discrete accessibility element in this presentation, but the
backdrop DOES: it is its own discrete accessibility element (role Group,
AXLabel "dismiss popup", `AXUniqueId "PopoverDismissRegion"`) — the E2E test
taps that element directly (#956) rather than a fixed normalized-offset
coordinate, so the tap resolves against the CURRENT layout on every run.
Floats above `SETTINGS`, which stays visible but non-interactive until
dismissed.

**State variants:** none.

**E2E coverage (N19, #935 batch 5):** `-uitest-clear-cache-fail`
(DEBUG-only, `UITestLaunchArg.clearCacheFail`) swaps in
`UITestClearCacheFailPersistence` (`GameAppKit/Sources/GameAppKit/UITestFakeSeams.swift`,
resolved via `resolvePersistence` in `MakeGameApp+UITestOverrides.swift`) —
reports a synthetic in-progress saved game (so the row/dialog are reachable)
and throws from `deleteAbandoned`, so the failure-toast branch fires
deterministically. `App/SudokuE2ETests/SudokuE2ETests+MonetizationFlows.swift`
/ `App/MinesweeperE2ETests/MinesweeperE2ETests.swift`
`test_clearCacheCancelAndFailureToast_N19`.

**#956 flake note:** intermittently failed (twice during #954's acceptance
pass). The issue's original suspected cause — the Cancel half's fixed
backdrop-tap coordinate — turned out to be WRONG: repeat-running under
contention reproduced the flake at a consistent ~15–50% rate (worse under
heavier host load, but present even in a clean single-suite run with no
deliberate contention), always at the SAME assertion, with the
Cancel/backdrop-dismiss half always succeeding. Root cause: a genuine
precondition race in `SettingsViewModel.clearCache()`
(`Packages/GameAppKit/Sources/GameAppKit/SettingsViewModel.swift`) —
`deleteAbandoned` only runs `if let candidate = resumeCandidate`, and
`resumeCandidate` is populated by `bootstrap()`'s async
`persistence.latestInProgress()` fetch; if that fetch hadn't resolved by
the time the test tapped Confirm, `clearCache()` silently fell through to
the unconditional SUCCESS toast branch instead of the failure one, so the
awaited failure toast never appeared. Closed by adding
`SettingsViewModel.isCacheStateReady` (flips `true` once `bootstrap()`
settles either way) and the `settings.storage.cacheReady` anchor above —
the test now waits for that anchor before ever tapping the row, so it can't
race the async load.
Also hardened, per issue direction (a) — genuine improvements to the
Cancel/backdrop half, confirmed correct by repeat-running (every pre-fix
failure was at the toast assertion, never at these waits): wait for the
confirm button to be `isHittable` (not merely `exists`) before every tap,
and re-query a fresh handle after reopening rather than reusing the
pre-Cancel one, which a still-tearing-down duplicate from the first
presentation could satisfy without being the live, on-screen button; and
Cancel now taps the popover's own `PopoverDismissRegion` backdrop element
instead of a fixed normalized-offset coordinate.

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

**E2E coverage (N14, #935 batch 4):** `-uitest-gc-signed-out` (DEBUG-only,
`UITestLaunchArg.gcSignedOut`) swaps in `UITestSignedOutGameCenterClient`
(`GameAppKit/Sources/GameAppKit/UITestFakeSeams.swift`, resolved via
`resolveGameCenterClient` in `MakeGameApp+UITestOverrides.swift`) so
`GameRootViewModel.bootstrap()` lands on `authState = .unauthenticated`
deterministically — CI sim Game Center is signed out in practice, but the
live GameKit handshake is nondeterministic (timeouts / system prompts), so a
forced seam replaces relying on real sim state. Exercised via the `SETTINGS`
GC row entry point: `App/SudokuE2ETests/SudokuE2ETests.swift`
`test_gcSignedOutAlertDismissesInPlace_N14`,
`App/MinesweeperE2ETests/MinesweeperE2ETests.swift`
`test_gcSignedOutAlertDismissesInPlace_N14`.

---

## ATT-PRIMER

**Entry points (3.0, C-33 BREAK — #1020):** first ad-relevant moment — the
**Today tab's** banner slot (`GameAppKit/TodayTabHost.swift`, `onAdContext`)
calls `attPrimer.maybePresentOnAdContext()` (i.e., the **first Today banner
load**, not app launch). Pre-3.0 this was `GameHomeView`'s banner slot; HOME
is retired. One-offer-per-launch latch (`hasOffered`) unchanged. **Does not
block Today interaction** — the tab is already rendered and tappable when
this sheet appears (CODE CONTRADICTED vs. a "boot-time gate" assumption).

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

**E2E coverage (N15, #935 batch 5):** `-uitest-fake-ad-gate-repoll` (opens
the banner ad-gate — this sheet's only trigger — after a real
background→foreground cycle, #931) combined with `-uitest-att-primer`
(DEBUG-only, `UITestLaunchArg.attPrimer`) forces `isNotDetermined` → `true`
/ `requestSystemPrompt` → no-op (`resolveATTIsNotDetermined` /
`resolveATTRequestSystemPrompt` in `MakeGameApp+UITestOverrides.swift`, fed
into `makeATTPrimerCoordinator()` in `MakeGameApp+Helpers.swift`), so the
sheet presents deterministically without depending on the simulator's real
(once-per-install) ATT status. `App/SudokuE2ETests/SudokuE2ETests+MonetizationFlows.swift`
/ `App/MinesweeperE2ETests/MinesweeperE2ETests.swift`
`test_attPrimerDeclineDismissesAndLatches_N15` — declines via `att.primer.notNow`,
asserts dismissal + Home unaffected, then a SECOND background→foreground
cycle to confirm the `hasOffered` latch holds (no re-offer).

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
