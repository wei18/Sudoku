---
name: swiftui-interaction-footguns
description: Checklist of known SwiftUI interaction bugs that slipped past pure-code review (tap-target shrink, sidebar inert Labels, sizeClass on Mac, .task re-fire, theme tint propagation, NSHostingView env). Invoke automatically during Code Reviewer dispatch on any `.swift` file under `Sources/.../SudokuUI/` or any file matching `*View*.swift`, and whenever reviewing new SwiftUI View components, Button / NavigationLink / TabView / Form, or Mac NavigationSplitView variants.
---

# SwiftUI Interaction Footguns

A class of bugs that look fine in code but break at runtime. Phase 8 shipped two of these to v1 (issue #15). Sweep this checklist on every SwiftUI View review.

## When to invoke

- Reviewing any new or modified SwiftUI View
- Reviewing `Button` / `NavigationLink` / `TabView` / `Form` / `Menu`
- Reviewing Mac variants (`NavigationSplitView` / sidebar)
- After a macOS or iPad smoke test surfaces a tap or navigation bug
- Before declaring a Phase complete that ships new View code

## Checklist

### Tap target & hit-test

- `Button { } label: { LayoutWithSpacer }` `.buttonStyle(.plain)` → hit-test shrinks to drawn content; the Spacer-expanded area is **not** tappable. **Fix:** `.contentShape(Rectangle())` on the label's outermost container.
- Same trap for `NavigationLink`, `Menu`, and any custom interactive view with `.onTapGesture` + Spacer / `frame(maxWidth: .infinity)` / padding.
- Padding and `frame(maxWidth: .infinity)` enlarge the visual frame but do **not** automatically enlarge the hit region under `.plain`. When in doubt, add `.contentShape`.

### NavigationSplitView (Mac / iPad)

- Sidebar items must be `NavigationLink(value:)` or `Button` — a bare `Label` is non-interactive even if it visually looks like a row.
- iPhone compact size class should fall back to `NavigationStack`, not split. Snapshot tests for iPhone fixtures must force `.compact` (see next item).
- Selection binding pitfall: sidebar selection and detail's path must share the same source of truth, or selection won't navigate.

### `horizontalSizeClass` on Mac

- `@Environment(\.horizontalSizeClass)` returns `.regular` for every macOS-hosted SwiftUI view — even iPhone-shaped fixtures inside `NSHostingView`. iPhone snapshot tests must inject `.compact` explicitly via `.environment(\.horizontalSizeClass, .compact)`.

### Async state load timing

- `.task { await viewModel.bootstrap() }` re-fires on every view mount / identity change. If a test pre-seeds VM state, the task overwrites it back to `.loading`. **Fix:** `hasBootstrapped` latch in the VM + a separate `retry()` method for user-driven retry.
- `.task(id:)` cancels and restarts when `id` changes — confirm that's the intent.

### Dynamic Type / AX3

- For "AX3 stacks vertical" patterns, `@Environment(\.dynamicTypeSize) >= .accessibility3` + conditional `VStack` vs `HStack` is enough. No custom `Layout` needed.
- Timer/control text scales with Dynamic Type by default; keep fixed-size for grids and critical regions (e.g., 9×9 board uses fixed cell metrics).

### Theme propagation to SwiftUI system controls

- `Picker`, `Button(.borderedProminent)`, `ProgressView`, `Toggle`, `Stepper` etc. follow `.tint` / `.accentColor`. The project's `theme.accent.primary` does **not** auto-propagate — apply `.tint(theme.accent.primary.resolved)` on each system control or at a high-enough ancestor.

### `NSHostingView` snapshot environment

- `colorScheme` override needs `host.appearance = NSAppearance(named: ...)` on macOS — SwiftUI's `.preferredColorScheme` does not propagate through `NSHostingView`.
- `locale` and `horizontalSizeClass` overrides must be set on the View **before** wrapping in `NSHostingView`; mutating after host creation is unreliable.

### Button / Picker styling

- `.labelsHidden()` on `Picker` when the label is provided externally (avoids duplicated label rendering on Mac).
- `.buttonStyle(.borderedProminent)` honours `.tint` only on iOS 17+ / macOS 14+; verify deployment target before relying on it.

### Touch target minimums

- Apple HIG: 44×44pt minimum. Buttons that look smaller due to compact text + tight padding fail accessibility audit even if visually balanced.

### View identity & `if/else`

- Branching between `if A { ViewA } else { ViewB }` gives the two branches distinct identities; state (`@State`, `.task` latches, focus) resets on switch. Use a single view with conditional modifiers when identity preservation matters.

### `@Observable` + `@Bindable`

- Reading an `@Observable` model via `let vm = …` does not establish a binding scope; passing `vm` into a child that needs `@Bindable var vm` requires the child to redeclare with `@Bindable`. Forgetting this silently breaks two-way bindings (TextField, Toggle).

## How to apply

1. Before approving any PR touching SwiftUI Views, sweep the checklist mentally.
2. For each item that *could* apply, grep / re-read the diff for the trigger pattern.
3. If a footgun is present, flag it with a concrete fix (cite the bullet).

## Sightings (real bugs that shipped past review)

- **Issue #15 Bug 1** — HomeView ModeCard: `Button { } label: { card-with-Spacer }` `.buttonStyle(.plain)` shrank tap target to drawn content. Caught by macOS smoke test, **not** by Code Reviewer. Fix: `.contentShape(Rectangle())`.
- **Issue #15 Bug 2** — Mac `NavigationSplitView` sidebar items were bare `Label`s with no `NavigationLink` / `Button`, so clicking did nothing. Same review-blind-spot path.
- (Future: append as more are caught.)

## Related skills

- `subagent-review-cycles` — Code Reviewer dispatch brief should explicitly name this skill when reviewing SwiftUI Views.
- `swiftui-expert-skill` — broader domain skill (Instruments traces, hang/hitch profiling); different scope.
