# Dead VM Factories Audit — Impl Notes

GitHub issue #34. Follow-up to PR #33 (which deleted `homeViewModelFactory`).
Audit the remaining 6 ViewModelFactory entries plumbed through
`AppComposition.swift` / `Live.swift` / `Preview.swift` and delete the dead ones.

## Status: COMPLETE

## Audit method

For each factory, ran:

```
rg -n "<factoryName>" Packages/SudokuKit/Sources/ Packages/SudokuKit/Tests/ App/
```

Classified each hit as SETTER (definition / wiring / `_ = ` touch) vs CONSUMER
(a View / Coordinator that reads `composition.<factoryName>(...)` and uses the
resulting VM). Also grep'd `composition.` everywhere and grep'd direct View
constructor sites (`DailyHubView(`, `GameView(`, etc.) to catch indirect flows.

Result: **The only `composition.<...>` reader anywhere is `App/SudokuApp.swift`
reading `composition.rootViewModel`.** No site constructs any of the six
downstream Views. `RootView` stubs its NavigationStack destination as
`{ _ in EmptyView() }`. All 6 factories are dead.

## Per-factory verdict

| Factory | Consumers (file:line) | Verdict | Action |
|---|---|---|---|
| `dailyHubViewModelFactory` | none (only struct decl + Live/Preview wiring + 1 test touch line) | DEAD | DELETE |
| `practiceHubViewModelFactory` | none (only struct decl + Live/Preview wiring + 1 test touch line) | DEAD | DELETE |
| `gameViewModelFactory` | none (only struct decl + Live/Preview wiring + 1 test touch line) | DEAD | DELETE |
| `completionViewModelFactory` | none (only struct decl + Live/Preview wiring + 1 test touch line) | DEAD | DELETE |
| `leaderboardViewModelFactory` | none (only struct decl + Live/Preview wiring + 1 test touch line) | DEAD | DELETE |
| `settingsViewModelFactory` | none (only struct decl + Live/Preview wiring + 1 test touch line) | DEAD | DELETE |

## Per-file change summary

### `Packages/SudokuKit/Sources/AppComposition/AppComposition.swift`
- Removed 6 stored properties (`dailyHubViewModelFactory` … `settingsViewModelFactory`).
- Removed 6 init parameters and 6 `self.xxx = xxx` assignments.
- Removed now-unused internal imports: `GameCenterClient`, `GameState`,
  `Persistence`, `SudokuEngine`, `Telemetry`.
- Demoted `public import PuzzleStore` → removed (no `PuzzleEnvelope` in public
  surface anymore).
- Kept: `Foundation` (parity / future-proof), `public import SudokuUI` (still
  re-exports `RootViewModel`).
- Trimmed the docstring's `gameViewModelFactory` paragraph (it described a
  factory that no longer exists).

### `Packages/SudokuKit/Sources/AppComposition/Live.swift`
- Removed all 6 `xxxFactory: { ... }` arguments from the `AppComposition(...)`
  call, leaving only `rootViewModel:`.
- Removed the now-unused `fileprivate static func leaderboardId(for:)` helper
  (its sole caller was `completionViewModelFactory`).
- Removed now-unused internal imports: `GameState` (for `GameSession` /
  `GameStateTelemetryAdapter`), `SudokuEngine` (for `Puzzle` types referenced
  only by deleted VMs).
- Trimmed the docstring sentence describing the `async throws`
  `gameViewModelFactory`.
- Kept: `Foundation`, `GameCenterClient`, `Persistence`, `PuzzleStore`,
  `SudokuUI`, `Telemetry`.

### `Packages/SudokuKit/Sources/AppComposition/Preview.swift`
- Removed all 6 `xxxFactory: { ... }` arguments from the `AppComposition(...)`
  call, leaving only `rootViewModel:`.
- Removed `let provider = FakePuzzleProvider()` (only used by the deleted
  daily / practice factories).
- Removed now-unused internal imports: `Foundation`, `GameCenterClient`,
  `GameState`, `Persistence`, `PuzzleStore`, `SudokuEngine`, `Telemetry`.
- Kept: `SudokuKitTesting` (for `FakeGameCenterClient`, `FakePersistence`),
  `SudokuUI` (for `RootViewModel`).

### `Packages/SudokuKit/Tests/AppCompositionTests/CompositionTests.swift`
- Removed 6 `_ = composition.xxxFactory` touch lines in
  `liveCompositionWiresAllProtocols()`.
- Adjusted the inline comment.
- (Imports of `GameCenterClient` / `Persistence` left untouched — they are
  unused but test targets are permissive; PR #33 left the equivalent
  `HomeViewModel` test-side cruft alone, same precedent.)

## Test count delta

- Before: 364 / 364.
- After: 364 / 364.
- Delta: **0**.

## Build / warning status

- `swift build` clean. Build log:
  ```
  [3/6] Compiling AppComposition Live.swift
  [4/6] Compiling AppComposition Preview.swift
  [5/6] Emitting module AppComposition
  [6/6] Compiling AppComposition AppComposition.swift
  Build complete! (2.67s)
  ```
- Zero warnings. Swift 6 strict mode + access-level imports happy.

## TODO sweep

`rg -n "TODO|FIXME|XXX" Packages/SudokuKit/Sources/AppComposition/`
→ no matches.

## Verification of no stale references

`rg -n "dailyHubViewModelFactory|practiceHubViewModelFactory|gameViewModelFactory|completionViewModelFactory|leaderboardViewModelFactory|settingsViewModelFactory" Packages/SudokuKit/Sources/ Packages/SudokuKit/Tests/ App/`
→ no matches.

## §未決 (flagged for Leader)

- **Architectural consistency observation**: All 7 VM factories
  (including `homeViewModelFactory` removed in PR #33) turned out to be dead.
  AppComposition is now a one-field struct that only carries `rootViewModel`.
  The DI composition root pattern in §How.1 may want a re-read — either
  (a) routing all downstream VMs through factories was the intended design and
  the Views never got wired up, or (b) inline VM construction (as RootView /
  HomeView already do) is now the de facto pattern and AppComposition should
  collapse to just a `RootViewModel` provider. Not fixing here; flagging for
  separate refactor decision.
- **Test target import hygiene**: `CompositionTests.swift` still imports
  `GameCenterClient` and `Persistence` which are now unused at the source
  level (only Mirror-reflected type-name strings are inspected). Left as-is
  for surgical-change discipline; trivial follow-up if desired.
