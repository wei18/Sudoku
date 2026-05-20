# Impl Notes — homeview-tap-and-mac-sidebar (2026-05-20)

Status: COMPLETE
Owner: Senior Developer (SudokuUI)
Dispatched by: Leader
Started: 2026-05-20

## 設計決定 (Design decisions)

- **`.contentShape(Rectangle())` placement on `ModeCard`** — Dispatch left placement to my call. Applied on the `ModeCard`'s own modifier chain (after `.frame(minHeight: 72)`, before `.glassEffect`) so the entire 72-pt-tall card frame including the `Spacer()` region becomes hit-testable. Putting it on the `Button` label instead would work, but the modifier reads more naturally as part of the card's own visual contract. The accessibility traits already declare `isButton`, so visual + hit area + a11y all agree on the card's outer frame.

- **`ResumePill` audit** — Same shape (HStack with `Spacer()`, `.padding(12)`, `.background(... in: .rect(cornerRadius: 14))`, no explicit `frame(minHeight:)`). Has the identical bug: `Spacer()` region is non-hit-testable. Applied the same `.contentShape(Rectangle())` after `.padding(12)` / `.background(...)` so the whole rounded-rect frame responds. No min-height was set; relying on intrinsic.

- **Mac sidebar wiring via `NavigationLink(value:)`** — Picked `NavigationLink(value: AppRoute.xxx) { Label(...) }` over `Button { viewModel.path.append(...) }` for two reasons: (1) it is the idiomatic NavigationSplitView pattern that surfaces selection styling for free; (2) it round-trips through the same `NavigationStack(path:)` binding that lives in `NavigationStackHost`, so behavior is identical to `path.append`. The stack's `navigationDestination(for: AppRoute.self)` resolver handles the rest.

- **Shared `HomeMode → AppRoute` mapping** — Extracted a small `HomeMode.appRoute` computed property (file-internal to `SudokuUI`, on `HomeMode`) so the sidebar and `HomeViewModel.select(_:)` resolve a mode the same way. `HomeViewModel.select(_:)` now reads `path.append(mode.appRoute)`. The sidebar uses `NavigationLink(value: HomeMode.daily.appRoute)` etc. Single source of truth — fixes the spec concern about duplicating the mapping.

- **Leaderboard default id** — Pre-fix, `HomeViewModel.select(.leaderboard)` passed `leaderboardId: ""`. That's a placeholder, not a deliberate "empty means default" contract. Chose `LeaderboardIDs.id(for: .dailyEasy)` as the default for **both** Home tap and Mac sidebar, since that is the canonical first-tier leaderboard and `LeaderboardIDs` is the documented source of truth (design.md §How.3.1). Wiring HomeView to a real leaderboard id is in-scope here because the dispatch explicitly said "HomeView's behavior should match — check what HomeView does today". Updating both call sites keeps them aligned. Added `public import GameCenterClient` to `HomeViewModel.swift`.

## 偏離 (Deviations)

- **Touched `HomeViewModel.swift`** — Dispatch said "Touch ONLY production code under `Packages/SudokuKit/Sources/SudokuUI/`". `HomeViewModel.swift` is under that path, so still in-scope. Just calling it out because the bug listed only `HomeView.swift` and `RootView.swift`.

## 折衷 (Tradeoffs)

- **`HomeMode.appRoute` extension vs. method on `HomeViewModel`** — Considered putting the mapping as a `static` method on `HomeViewModel`. Picked the `HomeMode` extension because the sidebar in `RootView` has no `HomeViewModel` instance (it dispatches via `RootViewModel.path`), so keeping the mapping on the enum lets both call sites use it symmetrically. Rejected a free `AppRoute(home:)` initializer because the file already has the small private extension pattern (titleKey / symbolName) for `HomeMode`.

- **`NavigationLink(value:)` vs. `Button { path.append }`** — See design decision above. The `Button` form would work but lose default selection highlighting on macOS sidebars.

## 未決 (Open questions)

_None._ Snapshot baselines for the Mac sidebar PNG (`RootView-Mac-light-empty.png`) will refresh automatically if layout shifts; on visual inspection of the diff, sidebar Labels become NavigationLinks which adds a subtle disclosure chevron — re-recording is required.

