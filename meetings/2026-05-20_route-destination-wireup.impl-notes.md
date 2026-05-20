# Impl Notes — route-destination-wireup (2026-05-20)

GitHub issue #45. Branch `fix/route-destination-wireup`.
Wire the `NavigationStackHost.destination` closure in `RootView` so that pushing
an `AppRoute` actually renders the matching View+VM. Today it returns
`EmptyView()` for every route — Home taps and Mac-sidebar `NavigationLink(value:)`s
all push onto the path, NavigationStack pops a screen onto the stack, and the
destination resolver renders nothing. This is the navigation-gap critical bug
follow-up to PR #44 (Bug 3 path binding) and the dead-factory audit issue #34.

Status: COMPLETE
Owner: Senior Developer (SudokuUI)
Dispatched by: Leader
Started: 2026-05-20

---

## §設計決定 (Design decisions — proposal)

### Decision 1 — Inline-construction pattern in destination closure

`RootView` (or a thin helper on `RootView`) holds a `switch route` that constructs
the appropriate downstream View + its VM **inline** in the `destination:` closure
passed to `NavigationStackHost`. No per-VM factory closures, no per-VM
`@Observable` cache.

```swift
destination: { route in
    switch route {
    case .home:
        EmptyView()  // .home is never pushed; root content already renders HomeView
    case .daily:
        DailyHubView(
            viewModel: DailyHubViewModel(
                provider: puzzleProvider,
                persistence: persistence
            )
        )
    case .practice:
        PracticeHubView(
            viewModel: PracticeHubViewModel(provider: puzzleProvider)
        )
    case .board(let puzzleId):
        BoardView(
            viewModel: GameViewModel(
                identity: PuzzleIdentity(puzzleId: puzzleId, /* … */),
                board: .empty,            // see Decision 4 (BoardView)
                status: .playing
            )
        )
    case .completion(let puzzleId, let elapsedSeconds):
        CompletionView(
            viewModel: CompletionViewModel(
                puzzleId: puzzleId,
                elapsedSeconds: elapsedSeconds,
                leaderboardId: LeaderboardIDs.id(for: .dailyEasy /* see Dec.5 */),
                gameCenter: gameCenter
            )
        )
    case .leaderboard(let leaderboardId):
        LeaderboardView(
            viewModel: LeaderboardViewModel(
                leaderboardId: leaderboardId,
                gameCenter: gameCenter
            )
        )
    case .settings:
        SettingsView(viewModel: SettingsViewModel(persistence: persistence))
    }
}
```

**Why inline-in-closure (mirrors how `RootView` already constructs `HomeView`
inline in `rootContent` with a `Binding` to `viewModel.path`):**

- Already the de-facto pattern after PR #33 (HomeView inline) + PR #34 (all
  6 factories deleted). See `meetings/2026-05-20_dead-vm-factories-audit.impl-notes.md`.
- `@MainActor`-isolated, synchronous, no captures of mutable state — the VM is
  fresh per stack push, so back-navigation discards it (correct semantics: a new
  push to `.daily` after pop should re-bootstrap, matching `hasBootstrapped`
  idempotency latch on each VM).
- Matches `HomeViewModel.init(path: Binding<[AppRoute]>? = nil)` shape: VM ctors
  are pure construction, no async, no IO. (`GameViewModel` snapshot-only init
  is the same shape — see Decision 4.)
- Trivial to mirror in `#Preview` blocks for downstream views.

### Decision 2 — How RootView gets the 4 dependencies — **recommend Option A**

Three options for plumbing `(any PuzzleProviderProtocol, any PersistenceProtocol,
any GameCenterClient, Telemetry)` into the destination closure:

