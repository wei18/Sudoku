# 2026-05-19 — Phase 8 Part 1 (SudokuUI: Theme + Navigation + Hubs)

Session continuation of `ae54f5ea-6b89-4f59-9d9f-cafb8dff08f6`.
Mode: AI Collaboration Mode (Leader + 1 Developer subagent dispatch, background).

## Goal

Execute Phase 8 **Part 1** (steps 8.1–8.6): Theme protocol + DefaultTheme tokens, AppRoute + NavigationStackHost, RootView with auth `.task`, HomeView with Liquid Glass mode cards, DailyHubView with `.exhausted` alert, PracticeHubView with shimmer placeholder. Deferred Part 2 (8.7–8.11) due to size.

## Decisions

1. **Theme color construction**: `Color(.sRGB, red:, green:, blue:, opacity:)` from `0xRRGGBB` integers. Light/dark resolution via a tiny `UIColor(dynamicProvider:)` / `NSColor(name:dynamicProvider:)` bridge inside `Color(light:dark:)`. System honors `@Environment(\.colorScheme)` at render time — one `Color` value re-renders correctly in both light + dark snapshots without View-level branching.
2. **No `@unchecked Sendable` wrappers in production**. Three friction points hit during 8.5–8.6:
   - `FakePersistence.fetchCompletedDailyIds(for: Date)` — `public import Foundation` needed under `InternalImportsByDefault` because `Date` parameter is public.
   - `DailyHubViewTests.fixedDate` `static let` on `@MainActor`-isolated `@Suite` — marked `nonisolated(unsafe) private static let` (literal `Date`, no mutation).
   - `PracticeHubViewModel.drawPuzzle()` shimmer Task — added explicit `@MainActor` on inner `Task { ... }` closure + widened test margins (shimmer 50ms / fetch 800ms / observation 400ms) to survive Swift Testing's parallel scheduler.
3. **Snapshot infrastructure** in `SnapshotConfig.swift`: `hostingView(_:size:)` helper wrapping `NSHostingView`. Canonical sizes iPhone 393×852, Mac 900×600. Snapshot suite ran clean twice (record + diff stability check).
4. **`.glassEffect()` works on macOS 26 SDK** as designed — no SDK-feature workaround needed.
5. **Package.swift edit**: `exclude: ["__Snapshots__"]` for `SudokuUITests` (otherwise SwiftPM treats PNG dir as buildable resources). No new dep additions — SudokuUI already declared deps on GameState/PuzzleStore/Persistence/GameCenterClient/Telemetry from Phase 1.3.

## Rejected alternatives

- **`UIColor(red:green:blue:alpha:)` literal construction** for the static theme side: rejected for the dynamic-provider approach which handles light/dark in one Color value.
- **Hand-rolling a shimmer animation with `withAnimation`**: rejected — `.redacted(reason: .placeholder)` provides system-native shimmer per `design-system.md §Loading & Placeholder`.
- **Snapshot tests on full View hierarchies via SwiftUI Inspector**: rejected — `NSHostingView` rendering is faster and matches actual rasterization.

## Subagent dispatch

| Step | Commit | New tests | New PNGs |
|---|---|---|---|
| 8.1 Theme + DefaultTheme + design-system tokens | `b615a44` | 6 | 0 |
| 8.2 AppRoute + NavigationStackHost (compact/regular split) | `86fc15d` | 3 | 0 |
| 8.3 RootView + RootViewModel (auth .task, resume banner) | `cd234c2` | 5 (3 behavior + 2 snapshot) | 2 |
| 8.4 HomeView + ModeCard (Liquid Glass) | `cdea2b9` | 5 (3 behavior + 2 snapshot) | 2 |
| 8.5 DailyHubView + DailyHubViewModel (.exhausted alert) | `96aaeb1` | 6 (3 behavior + 3 snapshot) | 3 |
| 8.6 PracticeHubView + shimmer (>100ms threshold) | `485e3c6` | 7 (4 behavior + 3 snapshot) | 3 |
| chore: SudokuUITests Package.swift exclude __Snapshots__ | `99f1a6f` | 0 | 0 |

**Total Part 1: 32 new tests, 10 new PNG baselines. 248 → 280, 0 warnings Swift 6 strict + complete concurrency + InternalImportsByDefault.**

## Phase 8 Part 2 readiness flagged by subagent

- **BoardView (8.7)** is the heaviest step. Protocol surfaces ready: `GameSession` / `GameSessionSnapshot` (Phase 3), `PersistenceProtocol.loadOrCreate` (Phase 5), `FakeClock` (Phase 3 testing helpers). Suggestion: GameViewModel holds `(snapshot, identity)` pair so deep-links don't re-derive `puzzleId`.
- **Difficulty has only 3 cases (no Expert)**. PracticeHubView's 4-segment Picker mockup in `04-practice-hub.md` is decorative — Part 1's actual PracticeHubView uses `Difficulty.allCases` (3).
- **Locale variants for BoardView**: ja / ko / zh-TW must be embedded in the 12-snapshot matrix; pattern already established (Part 1's environment overrides).
- **Time-based UI must inject `FakeClock`**: pattern surfaced by Part 1's shimmer flakiness. BoardView elapsed-time UI must bind to `GameSession.elapsedSeconds` (already `Clock`-injectable in Phase 3).
- **LeaderboardView + SettingsView are behavior-only** per plan.md — no new snapshots.
- **8.11 baseline lock** spec says 21 PNGs, but Part 1 added 10 (4 of which aren't in §How.5.8's strict matrix: Root×2 + Home×2). With Part 2 adding ~15 more (Board 12 + Completion 3), the realistic baseline will be ~25, not 21. Part 2 dispatch authorizes either trimming Part 1 (not recommended) or amending plan.md §8.11 to reflect 25.

## Leader-parallel work this session

During Phase 8 Part 1's ~21-minute background run:
- Created task #20, marked in_progress.
- Wrote this meeting log.
- Plan-ahead: pre-drafted Part 2 dispatch covering the heaviest step (BoardView 12 snapshots + keyboard + A11y).

## Next session

Phase 8 Part 2 — already dispatched in background. Covers BoardView (8.7) / CompletionView (8.8) / LeaderboardView (8.9) / SettingsView (8.10) / snapshot baseline lock (8.11). On return, expect ~15-20 more tests + ~15 PNG baselines → total ~25 PNGs / ~295-300 tests. After Part 2 completes, Phase 9 (DI + Privacy + L10n) becomes the next dispatch.
