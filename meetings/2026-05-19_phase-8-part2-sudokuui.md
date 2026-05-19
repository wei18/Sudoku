# 2026-05-19 — Phase 8 Part 2 (SudokuUI: Board + Completion + Leaderboard + Settings + lock)

Session continuation of `ae54f5ea-6b89-4f59-9d9f-cafb8dff08f6`.
Mode: AI Collaboration Mode (Leader + 1 Developer subagent dispatch, background).

## Goal

Execute Phase 8 **Part 2** (steps 8.7–8.11): BoardView (12 snapshots + Mac keyboard + A11y dump) / CompletionView (3 snapshots + behavior) / LeaderboardView (3 scopes + AX3 vertical stack, behavior-only) / SettingsView (behavior-only) / snapshot baseline lock with plan.md §8.11 amendment.

## Decisions

1. **BoardView grid sizing**: `GeometryReader` with `side = min(width, height)`, `cellSide = side / 9`, square cells. `.aspectRatio(1, contentMode: .fit)` for board. Digit font size = `cellSide * 0.6` is **NOT** Dynamic Type-bound (per §How.5.7 — only timer + controls scale with Dynamic Type; the 9×9 grid maintains visual structure).
2. **GameViewModel snapshot-only init**: extra constructor that bypasses the `GameSession` actor entirely. Used by snapshot tests for synchronous, deterministic rendering without spinning generators. Live VMs still go through the actor for real game state mutation.
3. **Mac keyboard bindings**: `⌘Z` undo / `⌘⇧Z` redo (matches `docs/designs/code/05-board.md` line 109; alternative `⌘Y` was rejected for parity with macOS-native apps). Hidden `Button` views with `.keyboardShortcut` sit in `.background()`; Mac App menu picks them up automatically, iPad external keyboards inherit. Board uses `.focusable() + .onKeyPress` for arrows / 1-9 / 0 / p / delete.
4. **CompletionView state machine** `.loading → .loaded(slice) | .unauthenticated | .failed(reason)`. `bootstrap()` maps `GameCenterError.notAuthenticated` and `.cancelled` to `.unauthenticated`; everything else lands in `.failed`. `.practiceMode` branch (designed in design preview code) **NOT** implemented in Part 2 scope — deferred to a Phase 9 follow-up when SudokuApp wires Practice completion via route flag.
5. **LeaderboardView AX3 implementation = pure SwiftUI**: `@Environment(\.dynamicTypeSize) >= .accessibility3` inside `LeaderboardRow`, switches between HStack and VStack. No custom `Layout` helper. Friends-auth gating in VM: `.notDetermined` triggers `requestFriendsAuthorization()`; `.denied`/`.restricted` short-circuits to `.friendsDenied` without fetch.
6. **§How.5.8 plan.md amendment 21 → 25**: amended `plan.md §8.11` + Appendix C Phase 8 gate to reflect actual baseline (Root×2 + Home×2 added in Part 1 beyond the strict §How.5.8 matrix). `design.md §How.5.8` itself **NOT** amended (the canonical 21-image *matrix* is unchanged — the count was a derived figure).

## Rejected alternatives

- **⌘Y for redo**: rejected for ⌘⇧Z (macOS-native convention).
- **Custom `Layout` helper for AX3 row stack**: rejected — pure-SwiftUI conditional is simpler and works.
- **Trimming Part 1 Root + Home snapshots** to fit plan.md §8.11's 21: rejected — they're useful and self-documenting. Plan.md amended instead.
- **Implementing `.practiceMode` CompletionView variant in Part 2**: rejected as scope — Practice completion flow is a Phase 9 wiring concern.

## Subagent dispatch — Phase 8 Part 2 background

| Step | Commit | New tests | New PNGs |
|---|---|---|---|
| 8.7 BoardView (12 snapshots + 4 keyboard + 1 A11y) | `99f38ea` | 17 | 12 |
| 8.8 CompletionView + ViewModel (3 state snapshots + 2 behavior) | `57fc4df` | 5 | 3 |
| 8.9 LeaderboardView + AX3 + friends-auth gating | `0ec89bd` | 4 | 0 |
| 8.10 SettingsView (Generator row + clear cache) | `aab54aa` | 3 | 0 |
| 8.11 Plan amendment (21 → 25 baseline) | `8d27477` | 0 | 0 |

**Total Part 2: 29 new tests, 15 new PNG baselines. 280 → 309, 0 warnings Swift 6 strict.**

**Combined Phase 8 (Part 1 + Part 2)**: 12 commits, 61 new tests (+32 +29), 25 PNG baselines (10 + 15), full SudokuUI v1 surface area covered.

## Phase 9 readiness flagged by subagent

- `RootView(viewModel: RootViewModel)` is wire-in entry. `AppComposition.live` constructs:
  - `RootViewModel(persistence:, gameCenter:)` — exists from Part 1.
  - Each downstream VM (`GameViewModel`, `CompletionViewModel`, `LeaderboardViewModel`, `SettingsViewModel`) takes its protocol seams + path binding.
  - `RootView` has placeholder `destination: { _ in EmptyView() }` — Phase 9 wires the per-route VM construction inside that closure.
  - Protocol surfaces (`PersistenceProtocol`, `GameCenterClient`, `PuzzleProviderProtocol`) stable, consumed via existential `any` — no module-boundary changes needed.
- **Forecast risk**: `GameViewModel.init` requires both a `GameSession` instance AND an initial Board to seed the observable mirror. Phase 9 needs an **async factory** in `AppComposition.live` that loads snapshot from `Persistence.loadOrCreate` first, then constructs the live VM with materialized state. Factory belongs in AppComposition, NOT in the VM.

## Leader-parallel work this session

During Phase 8 Part 2's ~16-minute background run:
- Created task #21, marked in_progress.
- Wrote Phase 8 Part 1 meeting log (`2026-05-19_phase-8-part1-sudokuui.md`) and committed it.
- Pre-drafted Phase 9 dispatch (5 steps: AppComposition / entitlements / PrivacyInfo / xcstrings seed / 5-locale AI translation pass).

## Next session

Phase 9 — `App` target wiring, already dispatched in background. Composition root + entitlements + PrivacyInfo + Localizable.xcstrings seed + 5-locale AI translation. After Phase 9 lands, codebase is feature-complete; Phase 10 (manual TestFlight + ASC submission checklists) is all that remains.
