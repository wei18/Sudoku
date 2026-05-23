# macOS Sidebar Navigation — Inconsistent Tap Fix

Date: 2026-05-23
Scope: `Packages/SudokuKit/Sources/SudokuUI/Root/RootView.swift`

## Problem

User report: "macOS tab bar 上的 buttons 跟 home page 裡面的 buttons 點擊後的行為應該要相同，但有時候卻沒反應". NavigationSplitView left sidebar (Daily / Practice / Leaderboard / Settings) sometimes did not push the destination when clicked.

## Root cause

`sidebarPlaceholder` used `NavigationLink(value: AppRoute.daily)` etc. inside the sidebar's `List`. The matching `.navigationDestination(for: AppRoute.self)` lives inside the detail pane's `NavigationStack` (`NavigationStackHost.swift:39`). On macOS `NavigationSplitView`, the sidebar and detail panes are sibling scopes — value-based `NavigationLink` walks ancestors to find a destination registry and the cross-pane resolution behaved inconsistently.

`HomeView` mode cards do not exhibit this because they live inside the detail pane scope and mutate `viewModel.path` directly (`HomeViewModel.select`).

## Fix

Mirror HomeView's pattern in the sidebar: plain `Button` whose action directly appends to `viewModel.path`. The `Binding` passed into `NavigationStackHost` is the single source of truth, so mutation from the sidebar deterministically drives the detail stack's push.

- `AppRoute` is `Hashable` (implies `Equatable`).
- Dedupe guard: **no**. HomeView appends unconditionally too; duplicate-push behaviour matches existing convention and is harmless (user-perceived as normal stack growth).
- Leaderboard remains a modal side-effect (`GameCenterDashboard.present()`) — unchanged.
- Extracted `sidebarRow(_:systemImage:action:)` helper to keep the list call-site declarative.

## Tests added

None. The bug surface is a SwiftUI `Button` action closure inside a `View`; without ViewInspector there is no testable seam. The existing `snapshotEmptyStateMacLight` test continues to cover sidebar rendering. Behavior parity is implicit via the same `viewModel.path.append(...)` call already exercised by `HomeViewTests.selectDailyAppendsDailyRoute` et al.

## Verify

- `swift build` (SudokuKit package) — Build complete.
- `swift test --filter "RootView"` — 5 / 5 passed.
- `tuist generate --no-open` — success.
- `xcodebuild ... -destination 'platform=macOS' build` — `** BUILD SUCCEEDED **`.
- `xcodebuild ... -destination 'generic/platform=iOS' build` — `** BUILD SUCCEEDED **`.

## §未決

- Selection highlight (active route tinted with `theme.accent.primary`) deferred — not part of the bug fix scope. Would require plumbing `viewModel.path.last` into a `selection` binding on `List`, which conflicts with the path-stack model. Punt to a follow-up if user requests visual parity with iOS tab-bar selected state.
