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
| Banner slot | ad or placeholder | — |

¹ `HomeScreen.cardAccessibilityIdentifier` defaults to `{ _ in nil }` and
neither app's `GameHomeView` callsite overrides it post-#557 — MS's older
"`MinesweeperHomeView.<mode>Card`" comment in `HomeScreen.swift` is stale for
the current shared path (CODE CONTRADICTED vs. that comment).

**Per-interaction outcome:**

| Element → action | Destination | Presentation | Back/Close lands on |
|---|---|---|---|
| Resume pill tap | `rootViewModel.resumeTapped()` → `path.append(candidate.route)` | push (→ `GameBoardRedirect` → `modal-full` on iOS; direct push on macOS) | Board's own Close/Leave (see `SUD-BOARD`/`MS-BOARD`) |
| Daily card tap | `.daily` | push → `SUD-DAILY-HUB`/`MS-DAILY-HUB` | pop → HOME |
| Practice card tap | `.practice` | push → `SUD-PRACTICE-HUB`/`MS-PRACTICE-HUB` | pop → HOME |
| Leaderboard card tap, GC authenticated | `GameCenterDashboard.present(nil)` | external (Apple GC UI) | dismiss → HOME (side-effect, no route change) |
| Leaderboard card tap, GC signed out | none | `.alert` → `GC-SIGNED-OUT-ALERT` | OK → HOME |
| Settings card tap | `.settings` | push → `SETTINGS` | pop → HOME |
| Sidebar row (macOS/iPad regular) | same targets as cards, via `RootShellView` sidebar | push | same |

**Covering behavior:** HOME is root content; nothing covers it except the
universal `GC-SIGNED-OUT-ALERT` (floats) and `ATT-PRIMER` sheet (partial
detent), both applied by `makeGameApp`'s `universalRootModifiers`
(`GameAppKit/MakeGameApp+Modifiers.swift`). Underlying HOME stays fully
interactive under an `.alert`; a `.sheet` blocks interaction with HOME until
dismissed.

**State variants:** single state — HOME has no loading/empty/failed of its
own (`docs/designs/02-home.md` §a, still accurate). Degraded CK/GC: resume
pill silently absent (nil `resumeCandidate`); leaderboard card still taps
through to the alert path.

---

## SUD-DAILY-HUB

**Entry points:** HOME "Daily" card; reminder-tap deep link
(`reminderTapRoute` → `.daily`, Sudoku only — see `navigation-flows.md`
negative flows for the MS gap).

**Code:** `SudokuUI/Daily/DailyHubView.swift`, `DailyHubViewModel.swift`,
`GameShellUI/DailyHubShellView.swift`.

**Element inventory:** 3 `DailyPuzzleCard`s (Easy/Medium/Hard), each combined
a11y element `"{difficulty}"` + completed checkmark or chevron.

**Per-interaction outcome:**

| Element → action | Destination | Presentation | Back/Close lands on |
|---|---|---|---|
| Un-completed card tap | `.board(puzzleId:)` | `GameBoardRedirect` → `modal-full` (iOS) / push (macOS) | Close/Leave → `SUD-DAILY-HUB` (modal dismiss or 1-entry pop) |
| Completed card tap | async `openCompleted` → `.completion(puzzleId:elapsedSeconds:mistakeCount:)` | push → `SUD-COMPLETION-REVIEW` | Close pops → `SUD-DAILY-HUB` |
| Completed card tap, snapshot load fails | falls back to `.board(puzzleId:)` (funneled error) | modal-full/push | as above |

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
(never blocks phase-1 render).

---

## MS-DAILY-HUB

**Entry points:** HOME "Daily" card. **No reminder deep-link** — MS's
`GameConfig.reminderTapRoute` is `nil` (CODE CONTRADICTED vs. the mirror
assumption; see `navigation-flows.md` negative flows).

**Code:** `MinesweeperUI/Daily/MinesweeperDailyHubView.swift`,
`MinesweeperDailyHubViewModel.swift`.

**Element inventory:** 3 `MinesweeperDailyCardView`s, each combined a11y
element; trailing indicator is checkmark (completed) / `"Failed"` badge
(mine hit) / chevron (unplayed).

**Per-interaction outcome:**

