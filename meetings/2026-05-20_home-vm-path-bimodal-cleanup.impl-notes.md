# `HomeViewModel` path bimodality cleanup — impl notes

Branch: `chore/home-vm-path-bimodal-cleanup`
Scope: code-only (no git / gh / commit / push).
Status: **COMPLETE**

## 設計決定

**Option chosen: Clarify (recommended in the brief).**

Rename the stored fallback to `localPath` (private), keep `externalPath:
Binding<[AppRoute]>?` as the injected one, and expose a single public
computed `path` that reads/writes through whichever mode is active.

Why this option over the other two:

1. **Most surgical at the call site.** `RootView` keeps the exact same
   `HomeViewModel(path: Binding(get:set:))` constructor it has today.
   `HomeView.select(_:)` callers see no API change. Tests keep reading
   `viewModel.path == [.daily]` verbatim. Zero ripple beyond the VM file.

2. **Split init (Option B) inflates surface for no benefit.** Two named
   factories (`.live(path:)` / `.preview()`) plus an internal enum-state
   would replace one `init` + one default-nil param. That's net more API
   to document and one more thing for future readers to learn — exactly
   the opposite of a clarity cleanup.

3. **Collapse (Option C) makes tests uglier.** Every test would have to
   either build a throwaway `@State` host or pass `.constant([])` (which
   silently swallows writes — confusing failure mode if a future test
   asserts on `viewModel.path` after `.select(.daily)`). Trading "two
   private storage slots in the VM" for "every preview/test site grows a
   binding harness" is a bad trade.

The bimodality doesn't disappear — it can't, because the navigation
source-of-truth genuinely lives in two places (RootView's path vs.
preview/test stub). What changes is that the bimodality is now
**encapsulated**: callers see one `path` property; the routing between
external binding and local fallback is a private detail named to make
the intent obvious (`localPath` clearly signals "preview/test only").

## 變更摘要 (per-file)

| File | Change |
|------|--------|
| `Packages/SudokuKit/Sources/SudokuUI/Home/HomeViewModel.swift` | (1) Renamed stored `public var path` → `private var localPath`. (2) Added public computed `var path: [AppRoute]` with get/set that routes through `externalPath` when present else `localPath`. (3) Simplified `select(_:)` from an `if let externalPath { ... } else { ... }` branch to a single `path.append(mode.appRoute)` — the computed setter now owns the routing. (4) Updated the doc comment on `localPath` to clarify it is the preview/test-only fallback. |
| `Packages/SudokuKit/Sources/SudokuUI/Home/HomeView.swift` | No change. View never read `viewModel.path` and only calls `viewModel.select(_:)`, whose signature is unchanged. |
| `Packages/SudokuKit/Sources/SudokuUI/Root/RootView.swift` | No change. Call site `HomeViewModel(path: Binding(get:set:))` is preserved verbatim. |
| `Packages/SudokuKit/Tests/SudokuUITests/HomeViewTests.swift` | No change. Tests read `viewModel.path == [.daily]` etc.; the public read path is preserved (now via computed getter). |

Net diff: one file modified.

## 驗證

- `swift build` → **Build complete!** (Swift 6 strict mode, 0 warnings).
- `swift test` → **Test run with 363 tests in 69 suites passed**.
  - Pre-flight expected count: 363. Actual: 363. **Test count delta: 0.**
- TODO sweep on `Packages/SudokuKit/Sources/SudokuUI/Home/` + `Packages/SudokuKit/Sources/SudokuUI/Root/`:

  ```
  $ grep -rn -E "TODO|FIXME|XXX|HACK" \
      Packages/SudokuKit/Sources/SudokuUI/Home/ \
      Packages/SudokuKit/Sources/SudokuUI/Root/
  (no output)
  ```

  Zero hits in scope.

## §未決

None.

A note for future readers (not blocking this change): the computed
`path` getter on an `@Observable` class reads `externalPath?.wrappedValue`,
which is a `Binding`, not an `@Observable`-tracked stored property. If a
future SwiftUI view tries to observe `homeViewModel.path` changes that
originate from a *third party* mutating the upstream `RootViewModel.path`,
that observation will not fire through this VM. Today no view does this —
`HomeView` does not read `path`, and `RootView` reads its own
`RootViewModel.path` directly — so the design is sound. If that ever
changes, the cleanest fix is to hoist observation to the upstream owner
(which already happens in `RootView` today), not to add a manual relay
here. Flagging for awareness only; no action required.