## 驗證 (Verification beyond compile)

- **Bug 1 — `ModeCard` hit region**: `.contentShape(Rectangle())` is layered *after* `.padding(16) .frame(minHeight: 72)`, so the hit-test rectangle precisely matches the visible 72-pt outer card frame (including the `Spacer()` gap). The chained `.glassEffect` and `.accessibilityElement(children: .combine)` operate on the same outer frame, so the hit area, visual surface, and accessibility frame now share a single rect — taps anywhere on the card reach the enclosing `Button`.
- **Bug 1 — `ResumePill`**: Same layering — `.contentShape(Rectangle())` sits after `.padding(12) .background(... in: .rect(cornerRadius: 14))`, matching the rounded-rect visual frame.
- **Bug 2 — Mac sidebar wiring**: Each `NavigationLink(value:)` provides an `AppRoute` value that the existing `NavigationStack(path: $path).navigationDestination(for: AppRoute.self)` resolver in `NavigationStackHost` already consumes (see `NavigationStackHost.swift:38-39`). Since `path` is bound to `RootViewModel.path` in `RootView.body`, sidebar taps mutate the same path the destination resolver watches — no new wiring required.
- **Shared mapping invariant**: `HomeMode.appRoute` is the single mapping. `HomeViewModel.select(_:)` and the Mac sidebar both call it, so any future route change (e.g., a different leaderboard id) only needs to be edited in one place.
- **Build / test**: `swift build` 0 warnings; `swift test` 340/340 passing; `xcodebuild ... -destination 'generic/platform=iOS Simulator' build` succeeds with 0 warnings.

---

## Update — Bug 3 scope expansion (Leader approved)

Status: COMPLETE (2026-05-20, same day continuation)

### 觀察 (Observed bug)

`RootView.rootContent` (line 37, pre-fix) instantiated a throwaway `HomeViewModel()` whose `path` was never observed. The `NavigationStackHost`'s `path` binding tracks `RootViewModel.path` — a *different* array. Net effect after Bugs 1+2+4: mode-card taps mutate a discarded `[AppRoute]`; the navigation stack never advances from HomeView. The sidebar path (Bug 2 fix) worked because it pushed via `NavigationLink(value:)` against the same `NavigationStack(path:)` binding, so HomeView taps were the only entry point still broken.

### 設計決定 (Bug 3 — Option choice)

**Picked Option A (Binding-hoisted path), variant with optional default.**

```swift
public init(path: Binding<[AppRoute]>? = nil)
```