| Element → action | Destination | Presentation | Back/Close lands on |
|---|---|---|---|
| Unplayed card tap | `.board(difficulty:seed:mode:.daily)` | modal-full (iOS) / push (macOS) | Close/Leave → `MS-DAILY-HUB` |
| Completed card tap | `.completion(difficulty:mode:.daily)` (#386 re-view) | push → `MS-COMPLETION-REVIEW` | Close → `Self.popToNewGame` → `path.removeAll()` → HOME (not back to `MS-DAILY-HUB`) |
| Failed card tap | `.replayDailyBoard(difficulty:seed:)` — unscored free replay, no persistence, no GC submit | modal-full/push | Close/Leave → `MS-DAILY-HUB` |

**Covering behavior:** none. MS has **no `.empty`/`.exhausted` state** —
`dailyTrio(date:)` is synchronous and non-throwing (unlike Sudoku's
generator, which can exhaust).

**State variants:** `idle`/`loading` → `ProgressView`; `loaded` → 3-card grid.
No `.failed`/`.empty` case exists on `MinesweeperDailyHubState`. CK-degraded:
phase-2 completed/failed-id fetch errors silently → cards render unplayed.

---

## SUD-PRACTICE-HUB

**Entry points:** HOME "Practice" card.

**Code:** `SudokuUI/Practice/PracticeHubView.swift`, `PracticeHubViewModel.swift`.

**Element inventory:**

| Element | Copy | a11y id |
|---|---|---|
| Difficulty segmented picker | Easy / Medium / Hard | none |
| "Draw new puzzle" button | `Label("Draw new puzzle", systemImage: "play.fill")` | none |
| Hint row (state-dependent) | `"{difficulty} · ready"` / redacted shimmer / `"{difficulty} · {puzzleId}"` / failure `reason` | none |

**Per-interaction outcome:**

| Element → action | Destination | Presentation | Back/Close lands on |
|---|---|---|---|
| Difficulty picker change | `selectDifficulty(_:)` — resets `loadingState` to `.idle` | side-effect (same screen) | — |
| "Draw new puzzle" tap | ONE tap runs `drawPuzzle()` then `playTapped()` in the same `Task` — **not** a separate draw-then-play step; a `.failed` draw leaves the user on the hub (guarded by `.drawn` check) | on success: `.board(puzzleId:)` → modal-full (iOS) / push (macOS) | Close/Leave → `SUD-PRACTICE-HUB` |

**Covering behavior:** none.

**State variants:** `idle` (picker only) / `drawingQuiet` (<100ms, no
indicator) / `drawingShimmer` (>100ms, `.redacted` placeholder) / `drawn` /
`failed(reason)` (inline caption, button re-enabled, no navigation).

---

## MS-PRACTICE-HUB

**Entry points:** HOME "Practice" card.

**Code:** `MinesweeperUI/Practice/MinesweeperPracticeHubView.swift`.

**Element inventory:**

| Element | Copy | a11y id |
|---|---|---|
| Difficulty segmented picker | Beginner / Intermediate / Expert | none |
| "Start" button | `Label("Start", systemImage: "play.fill")` + board-summary caption `"{rows} × {cols} · {mines} mines"` | `minesweeper.practiceHub.start` |

**Per-interaction outcome:**

| Element → action | Destination | Presentation | Back/Close lands on |
|---|---|---|---|
| "Start" tap | synchronous — no draw/shimmer step at all (CODE CONTRADICTED vs. a Sudoku-mirrored assumption): mints a random seed and appends `.board(difficulty:seed:mode:.practice)` directly | modal-full (iOS) / push (macOS) | Close/Leave → `MS-PRACTICE-HUB` |

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
| Pause toggle tap | `viewModel.pause()` | `overlay` → `PAUSE-OVERLAY` | see `PAUSE-OVERLAY` |
| Digit / cell taps | in-place board mutation | — | — |
| Solve (session → `.completed`) | `makeCompletionViewModel()` | `overlay` → `SUD-COMPLETION-OVERLAY` | see that contract |

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
| Pause toggle tap | `viewModel.pause()` | `overlay` → `PAUSE-OVERLAY` | see `PAUSE-OVERLAY` |
| Cell reveal/flag | in-place mutation | — | — |
| Terminal (win or loss) | `makeCompletionViewModel()` | `overlay` → `MS-COMPLETION-OVERLAY` | see that contract |

**Covering behavior:** same full-screen-before-overlay pattern as Sudoku
(#388 fix, shared root cause). Banner suppressed while `isTerminal` or
`isPaused`.

**State variants:** N/A (see `MS-BOARD-LOAD-FAILED` for the loader's states).

---

## SUD-BOARD-LOAD-FAILED

**Entry points:** any `.board(puzzleId:)` route, wrapped by
`BoardLoaderView` before `SUD-BOARD` mounts.

**Code:** `SudokuUI/Board/BoardLoaderView.swift`.

**Element inventory:** warning icon, `"Couldn't load puzzle."`, classified
error caption, `Label("Retry", systemImage: "arrow.clockwise")` button
(`.bordered`).

**Per-interaction outcome:** Retry tap → re-runs `load()` in place (no
navigation change); success swaps to `SUD-BOARD`, repeat failure stays on
this block.

**Covering behavior:** replaces the loader's content entirely (not an
overlay) — this is the state machine's `.failed` branch, not a covering
surface.

**State variants:** `.loading` (`ProgressView`) → `.loaded` (mounts
`SUD-BOARD`) or `.failed(UserFacingError)` (this block). Same shape for
`MS-BOARD-LOAD-FAILED` (`MinesweeperBoardLoaderView.swift`, copy: `"Couldn't
load saved game."` — only reachable via `.resumeBoard`, not fresh `.board`).

---

## MS-BOARD-LOAD-FAILED

**Entry points:** `.resumeBoard(recordName:mode:)` only (HOME resume pill).
Fresh `.board` / `.replayDailyBoard` mount `MS-BOARD` directly with no async
loader — MS's `LiveRouteFactory` builds `MinesweeperBoardView` inline for
those cases (no persistence fetch needed).

**Code:** `MinesweeperUI/MinesweeperBoardLoaderView.swift`.

**Element inventory / outcome / covering:** identical shape to
`SUD-BOARD-LOAD-FAILED` — see that entry. Copy: `"Couldn't load saved
game."`; a missing record (cleared elsewhere) is an **honest failure**
(`.unknown`), never a silent fresh board.

---

## PAUSE-OVERLAY

**Entry points:** pause toggle tap on `SUD-BOARD` or `MS-BOARD`.

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
| Mask tap (anywhere outside the card) | `onResume()` | side-effect | dismiss overlay → same board, `.playing` |
| Resume button tap | `onResume()` → `viewModel.resume()` | side-effect | same board, `.playing` |
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

Leaderboard slice UI is **NOT rendered** — `state: .hidden` is passed to the
shared `CompletionScreen`; the VM's leaderboard-fetch machinery exists but is
dormant (open question #468). `docs/designs/06-completion.md`'s "Top 3 +
Around you + View full leaderboard" section is **CODE CONTRADICTED** — none
of that renders today.

**Per-interaction outcome:**

| Element → action | Destination | Presentation | Back/Close lands on |
|---|---|---|---|
| Reminder affordance tap | `presentPrimer()` | `sheet(detent)` → `REMINDER-PRIMER` | dismiss → same overlay |
| Play Again tap | clears overlay, `exitToHub()`, then `playAgain(difficulty)` draws a fresh practice puzzle and re-presents | modal-full (new board instance) | new `SUD-BOARD` instance |
| Close tap | clears overlay, `exitToHub()` | iOS: `dismiss()` (cover collapses) · macOS: pop 1 path entry | HOME/hub that pushed the board (never the solved board — #667 fix) |

**Covering behavior:** in-board `.overlay` — background `.ignoresSafeArea()`,
card + CTAs stay within the safe area (so the hero icon clears the Dynamic
Island, #518). Board underneath is torn down on Close, not merely hidden.

**State variants:** single visible state (no loading/failed rendering since
the leaderboard zone is hidden); the dormant VM still has
loading/authenticated/unauthenticated/fetchFailed internal states with no UI
surface.

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
| Play Again (practice only, iOS only) | "Play Again" | none |
| Close | "Close" | none |

Same "leaderboard zone hidden" caveat as Sudoku (`state: .hidden`).

**Per-interaction outcome:**

| Element → action | Destination | Presentation | Back/Close lands on |
|---|---|---|---|
| Play Again tap | clears overlay VM, `dismiss()`, then `playAgain(difficulty)` with a fresh random seed | modal-full (new board instance) | new `MS-BOARD` instance |
| Close tap | clears overlay VM, `dismiss()` | iOS: cover collapses · macOS: pops the push (same `dismiss()` call both contexts — MS never branches on `path`) | HOME/hub that pushed the board |

**Covering behavior:** identical ZStack background/content split as Sudoku
(#518). Loss state: `"burst.fill"` icon, `status.failure` outcome kind.

**State variants:** win / loss (`didWin`); no mistake-count row (MS has no
mistakes concept, `mistakeCount: nil`).

---

## SUD-COMPLETION-REVIEW

**Entry points:** `SUD-DAILY-HUB` completed-card tap only (#379). **Never**
reachable from a live board — the live solve uses `SUD-COMPLETION-OVERLAY`,
not this pushed route.

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

**Entry points:** `MS-DAILY-HUB` completed-card tap only (#386). Same
non-reachability-from-live-board note as Sudoku.

**Code:** `MinesweeperAppComposition/LiveRouteFactory.swift` `.completion` case.

**Element inventory:** `MinesweeperCompletionView` seeded `didWin: true`,
`elapsedSeconds: 0`, **`showsElapsedTime: false`** — the hero omits the time
row entirely (MS has no stored elapsed for a past daily, #284); the real
ranked time would need the leaderboard slice, which is hidden (`state:
.hidden`, same dormant-VM caveat).

| Element → action | Destination | Presentation | Back/Close lands on |
|---|---|---|---|
| Close tap | `Self.popToNewGame(path:)` → `path?.wrappedValue.removeAll()` | pop-to-root | HOME (**not** `MS-DAILY-HUB`) — CODE CONTRADICTED vs. a mirror-of-Sudoku assumption; MS pops the whole path, Sudoku pops one entry |

**Covering behavior / state variants:** same scaffold shape as
`SUD-COMPLETION-REVIEW`; no Play Again; no mistake row.

---

## SETTINGS

**Entry points:** HOME "Settings" card / sidebar row.

**Code:** `SudokuUI/Settings/SettingsView.swift`,
`MinesweeperUI/SettingsView.swift`, `SettingsKit/Sources/SettingsUI/Settings/*`.

**Element inventory:** GC status row (`settings.gameCenter`), stats row,
locale row (read-only), audio section (mute/music-volume/sfx-volume/
music-enabled/haptics toggles, ids `audio.settings.*`), reminders section
(see `REMINDER-*` ids under it), Storage section "Clear cache" button,
About section (Version row +, Sudoku-only, Generator row), Notices section
(acknowledgements deep-link, copyright).

**Per-interaction outcome:**

| Element → action | Destination | Presentation | Back/Close lands on |
|---|---|---|---|
| Reminders "Enable"/"Turn On" row tap | `model.enable()` | `sheet(detent: .medium)` → `REMINDER-PRIMER` | dismiss → `SETTINGS` |
| Reminders denied-status row tap | `model.showDeniedExplainer()` | `sheet(detent: .medium)` → `REMINDER-DENIED` | dismiss → `SETTINGS` |
| Reminders "Turn off reminders" tap | `model.disable()` | side-effect | `SETTINGS` (status row switches back to enable row) |
| "Clear cache" tap | `showClearCacheConfirmation = true` | `.confirmationDialog` → `CLEAR-CACHE-DIALOG` | see that contract |
| Acknowledgements deep-link tap (iOS only) | `UIApplication.shared.open(UIApplication.openSettingsURLString)` | external (system Settings.app) | user manually returns via app-switcher — no in-app back |

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
affordance (Daily solve only — MS's completion overlay has no reminder
affordance, only Settings-initiated).

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

**Entry points:** HOME leaderboard card (authenticated only).

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

**Entry points:** HOME leaderboard card tap while `authState != .authenticated`.

**Code:** `GameAppKit/MakeGameApp+Modifiers.swift`
`universalRootModifiers` — bound to the stable `GameRootViewModel`, not a
transient per-render VM (deliberate fix for the "alert never fires"
computed-property footgun).

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
