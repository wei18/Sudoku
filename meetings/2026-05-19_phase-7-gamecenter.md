# 2026-05-19 — Phase 7 GameCenterClient

Session continuation of `ae54f5ea-6b89-4f59-9d9f-cafb8dff08f6`.
Mode: AI Collaboration Mode (Leader + 1 Developer subagent dispatch, background).

## Goal

Execute plan.md Phase 7 — `GameCenterClient` module: protocol + value types, live `GKLocalPlayer` auth, submit-score guards + `.v1` leaderboard IDs, achievement evaluator backed by Persistence, leaderboard slice with friends auth, `GameCenterSink` TelemetrySink consumer, macOS region mapper. 7 steps.

## Decisions

1. **`GKError.Code` → `AuthOutcome` mapping** (in `GKAuthDriver.mapError`):
   - `.cancelled` → `.cancelled`
   - `.notAuthenticated` → `.signedOut`
   - `.parentalControlsBlocked` → `.restricted`
   - `.gameUnrecognized` / `.notSupported` → `.unavailableInRegion`
   - else → `.error(rawCode + description)`
   Modern `GKError.Code` no longer has `.restricted`; the spec's prior "restricted" semantics now mean `.parentalControlsBlocked`. Comment in source.

2. **`AuthOutcome` → `GameCenterAuthState` mapping** (in `LiveGameCenterClient.mapOutcomeToState`):
   - `.signedIn(player)` → `.authenticated(player)` (return)
   - `.signedOut` → `.unauthenticated`
   - `.restricted` → `.restricted`
   - `.unavailableInRegion` → `.unavailableInRegion`
   - `.cancelled` → throws `GameCenterError.cancelled`
   - `.error(msg)` → throws `GameCenterError.underlying("AuthDriver", -1, msg)`

3. **`RegionMapper` (Step 7.7)** — pure `(Int rawCode, region String?) → classification`, no GameKit import. Codes 15/16 (`gameUnrecognized`/`notSupported`) when `region ∈ {"CN"}` → `.unavailableInRegion`; else `.ok`. Bias: false negatives (retry UI shown) over false positives (UI hidden).

4. **`GameCenterSink` swallows errors silently** per design.md §How.3.4 (`v1 不做離線提交佇列`; CloudKit `PersonalRecord` is durable record of truth, GC is "炫耀面"):
   - `submitScore` throw → swallowed
   - `reportAchievement` throw → swallowed per achievement (one failure doesn't stop others)
   - `evaluator.evaluateForCompletion` throw → swallowed (non-critical; re-derives on next completion)
   - Comments mark "Swallowed per §How.3.4" for grep-ability.
   - Live errors observable via `OSLogSink` (Phase 4); GameCenterSink itself doesn't import OSLog.

5. **Only `Live/GKAuthDriver.swift` imports `GameKit`**, fenced with `#if canImport(GameKit)` so Linux CI builds collapse to `.error("GameKit unavailable")` rather than failing. No other production file in `GameCenterClient` imports GameKit.

6. **Package.swift dep edit**: `GameCenterClient` deps `["Telemetry"] → ["Telemetry", "Persistence"]`. `AchievementEvaluator` needs `Persistence.fetchCompletedDailyIds` + `fetchPersonalRecord`. **`PuzzleStore` NOT added**: `SubmitGuards` parses `practice-` prefix + `YYYY-MM-DD` shape locally without needing PuzzleStore's `PuzzleIdentity` type — keeps the module at the same dependency-graph layer as PuzzleStore (sibling, not consumer).

## Rejected alternatives

- **GameCenterSink queues failed submissions for retry**: rejected per §How.3.4 (v1 no offline queue).
- **Per-error explicit `os.Logger.error` in GameCenterSink**: rejected to keep the sink GameKit-free / OSLog-free. Live errors propagate from `LiveGameCenterClient` which can log there.
- **Importing PuzzleStore into GameCenterClient for `PuzzleIdentity`**: rejected to avoid dependency-graph rotation. SubmitGuards parses puzzleId strings locally.

## Subagent dispatch

| Step | Commit | New tests |
|---|---|---|
| 7.1 Protocol + value types + FakeGameCenterClient | `8dfefee` | 6 |
| 7.2 LiveGameCenterClient + GKAuthDriver + FakeAuthDriver | `e4f1685` | 5 |
| 7.3 SubmitGuards + LeaderboardIDs (.v1 suffix) | `4ef60ef` | 7 |
| 7.4 AchievementEvaluator (Persistence-backed) | `fb3b55b` | 6 |
| 7.5 Leaderboard slice + friends-auth precondition | `c1b45d0` | 6 |
| 7.6 GameCenterSink (TelemetrySink consumer) | `2eeb0df` | 6 |
| 7.7 RegionMapper for macOS region restriction | `1679064` | 6 |

**Total: 41 new tests, 207 → 248, 0 warnings Swift 6 strict + complete concurrency.**

## Phase 8 readiness

Protocol surfaces ready for SudokuUI consumption:
- `RootView.task` → `try await client.authenticate()` returns `GameCenterAuthState`.
- `LeaderboardView` → `client.fetchLeaderboardSlice(leaderboardId:scope:around:limit:)`.
- `CompletionView` → deep link to `LeaderboardView` via `LeaderboardIDs.id(for: kind)` String.
- `authStateUpdates()` AsyncStream ready for `.task` observation.
- Friends-auth: `friendsAuthorizationStatus()` precondition + `requestFriendsAuthorization()` explicit gesture trigger.

## Leader-parallel work this session

During Phase 7's ~14-minute background run:
- Created task #19, marked in_progress.
- Wrote this meeting log entry.
- Pre-planned the Phase 8 split (Part 1 + Part 2) to avoid usage-limit interruption that hit Phase 2.

## Next session

Phase 8 — `SudokuUI`. **Split into two parts** due to size:
- **Part 1** (8.1–8.6): Theme + DefaultTheme, AppRoute + navigation, RootView, HomeView, DailyHubView, PracticeHubView. Already dispatched in background.
- **Part 2** (8.7–8.11): BoardView (12 snapshots + keyboard + A11y), CompletionView, LeaderboardView, SettingsView, baseline lock to 21 PNGs.
