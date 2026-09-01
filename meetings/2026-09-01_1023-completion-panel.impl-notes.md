# #1023 Phase A — Completion glass panel — impl notes

Live log, updated incrementally while implementing. See dispatch for full spec.

## Code map confirmed (2026-09-01, fresh scan)

- `CompletionOverlayScaffold` (GameShellKit/GameShellUI/Completion) — opaque bg at
  lines 58-60 of the pre-change file, `.accessibilityAddTraits(.isModal)` at 84,
  a11y id `game.completion.close` at 132/145. CTA area currently: onPlayAgain
  (optional closure) → Play Again above Close, else Close-only.
- `CompletionScreen` — hero reveal (M2) already implemented via `heroReveal(_:index:reduceMotion:)`
  using `MotionGate.animation` which returns `nil` (no animation, snap) under RM.
  Must change to fade-not-snap per §6 M2 RM row.
- 4 call sites confirmed: Sudoku `BoardView+Completion.swift:113` (live), Sudoku
  `LiveRouteFactory.swift:230` (.completion pushed review), Sudoku
  `BoardLoaderView.swift:183` (.completedRedirect review), MS
  `MinesweeperBoardView.swift:1160` (live), MS `LiveRouteFactory.swift:290`
  (.completion pushed review), MS `MinesweeperDailyOpenGuardView.swift:173`
  (.resolved(.completed) review).
- Haptic authority already on VM edge: Sudoku `GameViewModel.swift:538`
  `soundPlayer.play(.sudokuWin)`; MS `MinesweeperGameViewModel.swift` fires
  `.minesweeperExplosion` on loss / `.minesweeperWin` on win inside
  `fireRevealAudio`. `AudioEvent`s aren't yet declared with `.success`/`.error`
  haptics attached — need to verify (see below) that `.sudokuWin`/`.minesweeperWin`
  carry `.success` and `.minesweeperExplosion` carries `.error`, since R1 says the
  panel itself never fires haptics — the existing VM-edge fire is the ONE haptic.
