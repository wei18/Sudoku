# X5 Hubs Extraction — Proposal

**Status**: PROPOSAL_DRAFT (Track B)
**Author**: Developer
**Date**: 2026-06-02
**Predecessors**: X1 (#224), X2 (#226), X3 (#232), X4 (#239)

---

## TL;DR — Recommendation

**Option C: Skip X5 as a standalone phase.** Fold the relevant bit (a one-line `.background(theme.surface.background.resolved)` + `.navigationTitle(...)` pair on each hub root) into X6 only if Minesweeper's own hub shapes turn out to share it. The Daily and Practice hubs are **structurally different views** — they share no abstractable container — so there is no chrome-only shell worth extracting, and a `HubSection` protocol is speculative until Minesweeper has at least one concrete hub to compare against.

This matches the X4 precedent ("only the genuinely-shared `Form` triple was extracted; section taxonomy stayed in caller") taken to its logical conclusion: for X5 the genuinely-shared surface is empty.

---

## 1. What exists today

### 1.1 Daily hub

**Files**:
- `Packages/SudokuKit/Sources/SudokuUI/Daily/DailyHubView.swift` (157 LoC)
- `Packages/SudokuKit/Sources/SudokuUI/Daily/DailyHubViewModel.swift` (136 LoC)

**View shape** (`DailyHubView.swift:18-87`):

```
body
└── content (switch on viewModel.state)
    ├── .idle / .loading    → ProgressView (large)
    ├── .loaded(cards)      → ScrollView { LazyVGrid(columns: 1 or 3) { DailyPuzzleCard … } }
    ├── .exhausted          → Color.clear (alert handles it)
    └── .failed(reason)     → VStack { warning icon + caption }
    .frame(maxWidth:.infinity, maxHeight:.infinity)
    .background(theme.surface.background.resolved)
    .navigationTitle("Daily")
    .task { await viewModel.bootstrap() }
    .alert("Couldn't generate today's puzzle", isPresented: …)
```

**State machine** (`DailyHubViewModel.swift:22-28`):
`.idle → .loading → (.loaded([DailyCard]) | .exhausted | .failed(String))`

**Domain coupling**:
- `DailyCard` wraps `PuzzleEnvelope` + `isCompleted: Bool` (DailyHubViewModel.swift:14-20).
- `DailyPuzzleCard` (DailyHubView.swift:89-143) renders a Sudoku difficulty chip + `MiniBoardStrip` (a 9-cell Sudoku-shaped placeholder, DailyHubView.swift:145-157).
- `difficultyTint` switches on Sudoku `Difficulty` enum (`.easy / .medium / .hard`) — DailyHubView.swift:136-142.
- `bootstrap()` calls `provider.fetchDailyTrio(date:)` and `persistence.fetchCompletedDailyIds(for:)` — both Sudoku-shaped APIs (DailyHubViewModel.swift:87-89).
- Path injection: `Binding<[AppRoute]>?` with `cardTapped` appending `.board(puzzleId:)` (DailyHubViewModel.swift:133-135).

### 1.2 Practice hub

**Files**:
- `Packages/SudokuKit/Sources/SudokuUI/Practice/PracticeHubView.swift` (134 LoC)
- `Packages/SudokuKit/Sources/SudokuUI/Practice/PracticeHubViewModel.swift` (111 LoC)

**View shape** (`PracticeHubView.swift:18-50`):

```
body
└── VStack(alignment:.leading, spacing: 24)
    ├── Text("Difficulty") (title3.semibold)
    ├── Picker(.segmented, selection: difficultyBinding)
    │       .tint(tint(for: viewModel.difficulty))
    │       .glassEffect(.regular, in: .rect(cornerRadius: 12))
    ├── drawCard
    │   └── VStack { headline + hintRow + Button("Draw new puzzle") }
    │       .glassEffect(.regular, in: .rect(cornerRadius: 16))
    └── Spacer()
    .padding(16)
    .frame(maxWidth:.infinity, maxHeight:.infinity, alignment: .top)
    .background(theme.surface.background.resolved)
    .navigationTitle("Practice")
```

**State machine** (`PracticeHubViewModel.swift:13-21`):
`.idle → .drawingQuiet (<100ms) → .drawingShimmer (≥100ms) → (.drawn(PuzzleEnvelope) | .failed(String))`

**Domain coupling**:
- Difficulty Picker iterates Sudoku `Difficulty.allCases` (PracticeHubView.swift:24-29).
- `hintRow` formats `\(difficulty.rawValue.capitalized) · \(envelope.identity.puzzleId)` — Sudoku envelope identity (PracticeHubView.swift:108-110).
- `drawPuzzle()` calls `provider.fetchPracticePool(difficulty:)` (PracticeHubViewModel.swift:93).
- 100 ms shimmer threshold is Sudoku-specific UX from `docs/design-system.md §Loading & Placeholder`.
- Path injection mirrors Daily: `Binding<[AppRoute]>?` + `playTapped` appending `.board(puzzleId:)`.

### 1.3 How `LiveRouteFactory` routes to them

`Packages/SudokuKit/Sources/SudokuUI/Navigation/RouteFactory.swift:81-97`:

```swift
case .daily:
    return AnyView(
        DailyHubView(
            viewModel: DailyHubViewModel(
                provider: puzzleProvider,
                persistence: persistence,
                errorReporter: errorReporter,
                path: path
            )
        )
    )
case .practice:
    return AnyView(
        PracticeHubView(
            viewModel: PracticeHubViewModel(provider: puzzleProvider, path: path)
        )
    )
```

No shell wrapper between `LiveRouteFactory` and the two views; the factory hands a fully-configured `DailyHubView` / `PracticeHubView` directly to the navigation destination.

### 1.4 Side-by-side: where is the "hub" shape?

| Aspect              | DailyHubView                                  | PracticeHubView                                       |
|---------------------|-----------------------------------------------|-------------------------------------------------------|
| Top-level container | `switch viewModel.state` (5 branches)         | Single `VStack(alignment: .leading, spacing: 24)`     |
| Layout primitive    | `ScrollView { LazyVGrid }` for happy path     | Static vertical stack (no scrolling, no list)         |
| Header              | None (only `.navigationTitle`)                | Inline `Text("Difficulty")` as section heading        |
| Filter / picker     | None                                          | Segmented `Picker` over `Difficulty`                  |
| Item rendering      | `DailyPuzzleCard` grid (1 or 3 cols)          | Single "draw card" affordance                         |
| Async surface       | `.task { bootstrap() }` + `.alert(...)`       | `Task { drawPuzzle(); playTapped() }` on Button       |
| Loading affordance  | `ProgressView` (large) at root                | `.redacted(reason: .placeholder)` inline shimmer      |
| Failure affordance  | Inline VStack with icon + caption             | Inline Text in `hintRow`                              |
| Path push trigger   | Card tap → `.board(puzzleId:)`                | Draw + tap CTA → `.board(puzzleId:)`                  |
| Common modifiers    | `.frame(maxWidth/maxHeight:.infinity) + .background(theme.surface.background.resolved) + .navigationTitle(...)` | same triple |

**Common surface = three modifiers.** Even the "fill the detail pane and tint the background" pair is theme-token-coupled to Sudoku's `theme.surface.background.resolved`. The `.navigationTitle` is already provided by SwiftUI; not worth a shell.

There is **no "hub" pattern** — the two files are different shapes that happen to both live behind a sidebar tab.

---

## 2. What's generic vs Sudoku-specific (per construct)

| Construct                                       | File:line                                      | Generic? | Notes |
|-------------------------------------------------|-----------------------------------------------|----------|-------|
| `.frame(maxWidth/maxHeight: .infinity)` fill    | DailyHubView.swift:20 / PracticeHubView.swift:47 | Yes (SwiftUI built-in) | No extraction value |
| `.background(theme.surface.background.resolved)` | DailyHubView.swift:21 / PracticeHubView.swift:48 | Sudoku theme | Minesweeper will likely want its own background |
| `.navigationTitle("Daily" / "Practice")`        | DailyHubView.swift:22 / PracticeHubView.swift:49 | Yes (SwiftUI built-in) | No extraction value |
| `DailyHubState` enum                            | DailyHubViewModel.swift:22-28                 | Sudoku-specific | `.exhausted` is daily-trio specific |
| `DailyCard` struct                              | DailyHubViewModel.swift:14-20                 | Sudoku-specific | Wraps `PuzzleEnvelope` |
| `DailyPuzzleCard` view                          | DailyHubView.swift:89-143                     | Sudoku-specific | `MiniBoardStrip` + difficulty tint |
| `MiniBoardStrip` view                           | DailyHubView.swift:145-157                    | Sudoku-specific | 9-cell row, Sudoku shape |
| LazyVGrid 1-or-3 columns                        | DailyHubView.swift:77-86                      | Borderline | Could be reused; but Minesweeper hub may not need a grid at all |
| `PracticeHubLoadingState` enum                  | PracticeHubViewModel.swift:13-21              | Sudoku-specific | 100 ms shimmer threshold is Sudoku design-system rule |
| Segmented `Picker` over `Difficulty.allCases`   | PracticeHubView.swift:24-29                   | Sudoku-specific | Minesweeper has different difficulty taxonomy (Beginner/Intermediate/Expert + custom WxHxMines) |
| Shimmer timing (`shimmerDelayNanos: 100_000_000`)| PracticeHubViewModel.swift:58                | Sudoku UX rule | Per `docs/design-system.md` |
| `path: Binding<[AppRoute]>?` injection pattern  | both ViewModels                               | Sudoku-typed; pattern is generic | Mirrors `HomeViewModel`; not unique to hubs |
| `cardTapped` / `playTapped` → `.board(puzzleId:)`| both ViewModels                              | Sudoku route | Minesweeper would push its own `.board` case |

**Sum:** the only constructs that meet the "would Minesweeper want to reuse this verbatim" test are SwiftUI built-ins. There is no candidate construct that is both (a) non-trivial and (b) game-agnostic.

---

## 3. Recommended abstraction shape

**Option C: Skip X5.** Justification, against the three options:

### Why not Option A (chrome-only shell)?

A `HubShellView<Content: View>` that wraps:

```swift
content()
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(/* what color? */)
    .navigationTitle(title)
```

…runs into three problems:
1. **No shared chrome to extract.** The `.frame.infinity` is a SwiftUI one-liner; `.navigationTitle` is already SwiftUI. The only non-trivial line is the theme background, which is Sudoku-typed.
2. **Background color isn't shared.** Sudoku reads `theme.surface.background.resolved` from its `Environment(\.theme)`. Minesweeper's theme tokens have not been designed; forcing it through a `Color` parameter or a `ThemeProtocol` injection is exactly the speculative coupling X4 rejected.
3. **No structural reuse.** Unlike `SettingsShellView`'s shared `Form.formStyle(.grouped)` decision (which had a real macOS behavior fix baked in — SettingsShellView.swift:43-44), the hub backgrounds have no platform-quirk gravity holding them together. Two separate one-liner modifiers in the two callers is not duplication worth fixing.

A `DailyHubShellView` / `PracticeHubShellView` pair (one shell each) would be even worse — they'd be two single-call-site abstractions, which is the textbook anti-pattern Karpathy guideline §2 calls out.

### Why not Option B (chrome + section protocol)?

A `HubSection` / `HubItem` protocol so Minesweeper can plug its own card / picker / list into a shared layout engine:

1. **Speculative generalization.** Minesweeper has zero hub code today (`Packages/MinesweeperKit` is a placeholder per session log §Minesweeper foundation). Designing a `HubSection` protocol without a second concrete shape is exactly the "no abstractions for single-use code" violation karpathy-guidelines §2 warns against.
2. **The two existing shapes don't agree.** Daily = state-machine-driven grid; Practice = static stack with inline async surface. A protocol that fits both would either (a) be a `some View` wrapper that adds nothing or (b) bake in Sudoku's specific state taxonomy (`DailyHubState`, `PracticeHubLoadingState`) and force Minesweeper to mimic it.
3. **swiftpm-modularization principle**: a module boundary justifies its existence by having ≥ 2 consumers that benefit. `HubSection` would have 1 consumer (Sudoku) and 1 placeholder waiting (Minesweeper) — and the placeholder hasn't said it wants this shape.

### Why Option C wins

- **Karpathy §2 (Simplicity First)** — minimum code to enable Minesweeper reuse is zero code, because the two hubs share nothing reusable.
- **Karpathy §1 (Think Before Coding)** — surfacing the tradeoff: extracting now means picking a hub shape Minesweeper hasn't asked for; deferring means one extra `.background(...)` + `.navigationTitle(...)` per hub later, which is cheaper than wrong-abstraction debt.
- **swiftpm-modularization** — `GameShellKit` should grow only when a second consumer concretely needs the API. Minesweeper's hub UI doesn't exist yet (session log §"Next-up code work" — `MinesweeperCoreKit/GameState` is the next priority, not Minesweeper hubs).
- **Pattern reuse without extraction** — the `path: Binding<[Route]>?` injection pattern from both ViewModels (DailyHubViewModel.swift:38-57, PracticeHubViewModel.swift:32-51) is the genuinely reusable artifact, but it's already a one-screen Swift idiom that can be copy-pasted into MinesweeperHubViewModel without a `GameShellKit` symbol. Adding a `GenericHubViewModel<Route>` base class to wrap 20 lines of binding plumbing would be more code than the duplication it removes.

### When to revisit

When Minesweeper introduces its first hub view, compare it to Daily and Practice. If the shapes converge on a real pattern (e.g. all three become "filter picker + draw button" or all three become "card grid"), extract then with concrete evidence. Until then, copy-paste once is cheaper than a wrong abstraction.

---

## 4. PR plan

**N/A.** Recommendation is Option C — no PR.

If the Leader overrides to Option A (chrome-only `HubShellView`), the plan would be:

- **LoC delta**: +~30 (new `HubShellView.swift` + sentinel test) / -~4 (the three modifiers in each hub) → net +~26. Below the 50 LoC mandatory-CR threshold per `feedback-code-reviewer-threshold.md`, but X-series convention has been routing to CR anyway.
- **Files created**: `Packages/GameShellKit/Sources/GameShellUI/HubShellView.swift`, `Packages/GameShellKit/Tests/GameShellUITests/HubShellViewGenericityTests.swift`.
- **Files modified**: `Packages/SudokuKit/Sources/SudokuUI/Daily/DailyHubView.swift` (lines 20-22 collapsed into shell call), `Packages/SudokuKit/Sources/SudokuUI/Practice/PracticeHubView.swift` (lines 47-49 collapsed into shell call).
- **Files deleted**: none.
- **Snapshot risk**: `Packages/SudokuKit/Tests/SudokuUITests/DailyHubViewTests.swift` (3 snapshots) and `PracticeHubViewTests.swift` (5 snapshots) — if the shell injects any layout difference (even a different modifier order can change SwiftUI's hit-testing), all 8 snapshots need re-baseline. **This is the headline risk** — and is itself an argument against extraction since byte-identicality was a core X1-X4 promise.
- **Sentinel test**: mirror `SettingsShellViewGenericityTests` pattern (Packages/GameShellKit/Tests/GameShellUITests/SettingsShellViewGenericityTests.swift:18-29) — instantiate `HubShellView` with `Text("sentinel content")` to pin genericity.

---

## 5. Open questions for Leader

1. **Is "skip X5 and go to X6" acceptable, or does the phase numbering need a placeholder PR?** Methodology has no rule requiring sequential phase numbers; suggest just relabeling X6 → X5 in the backlog.
2. **Does the Leader have any signal from the Minesweeper UI direction (issue / spec) that suggests a specific hub shape?** If Minesweeper plans a "preset list + custom-size form" hub, neither Daily nor Practice's current shape will apply — confirming Option C. If it plans a "card grid like Daily", that's one data point but still not two consumers.
3. **Snapshot byte-identicality**: X1-X4 each kept Sudoku snapshots untouched. Is that promise expected to extend through X5/X6, or are we allowed to re-baseline once we hit a hub that genuinely needs to refactor? (Affects how aggressively we can refactor when the time comes.)
4. **Should the `path: Binding<[Route]>?` injection pattern (currently duplicated in `HomeViewModel`, `DailyHubViewModel`, `PracticeHubViewModel`, and presumably forthcoming Minesweeper VMs) be extracted as a property-wrapper or base class?** This is the **one** genuinely-shared piece of code across all hubs/home — but it's a 20-line pattern and would be its own micro-phase, not a hub-shell extraction. Flagging for backlog if Leader agrees.

---

## Appendix A — Files read

- `Packages/SudokuKit/Sources/SudokuUI/Daily/DailyHubView.swift` (157 lines)
- `Packages/SudokuKit/Sources/SudokuUI/Daily/DailyHubViewModel.swift` (136 lines)
- `Packages/SudokuKit/Sources/SudokuUI/Practice/PracticeHubView.swift` (134 lines)
- `Packages/SudokuKit/Sources/SudokuUI/Practice/PracticeHubViewModel.swift` (111 lines)
- `Packages/SudokuKit/Sources/SudokuUI/Navigation/RouteFactory.swift` (133 lines)
- `Packages/SudokuKit/Sources/SudokuUI/Navigation/AppRoute.swift` (22 lines)
- `Packages/GameShellKit/Sources/GameShellUI/NavigationStackHost.swift`
- `Packages/GameShellKit/Sources/GameShellUI/RootShellView.swift`
- `Packages/GameShellKit/Sources/GameShellUI/SettingsShellView.swift`
- `Packages/GameShellKit/Sources/GameShellUI/SidebarItem.swift`
- `Packages/GameShellKit/Tests/GameShellUITests/SettingsShellViewGenericityTests.swift`
- `Packages/GameShellKit/Tests/GameShellUITests/RootShellViewGenericityTests.swift`
- `meetings/2026-06-02_minesweeper-foundation-sprint.md`
- Cross-reference grep for `DailyHubView` / `PracticeHubView` / `*HubViewModel` consumers — single production call site each (`LiveRouteFactory`), plus existing snapshot test suites in `SudokuUITests`.
