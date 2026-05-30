# macos-navigation-and-settings-primitives

Status: COMPLETE
Branch: fix/197-settings-rows-unify-primitives
Worktree: /Users/zw/GitHub/Wei18/Sudoku-197b
Date: 2026-05-30
Dispatcher: Leader

## 任務 scope — TWO independent fixes bundled

### Fix A: macOS navigation broken in Daily + Practice (gameplay blocker)

**Symptom** (user-reported via screenshot):
- Daily hub: tapping a difficulty card does nothing — no navigation into a board
- Practice hub: tapping "Draw new puzzle" once shows the puzzle ID below the button (`Easy · practice-CXMDJDR01Z0RF-easy`), but subsequent taps re-fetch instead of navigating

**Root cause** (two-part):

1. **Path binding not propagated**: `RouteFactory.swift:96, 106` construct `DailyHubViewModel` and `PracticeHubViewModel` WITHOUT passing a path binding. Both VMs have their own internal `var path: [AppRoute] = []` which nothing observes — the real `NavigationStack` only watches `RootViewModel.path`. So mutations to the inner paths are silently dropped.

   The working precedent is `HomeViewModel` (`HomeViewModel.swift:24-46`): stores `externalPath: Binding<[AppRoute]>?` and exposes a `path` computed property that routes reads/writes through `externalPath` when present.

2. **PracticeHubView never calls `playTapped()`**: `PracticeHubView.swift:68-73` button action only calls `viewModel.drawPuzzle()`. There's no second affordance to call `viewModel.playTapped()`. Even with Fix A.1 the user would still need a way to invoke `playTapped()`.

**Fix A scope** (~50-70 LOC, 6 files):
- `PracticeHubViewModel.swift`: adopt HomeViewModel's `externalPath` pattern. Optional `Binding<[AppRoute]>?` init param.
- `DailyHubViewModel.swift`: same.
- `RouteFactory.swift` protocol: add `path: Binding<[AppRoute]>?` param to `view(for:)`. Update LiveRouteFactory + any mock fixtures.
- `RootView.swift` destination closure (line 56): `routeFactory.view(for: route, path: $viewModel.path)`.
- `PracticeHubView.swift` button: chain `await viewModel.drawPuzzle(); viewModel.playTapped()` so a single tap drafts + plays. Alternative: state-aware label. **Decision in §設計決定 below.**
- Tests: RouteFactory mocks, ViewModel ctor calls.

### Fix B: macOS Settings page row layout still inconsistent (cosmetic, post-#205)

**Symptom** (user-reported via screenshot):
- Purchases section: pill rows ✓ (correct, this is the working precedent)
- About section: "About" header text inline with icon column, `Version 1.0.0` / `Generator v1` cramped, NO pill backgrounds
- Storage section: "Storage" header collapsed, "Clear cache" button shrinks to compact-width

`.formStyle(.grouped)` from #205 wasn't enough — it gives Purchases (Button + HStack label primitive) the pill treatment, but doesn't affect `LabeledContent` (About rows) or `Button { Label }` without HStack-Spacer (Storage Clear cache).

**Fix B scope** (~20-30 LOC, 1 file):
- `SettingsView.swift`: replace About rows' `LabeledContent { Text } label: { Label }` with the same `HStack { Image + Text + Spacer + Text }` primitive Purchases uses (wrap in `Button { } label: ...` only if interactive; About rows are static so use plain HStack + `.frame(maxWidth: .infinity)` so the grouped form gives them the pill background).
- `SettingsView.swift`: Storage section's `Button(role: .destructive) { } label: { Label }` wrap label in `HStack { Label; Spacer }` so the button stretches full-width.

### Out of scope (file as separate follow-up issue)

- **macOS snapshot harness gap**: NSHostingView-based snapshot tests don't reproduce real macOS Form rendering, so they couldn't catch Fix B. The "synthesized host" gap was already acknowledged in issue #181 (closed) and #197 body. Real fix requires an NSWindow-based snapshot harness — separate scope, larger effort. **File as new issue with these screenshots as evidence.**

## 依賴文件
- docs/methodology.md §派發契約 (items 6, 8, 10, 11, 12)
- HomeViewModel pattern: `Packages/SudokuKit/Sources/SudokuUI/Home/HomeViewModel.swift:24-46`
- HomeView path injection: `Packages/SudokuKit/Sources/SudokuUI/Root/RootView.swift:72-79`
- Current broken state evidence: user's two screenshots (settings + practice)

## 設計決定

1. **`path:` parameter optional + default `nil`** in `RouteFactory.view(for:path:)`. Two motivations:
   - Existing `RouteFactoryTests` call `view(for: .home)`, `view(for: .daily)`, … without a binding. Making `path` non-optional would force every test to pass `path: nil` or a stub. Solution: keep the protocol requirement explicit (`func view(for:path:) -> AnyView`) but provide an `extension RouteFactory { view(for:) }` convenience that forwards `nil`. Test call sites unchanged; signature still discoverable in the protocol.
   - Mirrors the `Binding<[AppRoute]>? = nil` pattern already established by `HomeViewModel.init(path:)` — both VMs (Daily, Practice) now take an optional binding so previews / unit tests construct them with no path argument.

