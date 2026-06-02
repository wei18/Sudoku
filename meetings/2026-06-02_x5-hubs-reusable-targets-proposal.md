# X5 Hubs — Reusable Targets Proposal (overrides prior skip)

**Status**: PROPOSAL_DRAFT (Track B, revisited)
**Author**: Developer
**Date**: 2026-06-02
**Supersedes**: `meetings/2026-06-02_x5-hubs-proposal.md` (Option C — skip)
**Binding rubric**: `feedback/reusable-targets-over-duplication.md` + `feedback/minesweeper-mirrors-sudoku.md`

---

## TL;DR — Recommendation

**Option A (two narrow shells): `DailyHubShellView<Card, EmptyOverlay>` + `PracticeHubShellView<Filter, CTA>`** living in `GameShellKit/Sources/GameShellUI/`. Both shells own only the X4-style chrome triple (`.frame.infinity` + `.background(Color)` + `.navigationTitle`) **plus** the one structural primitive that genuinely repeats per hub kind:

- Daily shell: the 1-or-3-column `LazyVGrid` inside a `ScrollView`, parameterised on a `Card` view-builder and on a `state: HubLoadState` enum (idle / loading / loaded / empty / failed) provided by the caller's view model. Empty / failed overlays are caller-provided builders so each game keeps its own copy.
- Practice shell: the static `VStack(alignment: .leading, spacing: 24)` with two slots — `filter` (the game's difficulty Picker) and `cta` (the game's draw card). No state machine baked in; the caller's CTA view owns its own loading affordance.

Theme background is injected as a plain `Color` parameter (the caller resolves `theme.surface.background.resolved` before handing it in), mirroring X4's pattern of letting the caller resolve theme tokens at the boundary. Navigation path injection stays in caller VMs.

Why Option A wins over B/C/D: it captures the **two** non-trivial repeating primitives (the responsive grid and the `VStack(24)+padding(16)` skeleton) without inventing a hub taxonomy that doesn't exist. Option B (single `HubScaffold`) only catches the chrome triple — too thin to justify a target boundary that already costs a sentinel test per shell. Option C (protocol-driven) bakes Sudoku's `DailyHubState` / `PracticeHubLoadingState` shapes into the public surface, which fails the "if the abstraction blocks the second consumer, fix the abstraction" rule in `reusable-targets-over-duplication.md`.

---

## 1. What exists in Sudoku today (cite-only)

Prior audit covered this in depth; this section is a one-screen recap to anchor the abstraction discussion.

### 1.1 Daily hub
- View: `Packages/SudokuKit/Sources/SudokuUI/Daily/DailyHubView.swift:18-87` — root chrome triple on lines 20–22; `switch viewModel.state` over `DailyHubState` (idle/loading/loaded/exhausted/failed); happy path renders `ScrollView { LazyVGrid(columns: 1 or 3) { DailyPuzzleCard … } }` (lines 62-75). `columns` adapts on `horizontalSizeClass` (lines 77-86).
- ViewModel: `Packages/SudokuKit/Sources/SudokuUI/Daily/DailyHubViewModel.swift:32-135` — `DailyHubState` enum lines 22-28; `DailyCard` struct lines 14-20; `path` binding pattern lines 38-57.

### 1.2 Practice hub
- View: `Packages/SudokuKit/Sources/SudokuUI/Practice/PracticeHubView.swift:18-50` — root is `VStack(alignment: .leading, spacing: 24)` with `.padding(16)` + chrome triple on lines 46-49. Contains an inline `"Difficulty"` `Text` section header (line 20), segmented `Picker` lines 24-30 with `.glassEffect(.regular, in: .rect(cornerRadius: 12))` line 40, and `drawCard` lines 60-93 (a `VStack` + `Button` wrapped in `.glassEffect(.regular, in: .rect(cornerRadius: 16))`).
- ViewModel: `Packages/SudokuKit/Sources/SudokuUI/Practice/PracticeHubViewModel.swift:25-111` — `PracticeHubLoadingState` lines 13-21; 100 ms shimmer threshold line 58.

