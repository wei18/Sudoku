# 07 — Leaderboard (Apple Native UI)

> **AS-BUILT NOTE (2026-07-05):** content verified accurate 2026-07-04;
> banner added for consistency with the rest of `docs/designs/`. Canonical
> flow spec: `docs/navigation-flows.md`.

## a. Decision

v1 uses Apple's native Game Center UI for full leaderboard browsing
(issue #49, 2026-05-20). The previously-planned custom SwiftUI
`LeaderboardView` has been retired (~400 lines of production + tests
deleted). The entry seam is the static helper:

```swift
GameCenterDashboard.present(leaderboardId: String?)
```

(Source: `Packages/SudokuKit/Sources/SudokuUI/Leaderboard/GameCenterDashboard.swift`.)

## b. Triggers

| Surface | Call | Effect |
|---|---|---|
| Home tab "Leaderboard" card | `GameCenterDashboard.present(leaderboardId: nil)` | Opens the full leaderboards listing — all 3 v1 boards (easy / medium / hard daily) shown in Apple's native dashboard |
| Mac sidebar "Leaderboard" row | `GameCenterDashboard.present(leaderboardId: nil)` | Same as Home card |
| CompletionView "View full leaderboard" button | `GameCenterDashboard.present(leaderboardId: viewModel.leaderboardId)` | Opens the dashboard focused on the just-solved difficulty's board |

## c. Native dashboard features (delegated to Apple)

Apple's GC dashboard ships with all the affordances that the retired
`LeaderboardView` had to implement manually:

- Friends / global scope toggle
- Time-range filter (today / week / all-time)
- Player profile drill-through (tap an entry → player profile sheet)
- AX3 vertical-stacked rows under Dynamic Type extended sizes
- Sign-in affordance when unauthenticated (`GKAccessPoint` shows a
  prompt; `GKGameCenterViewController` shows an inline sign-in CTA)
- Localizations matching the user's system language (Apple supplies
  these; only achievement / leaderboard *names* still ship via ASC
  metadata, see §e)

## d. CompletionView mini-slice (kept)

`CompletionView` still renders an embedded top-3 mini-slice on the
post-solve screen — that is a different affordance (immediate rank
feedback) and is **not** the full leaderboard. Its data source remains
`GameCenterClient.fetchLeaderboardSlice(.globalAllTime, limit: 3)`
(docs/v1/design.md §How.3.3 still defines this protocol method).

The "View full leaderboard" button below the mini-slice is the
deep-link into Apple's dashboard via the §b CompletionView trigger
above.

## e. API choice

`GameCenterDashboard` is a hybrid wrapper (see
`meetings/2026-05-20_native-gamecenter-switch.impl-notes.md` §設計決定
Decision 1 for full rationale):

- `leaderboardId == nil` → `GKAccessPoint.shared.trigger(state: .leaderboards)`.
  Cleanest path for the "open all leaderboards" entry. Cross-platform
  (iOS / macOS share the same `GKAccessPoint` shape).
- `leaderboardId != nil` → present `GKGameCenterViewController(leaderboardID:
  playerScope: .global, timeScope: .allTime)` modally on the active
  window. Required because `GameCenterViewControllerState.leaderboards`
  has no associated values for a focused leaderboard ID; the focused
  variant is the view-controller initializer instead.

Both paths bottom out in Apple's UIKit / AppKit view controller, so we
do not need a SwiftUI `UIViewControllerRepresentable` bridge — we reach
the active `UIWindowScene` (iOS) or `NSApplication.keyWindow` (macOS)
directly. Linux SwiftPM CI (pure-logic targets) collapses to a no-op
behind `#if canImport(GameKit)`.

## f. macOS unauthenticated UX (note-only, no special handling)

On macOS with the player not signed in to Game Center, the access-point
trigger shows Apple's standard sign-in prompt; the focused
`GKGameCenterViewController` shows an inline sign-in affordance.
No App-level handling is required.

## g. Foundations.md §2 exception

`SudokuUI` normally does not import `GameKit` — protocols (e.g.
`GameCenterClient`) keep the UI / logic layer testable + previewable.
`GameCenterDashboard.swift` is the lone exception: Apple's native UI
entry has no protocol-injectable seam (the framework *is* the UI), so
the file imports `GameKit` directly. The local file-scope import does
not contaminate the rest of SudokuUI's testability — all other Views
continue to inject via `any GameCenterClient`.

## h. Out of scope (v1)

- Embedded leaderboard preview in views other than CompletionView
  (e.g. a Home-tab summary widget). If product later wants this, the
  existing `fetchLeaderboardSlice` protocol method already covers it
  (see §d).
- Deep-link routing to a focused leaderboard via URL scheme / Universal
  Link. v1 has no such deep link; the absence of `AppRoute.leaderboard`
  is intentional. A future re-add would attach a side-effect handler
  rather than a stack push.