- No existing `GlassEffectContainer` usage anywhere in the repo yet — this is the
  first real glass surface built (G4 is still #1022, not started).
- Difficulty label pattern already established:
  `Text(LocalizedStringKey(difficulty.rawValue.capitalized))` (PracticeHubView.swift:60).
  Reused for the new "Next: <difficulty>" CTA instead of minting a new format string.
- Daily progress data IS available at path-1 call sites via existing DI:
  Sudoku `puzzleProvider.fetchDailyTrio(date:)` (in-memory-cached) +
  `persistence.fetchCompletedDailyIds(for:)`; MS `MinesweeperDailyProviding.dailyTrio(date:)`
  (sync) + `MinesweeperSavedGameStore.fetchCompletedDailyIds(for:)`. Wiring a new
  injected closure (`fetchDailyProgress`, mirrors `makeDailyReminderPrimer`'s
  injection shape) into BoardView / MinesweeperBoardView from each app's
  LiveRouteFactory, resolved once on the `.completed` transition via `Task`.

## Design decisions

- `CompletionVariant`: `public enum CompletionVariant: Sendable, Equatable { case liveSolve, review }`.
- `CompletionMotionPlan`: pure value type computed from `(variant, outcomeKind, reduceMotion)`.
  Ritual (M1 accent seep + M3 pip + M4 counter) plays ONLY for `(liveSolve, .success)`.
  M10 panel rise plays for `liveSolve` (both outcomes — MS loss still rises into
  view, it just skips the win ritual); `.none` for `review`. M2 hero reveal always
  plays (content reveal, not "ritual") — RM changes it from snap-off to fade-only,
  a deliberate behavior change per R2.
- `CompletionContext`: 4 cases matching the §3.5 CTA table exactly, closures for
  the primary action; `onClose` stays a separate always-present param on the
  scaffold (existing convention). `dailyAllDone`'s "See you tomorrow" primary
  IS the close action (no separate secondary scaffold button — the reminder
  opt-in is the existing card-level `reminderPrimer` footer, per R4, unchanged).
- Daily "more today" derivation: new `DailyProgress` enum + `fetchDailyProgress`
  closure injected the same way as `makeDailyReminderPrimer`, resolved async on
  the completed transition, defaulting to `.allDone` (never over-claims a "Next"
  that doesn't exist) until resolved.

## Deviations from dispatch (final)

1. **`onAppear`-driven M10 panel-rise doesn't fire in the `MinesweeperBoardTerminalOverlaySnapshotTests` composition** (board + hoisted-overlay path), same class of limitation `CompletionScreen`'s hero already has (`completionHeroSkipsReveal`'s doc comment) — confirmed via a forced-true diagnostic that even the PRE-EXISTING `CompletionScreen` hero reveal doesn't fire in that exact composition either (this suite has prior-observation history of "baselines regenerated but tests still report failures", 2026-06-25 — a pre-existing flake, not introduced here). Fix: added `.environment(\.completionHeroSkipsReveal, true)` to that ONE test's harness, matching the established pattern every other reveal-dependent snapshot suite already uses (`MinesweeperCompletionSnapshotTests`, `CompletionViewTests`, `ASCScreenshotEmitTests`). Not a production behavior change — purely a test-harness fix.
2. **Accent glow tuned down from an initial too-strong pass** (0.28 opacity / 480pt radius rendered as a near-solid dark wash that made CTA text illegible in the offline snapshot capture) to 0.16 opacity / 260pt radius. Exact visual tuning still needs a live-simulator pass (idb) — not done in this Phase (see open questions).
3. **`CompletionContext.practice`/`.loss` take an OPTIONAL action closure** (`(() -> Void)?`, not the non-optional shape implied by a literal reading of R4), falling back to a single Close-only button when nil — preserves the exact pre-#1023 single-button rendering for the 3 review-variant call sites that have no "play again"/"try again" presenter wired (matches the ORIGINAL scaffold's nil-`onPlayAgain` behavior byte-for-byte in that regard, modulo the background/glass change).
4. **Daily "more today?" (`dailyMoreToday` vs `dailyAllDone`) is REAL production wiring, not stubbed** — both apps got a new `fetchDailyProgress`/`onDailyNext` closure pair (mirrors the existing `makeDailyReminderPrimer` injection shape) threaded from each `LiveRouteFactory` through every Daily call site (live board, pushed review route, loader/guard redirect), resolving via the already-injected `puzzleProvider`/`persistence` (Sudoku) or `LiveMinesweeperDailyProvider`/`savedGameStore` (MS). Defaults to `.allDone` until resolved — never overclaims a "Next" that doesn't exist.
5. **`Next: <difficulty>` composes two independently-localized `Text` values with a hardcoded ASCII space** between them (`Text("Next:") + " " + Text(difficulty)`), matching the EXISTING repo precedent for this exact pattern (`PracticeHubView.swift`'s difficulty-label composition uses a hardcoded `" · "` connector). Consequence: zh-Hant renders "下一題: 中等" (with a half-width space) rather than design.md's exact "下一題:中等" (no space) — a minor, precedent-consistent typographic deviation, not re-architected given the existing codebase convention.
6. **File-length ceiling fallout**: adding the Daily-progress plumbing pushed `BoardView.swift`/`BoardLoaderView.swift` (Sudoku) and `Theme.swift` (GameShellKit) over 400 lines. Extracted `BoardView+Keyboard.swift` (pre-existing keyboard-handling code, moved verbatim) and `StreakTokens.swift` (new R5 token, split out) rather than growing those files — repo convention.

## Open questions for Phase B

- Accent glow / panel-rise exact visual tuning needs a live iOS-simulator (idb) pass — the acceptance criteria's "board visible behind the glass panel — screenshot evidence" bullet is NOT covered by this Phase A report (only proven via the headless composited snapshot, which is a good structural proxy but not the real thing).
- M3 (streak pip advance) / M4 (streak counter +1) motion-plan entries are fully defined and tested (`CompletionMotionPlan`), but have no consumer yet — Phase B wires the actual streak view using `theme.streak.pipOff` + `theme.accent.celebratory`.
- `identity.tier1/2/3` IC-contrast rung work from design.md §5.4 is unrelated to this issue and untouched.

---

# Phase B — streak ritual wiring (2026-09-01)

Status: IN_PROGRESS
Owner: Developer (session/defiant-stork-cq9s)
Dispatched by: team-lead
Started: 2026-09-01

## Code map confirmed (fresh scan)

- Live-daily-win call sites are EXACTLY ONE per app (not all 4 completion
  paths): Sudoku `BoardView+Completion.completionSurface` (variant
  `.liveSolve`, `BoardView` ← `BoardLoaderView` ← `LiveRouteFactory`'s
  `.board` case); MS `MinesweeperDailyOpenGuardView`'s `.resolved(.playable)`
  branch (constructs `MinesweeperBoardView` directly, NOT via
  `MinesweeperFreshBoardLoaderView`) ← `LiveRouteFactory+DailyBoardOpen
  .boardOpenDestination`. The other 3 review paths per app (pushed
  `.completion`, Sudoku's `.completedRedirect`, MS's `.resolved(.completed)`)
  all use `variant: .review` and will simply never be wired with a streak
  provider — no defensive plumbing needed there beyond the scaffold's own
  gate (see R3 below).
- Existing week-window fetch (`fetchWeekWindow(referenceDate:)` +
  `WeekWindowSlot`) is an `internal` INSTANCE method on
  `DailyHubViewModel`/`MinesweeperDailyHubViewModel` — not callable from
  `LiveRouteFactory` (different module, and instantiating a whole Hub VM
  just to read one method would be architecturally wrong). Mirrors
  `makeFetchDailyProgress`'s existing precedent: a NEW standalone
  `makeFetchStreakAdvance` static factory per app, calling
  `persistence.fetchCompletedDailyIdsByDay()` / `savedGameStore
  .fetchCompletedDailyIdsByDay()` directly and reusing the PUBLIC
  `DailyStripLogic.computeStreak(days:)` / `MinesweeperDailyStripLogic
  .computeStreak(days:)` — satisfies R1 ("do NOT invent a second streak
  algorithm") while staying within the existing no-shared-hub-VM-widget
  convention (#774's copy-paste-adapt scope note already duplicates this
  exact window-slicing shape between the two apps' Hub VMs; a 3rd, smaller
  duplicate in each `LiveRouteFactory`+DailyBoardOpen file is consistent,
  not a new anti-pattern).
- `theme.streak` (`StreakTokens.pipOff`) is ALREADY wired end-to-end by
  Phase A (`Theme` protocol requirement + `NeutralTheme`/`DefaultTheme`
  (Sudoku)/`MinesweeperTheme` all provide concrete values) — nothing to add
  there, just consume.
- `"%lld day streak"` / `"7+ day streak"` L10n keys already exist ×7 in BOTH
  apps' `Localizable.xcstrings` (from #843's `DailyStripView`) — reused
  verbatim per R5, no new strings minted.

## Design decisions

- **Pre/post computed via set-membership, not timing.** `kickOffDailyProgressFetch`-style
  fetches race an in-flight async persist (the `persistJoin`/`pendingTerminalPersistTask`
  pattern means the just-solved puzzleId may or may not have landed in
  `fetchCompletedDailyIdsByDay()`'s result yet). Fix: `makeFetchStreakAdvance`
  explicitly EXCLUDES `currentPuzzleId` from today's completed-id set to build
  the "pre" window, and explicitly UNIONS it in to build "post" — deterministic
  regardless of whether the persist has landed, no race window. `preCount`/
  `postCount` = `computeStreak` over the pre/post day arrays (identical for
  every day except today's own slot).
- **`CompletionStreakAdvance` (GameShellUI) is minimal**: `pipStates: [Bool]`
  (7, oldest→today, POST-solve — the only state actually rendered once
  settled), `preCount: Int`, `postCount: Int`, plus a computed
  `todayAdvanced: Bool { preCount != postCount }`. Proved by construction
  (see set-membership note above) that `preCount != postCount` if and only if
  today's own pip flipped off→on — so a single boolean derived from the two
  counts is sufcient to gate the M3/M4 animation; no second "did today
  change" flag needed, and no `prePipStates` array needed (only today's slot
  can ever differ pre→post, so the view derives the pre-state of pip[6] by
  flipping `pipStates.last` when `todayAdvanced`).
- **Placement: inside `CompletionOverlayScaffold`, between `card()` and
  `ctas`.** The scaffold already holds all 3 gating conditions (`variant`,
  `outcomeKind`, `context`) locally for M1/M10; `CompletionScreen` (the
  per-app card content) knows none of them. Adding a 4th optional init param
  (`streakAdvance: CompletionStreakAdvance? = nil`) keeps the gate
  (R3: `variant == .liveSolve && outcomeKind == .success && context is
  daily-shaped && streakAdvance != nil`) in ONE place, enforced regardless of
  what a call site passes — defense in depth, a review path can never leak
  the ritual even if a future call site mistakenly threads a provider in.
- **M3 bounce via `.phaseAnimator`, M4 via `.contentTransition(.numericText/.opacity)`** —
  both are the official SwiftUI mechanisms for exactly this shape (a
  trigger-driven 3-phase scale bounce; an animated in-place digit swap), no
  hand-rolled timer/offset chains. Reduce Motion: `.fillOnly` skips the
  `.phaseAnimator` entirely (fill-only, static); `.numericText()` swaps to
  `.opacity` crossfade — matches CompletionMotionPlan's existing RM forms
  exactly, no new gating logic invented at the view layer.
- **Haptics (R4):** untouched — `CompletionStreakView` never references
  `soundPlayer`; the existing single `.success`/`.error` VM-edge fire from
  Phase A's map (BoardView+Completion notes) remains the ONE haptic.

## Deviations from dispatch (final)

1. **`showsStreakSection` lives on `CompletionStreakAdvance`, not `CompletionOverlayScaffold`** — a first pass put the pure gate as a `static func` on the scaffold itself (mirroring how I'd initially framed R3), but `CompletionOverlayScaffold` conforms to `View` and is therefore `@MainActor`-isolated in this package's build settings; a plain `@Suite struct` test calling it hit "sending task-isolated value to main-actor-isolated static method" errors. Moved the pure function onto `CompletionStreakAdvance` (a plain `Sendable` value type) instead — same signature, freely callable from non-isolated test contexts, and arguably the more natural owner anyway (mirrors `CompletionMotionPlan.plan` being a static func on the plan type, not on the scaffold).
2. **File-length ceiling fallout, again** (same class of thing Phase A's report flagged): `BoardLoaderView.swift` was already at 399/400 lines; adding `fetchStreakAdvance` pushed it to 409. Extracted the two `self`-free static helpers (`isLoaderFailLaunch`, `identity(from:)`) into a new `BoardLoaderView+Identity.swift` sibling — deliberately did NOT try to move `load()`/`mountLoaded()` (they need direct access to `self.state` etc., which would require widening several `private` properties to `internal` for a much larger and riskier diff). Sudoku's `LiveRouteFactory.swift` similarly grew from 400→438; extracted the new `makeFetchStreakAdvance` factory (+ its window-size constant) into `LiveRouteFactory+StreakAdvance.swift`, mirroring the MS side's pre-existing `LiveRouteFactory+DailyBoardOpen.swift` split.
3. **`MinesweeperFreshBoardLoaderView` does NOT get `fetchStreakAdvance` threaded through it**, even though its init signature could accept one — mirrors an EXISTING (pre-#1023 Phase B) gap: `boardOpenDestination` never threads `fetchDailyProgress`/`onDailyNext` into that loader either (only into `MinesweeperDailyOpenGuardView`, which is the only path a store-backed Daily board actually takes). Practice never needs streak data (not Daily); the no-store Daily fallback (preview/test only, `savedGameStore == nil`) already gets `.allDone`-equivalent behavior for daily progress and would get `nil` for streak too, consistent, not a regression I introduced.
4. **No date injection on `makeFetchStreakAdvance`** (either app) — mirrors `makeFetchDailyProgress`'s existing non-injected `Date()` shape exactly (Phase A precedent, not something I invented). Tests anchor on a `Date()` read at test setup and day-bucket via `UTCDay`, which is safe except across an exact UTC-midnight race window (accepted, same risk profile the sibling factory already carries, and neither is exercised in CI at midnight).

## Open questions

None load-bearing. One pre-existing (not introduced by Phase B) doc staleness noted but left alone as out of scope: `docs/screen-contracts.md`'s `SUD-COMPLETION-OVERLAY` "Element inventory" table (~line 608) still only lists the pre-#652/#1023 Play-Again-only CTA shape — it doesn't reflect §3.5's 4-row CTA hierarchy (Next/Done, See you tomorrow, Try Again) Phase A already shipped, or Phase B's streak section. Predates both phases of #1023; a full rewrite of that table is a larger doc project than a re-anchor sweep, flagged for a follow-up rather than done here.

Status: COMPLETE