### 1.3 Route factory call sites
`Packages/SudokuKit/Sources/SudokuUI/Navigation/RouteFactory.swift:81-108` — no shell in between today; both views are fully constructed by the factory and handed straight to the navigation destination.

---

## 2. Projected Minesweeper equivalents

Per `minesweeper-mirrors-sudoku.md`, both hubs must exist. Today only a proto-Practice ships:

- `Packages/MinesweeperKit/Sources/MinesweeperUI/NewGameView.swift:21-57` — a `VStack(spacing: 24)` with a segmented `Picker` over `MinesweeperEngine.Difficulty.allCases` (Beginner / Intermediate / Expert), a board-summary line, and a `Button("Start")`. No theme background (no MS theme tokens yet), no state machine (path push is synchronous because there's no async generator).

### 2.1 Projected MS Practice (mirror of Sudoku Practice)
- `VStack(alignment: .leading, spacing: 24)` with `"Difficulty"` heading + segmented `Picker` over MS `Difficulty` + a `drawCard`-shaped CTA. The CTA can either push immediately (current `NewGameView` shape) or run through a tiny `PracticeStarter` if MS later gains an async "warm the seed" pass. Either way the **outer scaffold** — picker + draw card + padding + chrome — is byte-identical to Sudoku Practice in structure.
- MS does not have a 100 ms shimmer rule today and probably never will (no async generator); the shimmer/redacted hint is a property of the caller's CTA, not the scaffold. This is why the Practice shell should NOT bake the loading state in — pushing it into the CTA builder is what lets MS opt out cleanly.

### 2.2 Projected MS Daily
- "Today's 3 boards seeded by date" by analogy. Likely shape: 3 `DailyMineCard`s in the same 1-or-3-col `LazyVGrid`, each card showing difficulty chip + a tiny `MiniBoardStrip`-equivalent (probably a row of mine icons or a tiny preview grid) + completion checkmark. Same `idle/loading/loaded/empty/failed` outer state machine — even the names map cleanly: `exhausted` becomes "no boards seeded for today" (same UX shape, different prose).
- The state-machine shape is the part that genuinely repeats; the card content is where games diverge. That's the natural cut.

---

## 3. Recommended abstraction shape (Option A)

### 3.1 `DailyHubShellView`

```swift
// GameShellKit/Sources/GameShellUI/DailyHubShellView.swift
public enum HubLoadState<Item: Sendable & Equatable>: Sendable, Equatable {
    case idle
    case loading
    case loaded([Item])
    case empty   // Sudoku.exhausted / MS.no-daily-seed
    case failed(String)
}

public struct DailyHubShellView<Item, Card, Failure>: View
    where Item: Sendable & Equatable & Identifiable, Card: View, Failure: View
{
    private let title: LocalizedStringKey
    private let background: Color
    private let state: HubLoadState<Item>
    private let card: (Item) -> Card
    private let failure: (String) -> Failure
    private let onItemTap: (Item) -> Void

    public init(
        title: LocalizedStringKey,
        background: Color,
        state: HubLoadState<Item>,
        @ViewBuilder card: @escaping (Item) -> Card,
        @ViewBuilder failure: @escaping (String) -> Failure,
        onItemTap: @escaping (Item) -> Void
    ) { /* … */ }

    public var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(background)
            .navigationTitle(title)
    }

    @ViewBuilder private var content: some View {
        switch state {
        case .idle, .loading: ProgressView().controlSize(.large)
        case .loaded(let items): grid(items)
        case .empty:             Color.clear
        case .failed(let reason): failure(reason)
        }
    }

    @ViewBuilder private func grid(_ items: [Item]) -> some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(items) { item in
                    Button { onItemTap(item) } label: { card(item) }
                        .buttonStyle(.plain)
                }
            }
            .padding(16)
        }
    }

    @Environment(\.horizontalSizeClass) private var sizeClass
    private var columns: [GridItem] {
        sizeClass == .regular
            ? [.init(.flexible()), .init(.flexible()), .init(.flexible())]
            : [.init(.flexible())]
    }
}
```

**Caller wires the `.task { bootstrap() }` + `.alert(...)` themselves** because:
- `.task` ownership belongs to the VM (`DailyHubViewModel.bootstrap()`), not the shell — keeping the shell out of side-effect modifiers is the same X4 principle (SettingsShellView.swift:34-47 owns no `.task` / `.confirmationDialog`).
- The Sudoku exhausted-alert prose ("Try a different difficulty, or come back tomorrow.") is Sudoku-specific. MS would likely show a different message or none. Letting callers add `.alert(...)` on top of the shell is one extra line per caller and zero coupling.

### 3.2 `PracticeHubShellView`

```swift
// GameShellKit/Sources/GameShellUI/PracticeHubShellView.swift
public struct PracticeHubShellView<Filter: View, CTA: View>: View {
    private let title: LocalizedStringKey
    private let background: Color
    private let filterHeader: LocalizedStringKey
    private let filter: () -> Filter
    private let cta: () -> CTA

    public init(
        title: LocalizedStringKey,
        background: Color,
        filterHeader: LocalizedStringKey,
        @ViewBuilder filter: @escaping () -> Filter,
        @ViewBuilder cta: @escaping () -> CTA
    ) { /* … */ }

    public var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text(filterHeader)
                .font(.title3.weight(.semibold))
            filter()
            cta()
            Spacer()
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(background)
        .navigationTitle(title)
    }
}
```

**Note**: the `.foregroundStyle(theme.text.primary.resolved)` on the header (PracticeHubView.swift:22) is **dropped from the shell**. SwiftUI's default `.primary` foreground matches `theme.text.primary` semantically on both platforms; if a game's theme demands a non-system primary color, the caller can wrap the shell's content with `.foregroundStyle(...)` at the boundary or pass a styled header into a future overload. This is the one cosmetic concession the shell makes to stay theme-agnostic. **Snapshot impact below addresses this**.

### 3.3 Sudoku wiring (after extraction)

```swift
// SudokuKit/SudokuUI/Daily/DailyHubView.swift (revised)
public var body: some View {
    DailyHubShellView(
        title: "Daily",
        background: theme.surface.background.resolved,
        state: liftedState,                       // maps DailyHubState → HubLoadState<DailyCard>
        card: { DailyPuzzleCard(card: $0) },
        failure: { reason in
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(theme.status.warning.resolved)
                Text(reason).font(.caption)
                    .foregroundStyle(theme.text.secondary.resolved)
            }
        },
        onItemTap: viewModel.cardTapped
    )
    .task { await viewModel.bootstrap() }
    .alert("Couldn't generate today's puzzle", isPresented: …) { … }
}

private var liftedState: HubLoadState<DailyCard> {
    switch viewModel.state {
    case .idle: .idle
    case .loading: .loading
    case .loaded(let c): .loaded(c)
    case .exhausted: .empty
    case .failed(let r): .failed(r)
    }
}
```

Practice mirrors the same pattern: caller passes its `Picker` as the filter slot and its existing `drawCard` (with all the loadingState / shimmer / glassEffect bits intact) as the CTA slot.

---

## 4. Tradeoff matrix

| Dimension | A (two narrow shells) | B (one HubScaffold chrome-only) | C (protocol-driven) | D (hybrid) |
|---|---|---|---|---|
| Code reuse | Medium — grid logic + chrome triple + VStack(24)+padding(16) skeleton | Low — chrome triple only (~3 lines) | High in theory, but locks shape | n/a |
| Karpathy §2 simplicity | Good — two shells, each captures one repeating primitive | Good — minimal, but borderline trivial | Bad — protocol + container is more code than the duplicate it removes | n/a |
| X4 chrome-only precedent fidelity | High — same "chrome + one genuine layout primitive" cut | Highest — pure chrome, no layout | Low — bakes state machine into public surface | n/a |
| Forced abstraction risk | Low — neither shell forces a state shape; Daily lifts to a generic `HubLoadState`, Practice has no state at all | Lowest | High — `HubViewModel` protocol forces MS to declare a state taxonomy it may not need | n/a |
| Sudoku byte-identicality | At-risk on Practice header foregroundStyle (see §6); Daily likely identical | Highest — `.background + .navigationTitle` collapse only | At-risk; protocol forcing changes view structure | n/a |
| Minesweeper integration friction | Low — MS supplies its own cards/filter/CTA, no shape constraints | Low but provides little value | High — MS must implement protocol even for trivial cases | n/a |
| Sentinel test feasibility | Direct — instantiate each shell with a `Text("sentinel")` card / filter / CTA; mirrors `SettingsShellViewGenericityTests` 1:1 | Trivial | Awkward — must build a fake conformer for the protocol | n/a |

**D**: I considered a hybrid where `DailyHubShellView` exists but Practice stays in caller (since its structural reuse is just `VStack(24)+padding(16)+chrome`). Rejected because: (a) the practice scaffold IS the structural primitive MS will copy verbatim from `NewGameView`, so extracting it is the smaller delta long-term; (b) one-shell-extracted, one-not is asymmetric and harder to explain in code review.

---

## 5. Recommended PR plan (Option A)

### 5.1 New files in `Packages/GameShellKit/`
- `Sources/GameShellUI/DailyHubShellView.swift` — ~75 LoC (struct + `HubLoadState` enum + grid helper + columns env).
- `Sources/GameShellUI/PracticeHubShellView.swift` — ~35 LoC (struct + body).
- `Tests/GameShellUITests/DailyHubShellViewGenericityTests.swift` — ~30 LoC (instantiate with `Text("sentinel")` card + sentinel failure overlay, mirror SettingsShellViewGenericityTests.swift:18-29 pattern).
- `Tests/GameShellUITests/PracticeHubShellViewGenericityTests.swift` — ~25 LoC (instantiate with `Text("filter")` + `Text("cta")` slots).

Estimated GameShellKit delta: **+165 LoC**.

### 5.2 Modified Sudoku files
- `Packages/SudokuKit/Sources/SudokuUI/Daily/DailyHubView.swift` — body collapses ~20 lines (the state switch + grid plumbing moves into the shell call); `liftedState` adapter adds ~8 lines. Net ~-12 LoC. **`DailyPuzzleCard` / `MiniBoardStrip` stay put** (Sudoku-specific). The exhausted `.alert` stays on the caller per §3.1.
- `Packages/SudokuKit/Sources/SudokuUI/Practice/PracticeHubView.swift` — body collapses ~10 lines (VStack scaffold + chrome + header `Text` move into shell), with the Picker passed as the `filter` slot and `drawCard` passed as the `cta` slot. `drawCard` itself stays untouched (its `.glassEffect` and state-bound copy are Sudoku-specific). Net ~-8 LoC.
- `Package.swift` (SudokuKit): add `GameShellUI` as a dependency of `SudokuUI` (already added by X1-X4; no-op).

Estimated SudokuKit delta: **-20 LoC modified, no files added/deleted**.

### 5.3 New Minesweeper files (compile-and-render stubs)
- `Packages/MinesweeperKit/Sources/MinesweeperUI/DailyHubView.swift` — `DailyHubShellView` wrapped, with a `MinesweeperDailyCard` stub (chip + tiny mine-row strip + checkmark). State source: an empty `HubLoadState.empty` placeholder so it compiles and the empty branch renders. Wires MS's `AppRoute` for taps. ~60 LoC.
- `Packages/MinesweeperKit/Sources/MinesweeperUI/PracticeHubView.swift` — `PracticeHubShellView` wrapped around the existing `NewGameView`'s Picker + Start button extracted into `filter` + `cta` slots. Lets us delete or wrap `NewGameView` later (out of scope for this PR — keep both temporarily). ~50 LoC.
- These are intentionally shallow stubs: the goal of X5 is to prove the GameShellKit shells fit a second consumer; full MS Daily/Practice product work (date-seeding, persistence-backed completion, telemetry) is follow-up phases.
- No MS test files in this PR — the genericity sentinels in GameShellKitTests already pin the shells; full MS hub testing belongs to MS feature PRs.

Estimated MinesweeperKit delta: **+110 LoC**.

### 5.4 Total: **~+255 LoC added, ~20 LoC modified**

Well above the 50-LoC mandatory CR threshold; Code Reviewer dispatch is required per `feedback-code-reviewer-rule-is-or-not-and.md`.

### 5.5 Sentinel test sketch

```swift
// DailyHubShellViewGenericityTests.swift
@Suite("GameShellUI — DailyHubShellView stays generic")
struct DailyHubShellViewGenericityTests {
    struct SentinelItem: Sendable, Equatable, Identifiable { let id: String }

    @Test @MainActor func instantiatesWithNonSudokuItems() {
        let shell = DailyHubShellView(
            title: "Sentinel",
            background: .clear,
            state: HubLoadState<SentinelItem>.loaded([SentinelItem(id: "a")]),
            card: { item in Text(item.id) },
            failure: { reason in Text(reason) },
            onItemTap: { _ in }
        )
        _ = shell
    }
}
```

`PracticeHubShellViewGenericityTests` mirrors the SettingsShellView sentinel directly.

---

## 6. Snapshot rebaseline forecast — **honest answer: partial yes**

This is the headline risk and I'm not going to downplay it.

### 6.1 `DailyHubViewTests` (3 snapshots) — **expected GREEN (byte-identical)**
The shell preserves modifier order (`.frame.infinity` → `.background` → `.navigationTitle`), the same `LazyVGrid(columns:1or3, spacing:12)` inside a `ScrollView`, and the same `.padding(16)`. The `Button(...){ DailyPuzzleCard(...) }.buttonStyle(.plain)` wrapper is also preserved. The state-enum lift (`DailyHubState → HubLoadState<DailyCard>`) is a value-level translation that produces an identical view tree per branch. Failure overlay is caller-provided and unchanged.
- **Risk knob**: if `@ViewBuilder card:` is inlined slightly differently by the Swift compiler (e.g. an extra `_ConditionalContent` wrapper) the rendered output is still pixel-identical because we're handing the same `DailyPuzzleCard` in.
- **Verdict**: I expect 3/3 green. If one fails, it'll be the `.failed` snapshot if I forgot to mirror the icon+caption VStack exactly via the caller's `failure:` builder — that's recoverable inside the caller without touching the shell.

### 6.2 `PracticeHubViewTests` (5 snapshots) — **expected MIXED: 1 likely re-baseline**
Four of five (idle / drawingQuiet / drawingShimmer / drawn) preserve byte-identicality because the `drawCard` view is handed to the shell as-is and the Picker is also handed as-is; the outer VStack(24) + padding(16) + chrome are preserved.

**The one casualty**: the `"Difficulty"` header `Text` is moved into the shell (§3.2) and the shell does NOT call `.foregroundStyle(theme.text.primary.resolved)` on it (currently PracticeHubView.swift:22). This is a deliberate theme-decoupling — on iOS SwiftUI's default `.primary` matches the system label color, which is what `theme.text.primary` resolves to via `SudokuTheme`. **In practice this is the same color**, so the snapshot diff may be a no-op. But if `theme.text.primary.resolved` is anything other than the system primary (e.g. a custom warm-paper tone), the header pixel will change.

- **Verdict**: 4/5 green, 1 at risk. If the header snapshot re-baselines, that's acceptable and well-documented (it's the same theme decoupling X4 made for SettingsShellView). If the user requires byte-identicality, the alternative is to accept a small `foregroundStyle: Color` parameter on `PracticeHubShellView` for the header — adds 1 line, removes the risk. I'd prefer to defer that param until the snapshot proves it's needed (Karpathy §2).

