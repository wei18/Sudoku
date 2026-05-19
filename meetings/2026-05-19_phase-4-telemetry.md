# 2026-05-19 — Phase 4 Telemetry

Session continuation of `ae54f5ea-6b89-4f59-9d9f-cafb8dff08f6`.
Mode: AI Collaboration Mode (Leader + 1 Developer subagent dispatch, background).

## Goal

Execute plan.md Phase 4 — `Telemetry` module: fan-out facade, three sinks (OSLog / NoOp tracking / MetricKit), bridge to GameState via adapter pattern decided in Phase 3 meeting log.

## Decisions

1. **Architectural deviation from plan.md §4.1**: `TelemetryEvent` payload uses **primitive `String` fields** for `mode` and `difficulty` (e.g. `puzzleCompleted(puzzleId: String, mode: String, difficulty: String, elapsedSeconds: Int)`) instead of the mirror enums plan.md hinted at. Reason: avoid Telemetry depending on SudokuEngine; adapter does `.rawValue` conversion at the seam. Documented in `TelemetryEvent.swift` header.
2. **Adapter location**: `Sources/Telemetry/GameStateTelemetryAdapter.swift` (production, not SudokuKitTesting). Reasoning: the App composition root needs the adapter, not just tests.
3. **Package.swift edit**: `Telemetry` target now depends on `GameState` (single-line addition). `GameState` does NOT import `Telemetry` — the local `GameStateTelemetry` protocol seam from Phase 3 is preserved. No dependency cycle.
4. **`LoggerProtocol.log` sync, not async**: live `os.Logger` is sync; making the protocol async would add `await` noise without payoff. `FakeLogger` actor-isolates its internal store via `nonisolated func log(...)` + `Task { await self.append(...) }`, with a `settle()` helper to drain before assertions.
5. **`MetricKitSink` testing seam**: `MXMetricManagerSubscriber` callbacks can't be driven from unit tests (real device only). Production code split into:
   - `startReceivingSystemReports()` — live registration with `MXMetricManager.shared.add(self)`
   - `ingest(kind: payloadJSON:)` — test-friendly seam that accepts canned JSON, used by `MetricPayloadFixtures` (daily / crash / hang shaped per Apple docs).
   Live MetricKit wiring deferred to Phase 10 TestFlight validation.
6. **`MetricKitSink` as both source and sink**: it produces `metricKitReport` events into the Telemetry fan-out AND conforms to `TelemetrySink` (no-op `receive`) for API symmetry. Documented as intentional.
7. **Swift compile flags applied**: complete concurrency, `InternalImportsByDefault`, `ExistentialAny`. All 6 commits passed.

## Rejected alternatives

- Mirror `Difficulty` / `GameMode` enums inside Telemetry — rejected for cross-module type-drift risk.
- Put adapter in `SudokuKitTesting` — rejected because App composition root (real production code) needs it.
- Make `LoggerProtocol.log` async — rejected because `os.Logger` itself is sync.

## Subagent dispatch — Phase 4 background

| Step | Commit | New tests |
|---|---|---|
| 4.1 TelemetryEvent + TelemetrySink + MetricReport | `6798ab6` | 4 (Sendable / Equatable / Codable / MetricReport round-trip) |
| 4.2 Telemetry actor (fan-out) | `2571808` | 3 (all-sinks-receive / slow-sink-doesnt-block / ordering-preserved); removed obsolete SmokeTests.swift |
| 4.3 OSLogSink + LoggerProtocol seam + FakeLogger | `17646d0` | 6 (level mapping + privacy defaults + live os.Logger init) |
| 4.4 NoOpTrackingSink | `960a1a4` | 2 |
| 4.5 MetricKitSink + MetricPayloadFixtures | `9a296f4` | 4 (daily / crash / hang ingest + receive-as-sink no-op) |
| 4.6 GameStateTelemetryAdapter | `0f8f6f3` | 4 (session-event mapping / gameplay pass-through / abandon-zero-elapsed) |

**Total: 22 new tests, 126 → 148, 0 warnings Swift 6 strict.**

## Phase 5 readiness flagged by subagent

- `TelemetryEvent.errorOccurred(source:code:message:)` ready for Persistence LWW conflict / iCloud signed-out / quota-exceeded events.
- Save lifecycle events `puzzleCompleted` / `sessionAbandoned` carry `puzzleId / mode / difficulty / elapsedSeconds` — exactly what SavedGame CRUD needs to mirror to CloudKit.
- `Persistence` target already declares `Telemetry` as a dependency in `Package.swift` (line 18 per subagent).
- **Recommendation for Phase 5**: add a `.gameSaved(puzzleId:)` / `.gameSaveFailed(puzzleId:reason:)` event pair when Phase 5.4 lands. Additive change, no breaking impact.

## Leader-parallel work this session

During Phase 4's ~7-minute background run:
- ✅ Wrote Phase 3 / SudokuEngine follow-up closure (appended to 2026-05-19_phase-3-gamestate.md). Committed `8d7c11a` before Phase 4 returned.
- ✅ Spot-checked subagent C's claims (UndoStack/Move Hashable+Codable, PuzzleGenerator generic overload, commit count) — all verified true.
- ✅ Pre-read plan.md §Phase 5 spec to be ready for the next dispatch.
- ✅ Created task tracker entries #15 (closed) / #16 (in_progress).

This is the **first session honoring `[[leader-parallel-work-discipline]]`** — no idle time during subagent runs.

## Next session

Phase 5 — `Persistence` (CloudKit Private DB). 7 steps:
- 5.1 PersistenceProtocol + value types
- 5.2 Custom zone provisioning (`com.wei18.sudoku.userZone`)
- 5.3 CKDatabaseSubscription setup
- 5.4 SavedGame CRUD + generatorVersion field (+ Phase 4 follow-up: add `.gameSaved` / `.gameSaveFailed` events)
- 5.5 PersonalRecord CRUD + dedup
- 5.6 Per-field LWW conflict resolver (3-retry budget)
- 5.7 CKAccountChanged flow (Case A / B / C per §How.6.5)

Also a candidate Phase 5 simplification: `GameSessionSnapshot` can now embed `UndoStack` directly (Phase 3 follow-up).
