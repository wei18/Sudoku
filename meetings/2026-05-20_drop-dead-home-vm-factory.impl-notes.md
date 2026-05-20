# Drop dead `homeViewModelFactory` — impl notes

Branch: `chore/drop-dead-home-vm-factory`
Scope: code-only (no git / gh / commit / push).

## 設計決定

**Option chosen: Delete.**

Reasons:

1. **Plumb-through is structurally infeasible without redesign.**
   `HomeViewModel.init` is `init(path: Binding<[AppRoute]>? = nil)`. `RootView`
   constructs `HomeViewModel(path: Binding(get:set:))` where the binding is
   derived from the live `RootViewModel.path` instance. The factory in
   `Live.swift` / `Preview.swift` is `() -> HomeViewModel`, i.e. it produces
   a `HomeViewModel()` with `nil` path. That instance is unusable for
   `RootView` — the binding *must* be sourced from the `RootViewModel` that
   exists *after* composition, not from the composition root. Making the
   factory `(Binding<[AppRoute]>) -> HomeViewModel` would work, but
   (a) requires changing `RootView.init` to accept a factory closure (out of
   scope — file is in the do-not-touch list), and (b) is a larger surface
   than the cleanup task asks for.

2. **No DI parity is lost.**
   `HomeViewModel` has zero injected collaborators (no persistence, no
   GameCenter, no telemetry). Unlike `gameViewModelFactory` (which wires
   `Persistence` + `Telemetry`) or `dailyHubViewModelFactory` (which wires
   `puzzleStore` + `persistence`), the Home factory wraps a literal
   `HomeViewModel()` call. Deleting it removes a no-op indirection, not a
   real composition seam.

3. **Single consumer was a touch-test, not a real read.**
   The only reference to `composition.homeViewModelFactory` outside the
   AppComposition module was `CompositionTests.liveCompositionWiresAllProtocols`
   doing `_ = composition.homeViewModelFactory` purely as a presence check.
   No behavioral coverage is lost.

## 變更摘要 (per-file)

| File | Change |
|------|--------|
| `Packages/SudokuKit/Sources/AppComposition/AppComposition.swift` | Removed `homeViewModelFactory` stored property, init parameter, and assignment (3 line-removals). |
| `Packages/SudokuKit/Sources/AppComposition/Live.swift` | Removed `homeViewModelFactory: { HomeViewModel() }` from the `AppComposition(...)` initializer call. |
| `Packages/SudokuKit/Sources/AppComposition/Preview.swift` | Removed `homeViewModelFactory: { HomeViewModel() }` from the `fakeComposition()` initializer call. |
| `Packages/SudokuKit/Tests/AppCompositionTests/CompositionTests.swift` | Removed the `_ = composition.homeViewModelFactory` touch line. |

No other files touched. `SudokuUI` import in `AppComposition.swift` retained — other VM types (`DailyHubViewModel`, `GameViewModel`, etc.) still resolve through it.

## 驗證

- `swift build` → **Build complete!** (no warnings, Swift 6 strict mode).
- `swift test` → **Test run with 363 tests in 69 suites passed**.
  - Pre-flight expected count was 355 (per task brief); actual baseline is 363. Net delta from this change: **0** (no test added, no test removed — only a `_ = ` touch line dropped inside an existing test that still runs and passes).
- TODO sweep on `Packages/SudokuKit/Sources/AppComposition/`:

  ```
  /Users/zw/GitHub/Wei18/Sudoku-spec/Packages/SudokuKit/Sources/AppComposition/Live.swift:11:// constructing the VM (Phase 8 Part 2 forecast).
  ```

  The one hit is a pre-existing historical comment on the live
  `GameViewModel` snapshot pattern. Out of scope per Surgical Changes.

## §未決

While verifying that `homeViewModelFactory` had no production consumer, I ran:

```
rg -n 'dailyHubViewModelFactory|practiceHubViewModelFactory|gameViewModelFactory|completionViewModelFactory|leaderboardViewModelFactory|settingsViewModelFactory' --type swift \
  | rg -v 'Packages/SudokuKit/Sources/AppComposition/|Packages/SudokuKit/Tests/AppCompositionTests/'
```

**Result: zero hits.** The App target (`App/SudokuApp.swift`) only consumes
`composition.rootViewModel`. None of the remaining six ViewModelFactory
entries are read by any production callsite at the time of this cleanup.

This is **NOT** fixed in this change (task scope explicitly forbids it).
Flagging for follow-up — Leader should decide whether:

- (a) those factories are about to be wired in an imminent phase and the
  current "unused" status is transitional, in which case keep them; or
- (b) the App's navigation tree actually constructs those VMs inline
  (like RootView does for HomeViewModel after PR #16), in which case
  all six are dead by the same logic that killed `homeViewModelFactory`
  and a larger cleanup is warranted.

Recommend a sweep of `Packages/SudokuKit/Sources/SudokuUI/` to find any
inline `DailyHubViewModel(...)`, `GameViewModel(...)`, etc. constructions
before deciding.