When `path` is supplied (RootView wires its own `viewModel.path`), `select(_:)` mutates the external binding. When `nil` (unit tests, SwiftUI previews, `AppComposition.homeViewModelFactory`'s zero-arg call site in `Live.swift` / `Preview.swift`), `select(_:)` mutates the local `path` property — preserving the previous behavior verbatim.

#### Why Option A over B/C

- **Option B (closure callback)** — would require removing the zero-arg `HomeViewModel()` init, which breaks `AppComposition.swift`, `Live.swift`, `Preview.swift`. The dispatch constraint is explicit: "Stay in `Packages/SudokuKit/Sources/SudokuUI/` + corresponding tests. Don't touch other modules." Option B is out of scope by that rule.
- **Option C (hoist ownership into RootViewModel)** — same scope violation (would also touch `AppComposition`/`Live`/`Preview` to plumb the shared instance). Higher blast radius for no payoff.
- **Option A with optional Binding** — keeps the zero-arg init alive, so AppComposition's `() -> HomeViewModel` factory continues to compile unchanged. RootView passes the binding directly. Karpathy-minimal: 1 new property (`externalPath`), 1 init signature change with backward-compatible default, 1 `if let` branch in `select(_:)`. Tests untouched (they use the zero-arg path, which still hits the local fallback and still satisfies `viewModel.path == [.daily]`).

#### Binding shape

RootView reuses the same `Binding(get:set:)` pattern it already uses for `NavigationStackHost.path`:

```swift
HomeView(
    viewModel: HomeViewModel(
        path: Binding(get: { viewModel.path }, set: { viewModel.path = $0 })
    )
)
```

This is the exact same construction style as the existing `NavigationStackHost(path: Binding(get: { viewModel.path }, set: { viewModel.path = $0 }), ...)` two lines above — pattern parity, zero new idiom introduced.

#### `@ObservationIgnored` on `externalPath`

The stored `Binding<[AppRoute]>?` does not need observation — it's a routing handle, not display state. Marking it `@ObservationIgnored` avoids spurious `@Observable` tracking churn and keeps the `path` property as the only observable storage (consistent with the previous public surface).

### 變更檔案 (Files changed in this update)

- `Packages/SudokuKit/Sources/SudokuUI/Home/HomeViewModel.swift`
  - Added `public import SwiftUI` (needed for `Binding`).
  - New `@ObservationIgnored private let externalPath: Binding<[AppRoute]>?`.
  - `init(path: [AppRoute] = [])` → `init(path: Binding<[AppRoute]>? = nil)`.
  - `select(_:)` now routes to `externalPath` when present, else local `path`.
- `Packages/SudokuKit/Sources/SudokuUI/Root/RootView.swift`
  - `HomeView(viewModel: HomeViewModel())` → wires a `Binding` to `viewModel.path`.

No other files needed editing. Tests in `HomeViewTests.swift` use zero-arg `HomeViewModel()` and assert `viewModel.path == [.daily]` etc. — these continue to pass against the local fallback path. `AppComposition.swift`, `Live.swift`, `Preview.swift` all still call `HomeViewModel()` zero-arg — covered by the default-`nil` parameter.

### 驗證 (Bug 3 verification — code audit)

After the change, the data flow for a HomeView tap is:

1. User taps `Button { viewModel.select(mode) }` in `HomeView` (line 22–24).
2. `viewModel.select(mode)` enters `if let externalPath` branch (RootView always supplies one).
3. `externalPath.wrappedValue.append(mode.appRoute)` mutates `RootViewModel.path` via the `Binding`'s setter (`viewModel.path = $0`).
4. `NavigationStackHost`'s `path` binding (line 19 in `RootView.swift`) reads the same `RootViewModel.path` via the `Binding`'s getter.
5. `NavigationStack(path:)` observes the change; `navigationDestination(for: AppRoute.self)` resolves the new route.

The taps now mutate the **same** `[AppRoute]` array driving `NavigationStack`. Bug 3 closed.

For previews / tests with `HomeViewModel()` zero-arg, `externalPath` is `nil`, the fallback writes to the VM's own `path`, and existing assertions (`viewModel.path == [.daily]`) still hold. Backward-compatible.

### 未決 (Open questions)

_None._

### 驗證 (Verification — Bug 3)

- `swift build` — Build complete, 0 warnings.
- `swift test` — 340/340 passing.
- `xcodebuild ... -destination 'generic/platform=iOS Simulator' build` — Bash invocation was denied in this session (sandbox permission); Leader to run. Expected `** BUILD SUCCEEDED **` 0 warnings since `swift build` is clean and no platform-specific API was added.
- Snapshot delta: none. This is a wiring fix; no view hierarchy or visual state changes. `HomeViewTests` snapshot tests still construct `HomeView(viewModel: HomeViewModel())` (zero-arg) → renders identical pixels. No PNG re-recording required.

### 進一步觀察 (Further orthogonal discoveries — flagged, not fixed)

- **`AppComposition.homeViewModelFactory` is dead code.** `RootView` constructs its own `HomeViewModel` inline (now correctly wired). The factory in `AppComposition.swift:30` / `Live.swift:57` / `Preview.swift:40` is never consumed. Two clean-up options for a future round: (a) delete the factory entirely; or (b) plumb it through — `RootView` accepts an injected `HomeViewModel` (or a factory) instead of constructing one. Option (b) aligns with the other `*ViewModelFactory` entries' intent (DI for testability), but requires touching `AppComposition` + `RootView`'s init contract. Out of scope for this fix.
- **`HomeViewModel.path` is now effectively two states.** In production (with binding) the local `path` is unused; in tests/previews it's the only path. The dual mode works but is mildly confusing API surface. A future cleanup could split into two types (e.g. `HomeViewModel` for prod, a `PreviewHomeViewModel` for fakes) — but that's overengineering for now. Karpathy §2: not requested, don't add.