### 6.3 X4 broke 0 snapshots — is that promise broken here?
Yes, partially, on Practice. The X4 cut had no inline content (only `Form { sections }.formStyle.navigationTitle`); X5 must touch one inline `Text` because Practice's section header is structurally inside the outer scaffold, not inside the caller's content slot. The honest trade is: 0 risk if we add the foreground param; ~1 snapshot risk if we don't.

---

## 7. Open questions for Leader

1. **Practice header foreground param — accept the 1-snapshot risk, or add `headerForeground: Color = .primary` to the shell from day 1?** My preference: accept the risk (Karpathy §2), re-baseline if it actually trips, add the param if a third game needs a third color. Leader's call.
2. **MS Daily product definition.** The proposal assumes MS Daily = "today's 3 boards by date" mirroring Sudoku. If the MS product direction is "no Daily" or "Daily means something else", the Daily shell extraction loses one of its two consumers. Per `minesweeper-mirrors-sudoku.md` the default is "MS has the same shape" — I've planned to that, but flagging if there's a product-side override.
3. **`HubLoadState<Item>` empty-vs-failed semantics for MS.** Sudoku's `.exhausted` triggers an `.alert`; MS's equivalent ("no seed for today") may want an inline empty state instead. The shell renders `.empty` as `Color.clear` (mirroring Sudoku's "alert handles it" pattern), but MS may want a real empty view. Two options: (a) overload `.empty` with a caller-provided builder like `failure`; (b) leave it as `Color.clear` and let MS overlay its own. I'd add the empty builder when MS asks for it, not now.
4. **Should the `path: Binding<[Route]>?` injection pattern (duplicated across `HomeViewModel`, `DailyHubViewModel`, `PracticeHubViewModel`, `NewGameView`) be lifted in this PR or a later micro-phase?** Carry-over from the prior X5 audit's open question §4. My answer: **not in this PR** — it's orthogonal to hub shells and would balloon the diff.
5. **Stub MS hubs in this PR vs. a follow-up?** Proposal §5.3 includes shallow stubs. Alternative: ship X5 with only `GameShellKit` additions + Sudoku rewire, and let MS Daily/Practice land in their own phases. Pro of stubs: proves the shells fit a second consumer in-PR (the whole point of `reusable-targets-over-duplication.md`). Pro of split: smaller diff, cleaner review. I'd default to including the stubs — without a second concrete consumer in-PR, X5 is structurally the same as the rejected Option C.

---

## Appendix A — Files read for this proposal

- `meetings/2026-06-02_x5-hubs-proposal.md` (prior skip recommendation; built on, not repeated)
- `Packages/SudokuKit/Sources/SudokuUI/Daily/DailyHubView.swift` (157 LoC)
- `Packages/SudokuKit/Sources/SudokuUI/Daily/DailyHubViewModel.swift` (136 LoC)
- `Packages/SudokuKit/Sources/SudokuUI/Practice/PracticeHubView.swift` (134 LoC)
- `Packages/SudokuKit/Sources/SudokuUI/Practice/PracticeHubViewModel.swift` (111 LoC)
- `Packages/GameShellKit/Sources/GameShellUI/SettingsShellView.swift` (48 LoC — chrome-only precedent)
- `Packages/GameShellKit/Tests/GameShellUITests/SettingsShellViewGenericityTests.swift` (29 LoC — sentinel pattern)
- `Packages/GameShellKit/Package.swift`
- `Packages/MinesweeperKit/Sources/MinesweeperUI/NewGameView.swift` (89 LoC — proto-Practice)
- `Packages/SudokuKit/Tests/SudokuUITests/DailyHubViewTests.swift` (snapshot suite header)
- Memory: `feedback/minesweeper-mirrors-sudoku.md`, `feedback/reusable-targets-over-duplication.md`, `feedback/code-reviewer-rule-is-or-not-and.md`