| Option | Mechanism | Verdict |
|---|---|---|
| **A** | `RootView.init` grows to take the 4 protocols + the `RootViewModel` | **Pick** |
| B | `AppComposition` is the source-of-truth bag; `RootView.init(composition:)` reads from it | rejected — design.md §How.1 already shows `RootView(composition:)` as one option but it crosses the module boundary in the wrong direction (SudokuUI would have to import AppComposition or AppComposition would have to be re-exported through SudokuUI). |
| C | `@Environment(\.puzzleProvider)` / `@Environment(\.persistence)` etc., set at the App scene root | rejected — adds 4 new EnvironmentKeys for a single read site; the values are not actually environmental (don't traverse the view tree as state). |

**Recommend Option A.** Concrete shape:

```swift
public struct RootView: View {
    @State private var viewModel: RootViewModel
    private let puzzleProvider: any PuzzleProviderProtocol
    private let persistence: any PersistenceProtocol
    private let gameCenter: any GameCenterClient
    private let telemetry: Telemetry  // reserved; not consumed in v1 destination closure (see Dec.4)

    public init(
        viewModel: RootViewModel,
        puzzleProvider: any PuzzleProviderProtocol,
        persistence: any PersistenceProtocol,
        gameCenter: any GameCenterClient,
        telemetry: Telemetry
    ) { … }
}
```

`AppComposition` grows 4 stored properties beside `rootViewModel` (it's already
the bag holding these via `RootViewModel.persistence` / `.gameCenter` privately;
we just lift them to be re-readable). `SudokuApp.body` passes all 5 args.

### Decision 3 — Why Option A over B / C (折衷)

- **vs B (`composition:` ctor)**: Module hygiene. `SudokuUI` cannot import
  `AppComposition` (reverse dependency direction). Inverting to "AppComposition
  defines a `RootView`-facing struct" introduces a new protocol/struct purely
  for grouping — extra ceremony with zero behavior benefit. Option A keeps the
  contract at the natural module boundary: `RootView` declares what it needs;
  `AppComposition` decides how to source it.
- **vs C (`@Environment`)**: Environment is for values consumed deep in the
  view tree (theme, locale, color scheme) — these 4 protocols are read at
  exactly one site (the destination switch). 4 boilerplate `EnvironmentKey`s
  for one read site is over-engineering (Karpathy §2 Simplicity First).
  Additional concern: existential protocols as `EnvironmentValues` require
  a sentinel default, and the natural "fatalError fake" pattern bloats the
  AppComposition target.
- Option A grows `RootView.init` from 1 to 5 params. Single call site
  (`SudokuApp.body`), so blast radius is one line. CompositionTests already
  reflects on `RootViewModel.gameCenter`/`.persistence` via Mirror — adding
  the 4 new stored properties on `RootView` is invisible to that test.

### Decision 4 — BoardView is the awkward one — pragmatic v1 approach

`GameViewModel.init(identity:session:initialBoard:…persistence:…)` (live ctor)
needs a constructed `GameSession` actor, which itself needs the resolved
`Puzzle` from `PuzzleStore.puzzle(for: puzzleId)` — an **async** call. You
cannot do `async` work in a `@ViewBuilder` destination closure synchronously.

Three implementation shapes considered:

| Shape | Tradeoff |
|---|---|
| **i** Use `GameViewModel`'s existing snapshot-only init (`init(identity:board:notes:status:…)`) — no `GameSession`, no persistence — then have `BoardView.task` resolve the puzzle and call a future `BoardView`-owned `attach(session:persistence:)` mutator | matches the existing snapshot-init seam already used by previews/tests; requires a new `attach` method on `GameViewModel` to upgrade from preview-mode to live-mode |
| **ii** Pass `puzzleStore` + `persistence` + `telemetry` into `GameViewModel` and let it lazily await the puzzle in its own `bootstrap()` | requires changing `GameViewModel` init signature (out of scope per the dispatch — "DO NOT touch their VMs") |
| **iii** Wrap the BoardView destination in a `BoardLoaderView` that does the async fetch and then renders `BoardView(viewModel:)` | out of scope per dispatch — "DO NOT touch individual View files" |

The dispatch explicitly says "DO NOT touch individual View files / DO NOT touch
their VMs." That rules out shapes ii and iii.

**Pragmatic v1 picked**: use the **snapshot-only init** (`init(identity:board:notes:status:…)`)
to construct a `GameViewModel` with `board: .empty` and `status: .playing`. The
result is a *renderable* but non-persisting BoardView — taps mutate the local
mirror but don't go through a `GameSession` actor and don't save to CloudKit.
This is **not the final live wiring** — it makes the navigation gap closeable
without crossing the scope fence, and lights up the destination so snapshot tests
and visual QA can drive through the stack. The full live wiring requires either
(ii) widening `GameViewModel`'s init or (iii) adding a `BoardLoaderView` — both
out-of-scope here. **Flagged in §未決.**

If Leader wants live BoardView wiring inside *this* PR, the scope fence needs to
lift to include `Packages/SudokuKit/Sources/SudokuUI/Board/GameViewModel.swift`
(approve shape ii) or a new `Packages/SudokuKit/Sources/SudokuUI/Board/BoardLoaderView.swift`
(approve shape iii).

### Decision 5 — CompletionView leaderboardId derivation

`AppRoute.completion(puzzleId, elapsedSeconds)` carries no difficulty / mode,
but `CompletionViewModel` needs a `leaderboardId`. Two options:

- **5a**: Default to `LeaderboardIDs.id(for: .dailyEasy)` (placeholder mirroring
  the `HomeMode.leaderboard` choice from PR #44).
- **5b**: Extend `AppRoute.completion` to carry the difficulty / mode so the
  correct leaderboard id resolves. Out of scope (modifying `AppRoute.swift` not
  in the scope fence).

**Recommend 5a** as the same placeholder used for `HomeMode.leaderboard.appRoute`
in PR #44. Flagged in §未決 for a separate follow-up.

### Decision 6 — Smoke-test trace (will be filled in during IMPL step)

The end-to-end trace from each `HomeMode` tap → `HomeView.select` →
`HomeViewModel.select(_:)` → `path.append(mode.appRoute)` → `RootViewModel.path`
mutation (via binding) → `NavigationStackHost`'s bound `NavigationStack(path:)`
→ `.navigationDestination(for: AppRoute.self)` resolver → destination closure
→ matched View+VM. Will be written out per-route once Leader approves.

---

## §折衷 (Tradeoffs)

- **Option A vs B**: A is 4 extra `RootView.init` params; B is a new module-crossing
  re-export. A is the smaller diff and the more conventional View-takes-deps shape.
- **Snapshot-init BoardView (Decision 4)**: closes the navigation gap *visibly*
  without persistence wiring. Not final shipping behavior — flagged as known gap.
- **CompletionView leaderboardId placeholder (Decision 5)**: same placeholder
  pattern as PR #44 took for HomeMode.leaderboard. Will need a real fix when
  AppRoute carries difficulty/mode.

---

## §未決 (Open questions — Leader-resolvable)

1. **Decision 4 BoardView scope fence.** Three shapes (i / ii / iii) exist;
   the dispatch scope fence picks shape i by exclusion. Leader: confirm shape i,
   or lift the fence and approve shape ii (widen `GameViewModel.init`) or
   shape iii (add `BoardLoaderView`)?
2. **Decision 5 CompletionView leaderboardId.** Use `LeaderboardIDs.id(for: .dailyEasy)`
   placeholder for v1, or expand the `AppRoute.completion` case (out of current
   scope) to carry the difficulty? Recommend placeholder + a §Backlog item in
   design.md for the AppRoute expansion.
3. **Decision 2 confirmation.** Confirm Option A (RootView.init grows 4 params)
   over B (`composition:` ctor) or C (`@Environment` keys)?
4. **Spec amend wording for §How.1.** Plan to: (a) remove references to per-view
   `*ViewModelFactory`; (b) document the "inline construction in destination
   closure" pattern; (c) cross-link issues #15 #34 #45. Confirm this is the
   amend Leader wants, or any extra additions?

---

## §偏離 (Deviations)

- **Decision 4 — BoardView scope fence**: Leader lifted the fence to permit
  shape (iii). Added `Packages/SudokuKit/Sources/SudokuUI/Board/BoardLoaderView.swift`
  as a thin async wrapper. `GameViewModel.swift` and `BoardView.swift` are
  unchanged.
- **AppComposition struct widened**: `AppComposition` grew from holding only
  `rootViewModel` to also exposing the 4 protocol deps (`puzzleProvider`,
  `persistence`, `gameCenter`, `telemetry`). Required so `SudokuApp.body`
  can pass them through to the new `RootView.init`. Existing `Mirror`-based
  assertions in `CompositionTests` only read `rootViewModel.gameCenter` /
  `.persistence` — unaffected.
- **Preview/tests composition** now constructs a `Telemetry(sinks: [])` and
  a `FakePuzzleProvider` for the new bag fields. No observable behavior
  change in `.preview()` / `.tests()` semantics.

---

## §驗證 (Verification)

### Build

```
cd Packages/SudokuKit && swift build
# Build complete! (3.48s) — 0 warnings
```

### Tests

```
cd Packages/SudokuKit && swift test
# Test run with 364 tests in 69 suites passed after 2.373 seconds.
```

No regression vs the 364/364 baseline carried in from PR #44.

### iOS xcodebuild

Sandbox blocks `xcodebuild` from this agent harness (permission denied).
Recorded as a verification gap — Leader to run `xcodebuild -workspace
Sudoku.xcworkspace -scheme Sudoku -destination 'generic/platform=iOS'
build` locally to confirm the App-target wiring against the new
`RootView.init` signature compiles cleanly.

### TODO sweep

`grep -rn "TODO\|FIXME\|XXX"` on:
- `Packages/SudokuKit/Sources/SudokuUI/Root/`
- `Packages/SudokuKit/Sources/SudokuUI/Board/BoardLoaderView.swift`
- `Packages/SudokuKit/Sources/AppComposition/`

Result: zero hits.

### Per-route smoke trace (Decision 6 — filled in)

For each push:

```
HomeView card tap / sidebar NavigationLink
  → HomeViewModel.select(_:)  (or NavigationLink value:)
  → path.append(mode.appRoute)
  → RootViewModel.path mutation via Binding
  → NavigationStackHost.NavigationStack(path: $path)
  → .navigationDestination(for: AppRoute.self)
  → RootView.destinationView(for:)  ⟵ NEW
```

Per case:
- `.home`            → `EmptyView()` (defensive; never pushed).
- `.daily`           → `DailyHubView(viewModel: DailyHubViewModel(provider:persistence:))`.
- `.practice`        → `PracticeHubView(viewModel: PracticeHubViewModel(provider:))`.
- `.board(id)`       → `BoardLoaderView(puzzleId:puzzleProvider:persistence:)` → `ProgressView` → `.task` calls `persistence.loadOrCreate` + `GameSession.restore(from:)` → `GameViewModel` (live) → `BoardView`.
- `.completion(id,s)`→ `CompletionView(viewModel: CompletionViewModel(puzzleId:elapsedSeconds:leaderboardId: LeaderboardIDs.id(for: .dailyEasy), gameCenter:))`.
- `.leaderboard(id)` → `LeaderboardView(viewModel: LeaderboardViewModel(leaderboardId:gameCenter:))`.
- `.settings`        → `SettingsView(viewModel: SettingsViewModel(persistence:))`.

### BoardLoaderView structure

- File: `Packages/SudokuKit/Sources/SudokuUI/Board/BoardLoaderView.swift`
- Line count: 110 lines (single State enum: `.loading | .loaded(GameViewModel) | .failed(String)`).
- Transitions:
  - mount → `.loading`
  - `.task(id: puzzleId)` → `load()` →
    - success → `.loaded(GameViewModel)` (live `init(identity:session:initialBoard:…persistence:)`)
    - throw → `.failed(reason)` with Retry button → re-runs `load()`
- Identity recovery: derives `PuzzleIdentity` from the `puzzleId` string
  shape (practice- prefix → `.practice`; suffix after last `-` → difficulty
  string). Snapshot's `puzzle.difficulty` remains authoritative inside
  `BoardView`'s header — the recovered identity is best-effort.
- No mutation to `GameViewModel.swift` / `BoardView.swift`.

### Per-file change summary

| File | Change |
|---|---|
| `Packages/SudokuKit/Sources/SudokuUI/Root/RootView.swift` | `init` grows 4 deps; `destination:` closure swapped from `{ _ in EmptyView() }` to inline `switch` over all 7 `AppRoute` cases. |
| `Packages/SudokuKit/Sources/SudokuUI/Board/BoardLoaderView.swift` | **NEW** — 110 lines, shape (iii) async wrapper. |
| `Packages/SudokuKit/Sources/AppComposition/AppComposition.swift` | Struct gains `puzzleProvider` / `persistence` / `gameCenter` / `telemetry` stored properties + matching init params. |
| `Packages/SudokuKit/Sources/AppComposition/Live.swift` | `AppComposition` ctor call passes the 4 already-built deps through. |
| `Packages/SudokuKit/Sources/AppComposition/Preview.swift` | Adds `FakePuzzleProvider()` + `Telemetry(sinks: [])` to the fake bag. |
| `App/SudokuApp.swift` | `RootView(...)` call updated to the 5-arg init. |
| `docs/design.md` (§How.1 DI Composition Root block) | Updated `AppComposition` struct sketch + `SudokuApp.body` snippet + added paragraph documenting inline-construction pattern and the `BoardLoaderView` exception; cross-link issues #15 / #34 / #45 / PR #33 / PR #44. |
| `docs/design.md` (§不在 v1 範圍) | New `### 導航` subsection with the `AppRoute.completion` carry-difficulty backlog item. |
| `Packages/SudokuKit/Tests/SudokuUITests/RootViewTests.swift` | 2 snapshot tests updated to construct `RootView` with the new 5-arg init; imports add `PuzzleStore` + `Telemetry`. |
| `meetings/2026-05-20_route-destination-wireup.impl-notes.md` | Status → COMPLETE; §偏離 + §驗證 filled in. |

### Test count delta

364 → 364 (unchanged; no new tests added by this IMPL — Leader to decide whether smoke tests for `BoardLoaderView` state transitions warrant a follow-up).
