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
