# #579 phase 1+2 — wire Sudoku completion→Telemetry→GameCenter pipeline (impl-notes)

Branch: `feat/579-wire-gc-pipeline`. PR scope = phase 1 + phase 2 (restore leaderboard
submission + achievement reporting). Phases 3 (#578 PersonalRecord write) + 4 (#552
optimistic concurrency) are a follow-up PR.

## Root cause (verified, see #579)
Live Sudoku never emits `.puzzleCompleted`: `GameSession.restore` defaults `telemetry`
to `NoOpGameStateTelemetry` and `BoardLoaderView:128` passes none. `GameStateTelemetryAdapter`
+ `GameCenterSink` are never instantiated live. `makeGameApp` sinks = `[OSLogSink, NoOpTrackingSink]`.

## Phase 1 — adapter → live GameSession
- `BoardLoaderView`: add `telemetry: Telemetry? = nil` (default nil keeps preview/test call
  sites working — nil → NoOp, no behavior change).
- In `load()`, when `telemetry != nil`, build a fresh per-session adapter and pass to restore:
  ```
  let gameTelemetry: any GameStateTelemetry = telemetry.map {
      GameStateTelemetryAdapter(telemetry: $0, puzzleId: puzzleId, mode: identity.kind, difficulty: identity.difficulty)
  } ?? NoOpGameStateTelemetry()
  let session = await GameSession.restore(from: snapshot, telemetry: gameTelemetry)
  ```
- `LiveRouteFactory` `.board` destination (boardDestination helper): pass `telemetry: telemetry`
  into `BoardLoaderView`. RouteFactory already holds `telemetry: Telemetry`.
- Verify: integration test — a session completion routed through the live adapter makes the
  injected `Telemetry` observe `.puzzleCompleted(puzzleId,mode,difficulty,...)`.

## Phase 2 — GameCenterSink into the live sink list (breaks a dependency cycle)
**Cycle:** `Telemetry`(built first) ← needs `GameCenterSink` ← needs `persistence`/`gameCenter`/
`errorReporter` ← need `Telemetry`. Break with late binding (mirrors `LiveMetricKitRetainer.install`).

- NEW `TelemetryKit/Sources/Telemetry/DeferredSink.swift`:
  ```
  public final class DeferredSink: TelemetrySink, @unchecked Sendable {
      private let lock = NSLock()
      private var downstream: [any TelemetrySink] = []
      public init() {}
      public func setDownstream(_ sinks: [any TelemetrySink]) { lock.lock(); downstream = sinks; lock.unlock() }
      public func receive(_ event: TelemetryEvent) async {
          lock.lock(); let sinks = downstream; lock.unlock()
          for sink in sinks { await sink.receive(event) }   // sequential, mirrors Telemetry fan-out; no lock held across await
      }
  }
  ```
  Set exactly once at composition, before any event flows. Lock guards only the array read/write.
- `GameConfig`: add `public let makeCompletionSinks: (@MainActor @Sendable (GameDeps, GameRootViewModel<Route>) -> [any TelemetrySink])?` (default `nil`). Append to init with default `nil` so MS / 2048 / Preview configs are unaffected.
- `makeGameApp` (MakeGameApp.swift):
  - step 1: `let completionSink = DeferredSink()`; add it to `Telemetry(sinks: [OSLogSink(...), NoOpTrackingSink(), completionSink])`.
  - AFTER `rootViewModel` is built (step 10): `completionSink.setDownstream(config.makeCompletionSinks?(deps, rootViewModel) ?? [])`. (After rootVM because the auth provider reads it.)
- Sudoku `GameConfig` (Live.swift): add closure
  ```
  makeCompletionSinks: { deps, rootViewModel in
      [GameCenterSink(
          client: deps.gameCenter,
          guards: SubmitGuards(),
          achievements: AchievementEvaluator(persistence: deps.persistence),
          authStateProvider: { await MainActor.run { rootViewModel.authState } },
          errorReporter: deps.errorReporter
      )]
  }
  ```
  MS / 2048 leave it nil (they submit directly in their VMs; converge later under the mirror principle).

### Decisions / deviations
- **SubmitGuards seeded empty** (no async `fetchCompletedDailyIds` seed at sync composition).
  Rationale: GameKit leaderboards are best-score, so a once-per-launch re-submit of an
  already-submitted daily is harmless; within-session dedup still holds via `markSubmitted`.
  A persistence-seeded guard can be a follow-up if telemetry shows redundant submits.
- **authState via `rootViewModel.authState`** (already maintained: set at boot from
  `authenticate()`, updated by `authStateUpdates()`), not a fresh `authenticate()` per
  completion. `.unknown` before boot resolves → sink no-ops; a real completion always
  happens after boot auth resolves.
- DeferredSink is a `final class @unchecked Sendable` (sync `setDownstream` callable from the
  `@MainActor` sync `makeGameAppCore`) rather than an actor (actor would force `await` in a
  sync function).

## CR outcome (dual-Sonnet, 2026-06-20)
Reviewer A: ship-with-fixes (retain-cycle nit + `.unknown` auth window). Reviewer B (replacement,
ran the tests): ship-with-fixes — surfaced two things A missed:
- **Blocking completion path** (applied): `GameCenterSink.receive` runs `AchievementEvaluator`
  (real CloudKit reads) on the `placeDigit → sessionCompleted → Telemetry.observe` gameplay path
  → froze the board-completion animation. Fix: `DeferredSink.receive` now forwards on a detached,
  order-preserving Task (chained on the previous task) + `awaitForwardingForTesting()` drain for
  deterministic tests. Fast sinks (OSLog/NoOp) stay synchronous.
- **GameKit terminal is a stub** (NOT fixable here → issue #580): `LiveGameCenterClient.submitScore`
  calls a no-op hook and `reportAchievement` always throws → no score/achievement reaches GameKit
  even with phases 1+2 wired. Device-gated (entitlement + real device + GC sandbox).
- Retain-cycle nit applied: `[weak rootViewModel]` in `authStateProvider`.
- `.unknown`-at-cold-boot auth window: documented as a known limitation, not fixed (practically
  unreachable; §How.3.4 forbids a retry queue).

**Disposition**: branch holds correct, green, CR'd plumbing but is NOT merged — it delivers no
user-visible change until #580 (GameKit terminal) lands. Merge decision deferred to user.

## Out of scope (follow-up PR / issues)
- **#580** (GameKit terminal): real `GKLeaderboard.submitScore` + `reportAchievement` — the gating
  user-facing piece, device-verified.
- Phase 3 (#578): a `PersonalRecordSink` added to the same `makeCompletionSinks` array, calling
  a new facade `recordPuzzleCompletion(...)` → `PersonalRecordStore.recordCompletion`.
- Phase 4 (#552): scoped etag layer + per-record save policy + bounded retry (ref `fc557b8`).