2. **`externalPath` storage on Daily + Practice VMs literally mirrors HomeViewModel**: same `private var localPath: [AppRoute] = []` fallback, same `@ObservationIgnored private let externalPath: Binding<[AppRoute]>?`, same get/set routing in the `path` computed property. Goal was zero-novelty — a future reader who knows HomeViewModel reads these as identical patterns.

3. **PracticeHubView button chains `drawPuzzle()` → `playTapped()` instead of state-aware label**. `playTapped()` is already a guarded no-op when state is not `.drawn`, so chaining is safe on `.failed` (the user stays on the hub with the failure hint). A state-aware "Draw / Play" two-label button would force a second tap, contradicting the spec's "single tap drafts the puzzle and navigates into the board".

4. **About rows extracted to `AboutRow` helper** rather than inline `HStack` × 2 in `SettingsView.body`. Repetition was small (2 rows), but the helper makes the icon-left / label / spacer / value-right primitive name-able (matches the implicit shape of `RemoveAdsRow`/`RestorePurchasesRow`), so future rows in About don't drift back to `LabeledContent`.

5. **Storage's Clear-cache button wraps Label in `HStack { Label; Spacer }`** instead of converting to the AboutRow primitive — the button must keep its `role: .destructive` semantics and its disclosure-style action, so it stays a `Button { ... } label:`; the Spacer just stretches the label content so the grouped form gives it pill background.

## 偏離 spec

None — both Fix A and Fix B landed at the file paths and shapes the dispatch prompt specified.

## 折衷

- **`AboutRow` uses `theme.accent.primary.resolved` for the icon tint** (matches Purchases section icons). Original `LabeledContent` flavor used `.foregroundStyle(.secondary)` on the whole Label. The new shape reads as "this row is a settings entry" rather than "this row is greyed-out informational" — a small visual lift that the spec implicitly endorsed by asking us to match the Purchases section.
- **Snapshot baselines for SettingsView re-recorded (6 PNGs)**. The NSHostingView-synthesized harness still doesn't reproduce real macOS Form pill rendering (impl-notes already acknowledged this as out-of-scope), but the iPhone + synthesized-Mac diffs are still real visual changes (the AboutRow primitive renders differently from LabeledContent even under the synthesized host). Re-recording was unavoidable; the baselines now reflect the unified shape.

## 未決

None — all 7 verification steps green:
1. `swift build` — Build complete!
2. `swift test --filter PracticeHubView` — 9 tests, 2 suites passed
3. `swift test --filter DailyHubView` — 7 tests, 2 suites passed
4. `swift test --filter NavigationStackHost` — 0 matches (no suite of that name exists; no regression)
5. `swift test --filter SettingsView` — 10 tests, 2 suites passed (after baseline re-record)
6. `swift test --filter RouteFactory` — 7 tests, 2 suites passed
7. `git diff --stat HEAD` — 6 source files + 6 baseline PNGs + impl-notes only; no scope creep

## Files changed
| File | + | − | Note |
|---|---|---|---|
| `Packages/SudokuKit/Sources/SudokuUI/Daily/DailyHubViewModel.swift` | ~25 | ~3 | externalPath pattern + init `path:` param |
| `Packages/SudokuKit/Sources/SudokuUI/Practice/PracticeHubViewModel.swift` | ~25 | ~3 | externalPath pattern + init `path:` param |
| `Packages/SudokuKit/Sources/SudokuUI/Navigation/RouteFactory.swift` | ~20 | ~5 | protocol now `view(for:path:)`, LiveRouteFactory forwards `path` into Daily/Practice VM ctors, extension keeps zero-arg convenience for tests |
| `Packages/SudokuKit/Sources/SudokuUI/Root/RootView.swift` | ~6 | ~1 | destination closure passes `path: $viewModel.path`-equivalent binding |
| `Packages/SudokuKit/Sources/SudokuUI/Practice/PracticeHubView.swift` | ~10 | ~1 | button action chains `drawPuzzle` then `playTapped` |
| `Packages/SudokuKit/Sources/SudokuUI/Settings/SettingsView.swift` | ~30 | ~14 | About rows → `AboutRow` HStack primitive; Storage Clear-cache Label wrapped in `HStack { ; Spacer }` for full-width pill |
| `Packages/SudokuKit/Tests/SudokuUITests/__Snapshots__/SettingsViewTests/*.png` | (6 files re-recorded) | | reflects unified About + Storage primitives |

**No mock RouteFactory exists in tests** — only `LiveRouteFactory` is used (via `makeFactory()` in RouteFactoryTests, RootViewTests, AppCompositionTests). All test call sites of `view(for: route)` continue to compile via the protocol extension's zero-arg convenience overload.

## Verification
- [ ] `swift build` clean across the SudokuKit package
- [ ] `swift test --filter SudokuUITests` passes locally
- [ ] `swift test --filter NavigationStackHostTests`, `HomeViewTests`, `DailyHubViewTests`, `PracticeHubViewTests` (or whatever exists) — find and run all tests that touch path / navigation
- [ ] **Manual run on real macOS**: build + Cmd+R on `Sudoku` scheme. Tap Daily → click difficulty card → verify navigation to BoardLoaderView. Tap Practice → click "Draw new puzzle" → verify navigation to BoardLoaderView. Open Settings → verify About + Storage rows have pill backgrounds matching Purchases.
- [ ] **Manual run on iOS Simulator**: verify navigation unchanged (regression check).
