# 2026-05-19 — Phase 3 GameState

Session continuation of `ae54f5ea-6b89-4f59-9d9f-cafb8dff08f6`.
Mode: AI Collaboration Mode (Leader + 2 Developer subagent dispatches: Phase 2 follow-up bugfixes, then Phase 3).

## Goal

Close Phase 2 follow-ups (Solver `nakedPair` changed-flag bug, PuzzleCalibrator exponential `branchingFactor`), then execute Phase 3 — `GameState` module: state machine, transitions, play actions, elapsed time, snapshot, telemetry seam.

## Decisions

### Phase 2 follow-up fixes
1. **`Solver.applyNakedPair` changed-flag accuracy** — fixed at source, NOT at `propagate()` layer. `changed` now flips only on Board-cell fills, not on candidate eliminations. `propagate()` left untouched; once `applyOnce` returns honest, the fixed-point loop terminates naturally.
2. **`PuzzleCalibrator.calibrate` budget cap** — public constant `PuzzleCalibrator.branchingFactorCap = 8`; sentinel semantics ("`branchingFactor == 8` means ≥ 8 actual branches"). Pre-check + per-branch check ensure O(8^depth) worst case. Easy/Medium classification unchanged (require 0 / ≤2 branching).
3. **`PuzzleGenerator` workaround kept** — its hand-rolled fixed-point loop still works correctly; surgical-changes principle (Karpathy §3) — no churn beyond the filed bug. Doc comment slightly stale but not load-bearing.

### Phase 3 architecture
4. **`actor GameSession`** chosen over `final class @unchecked Sendable`. Swift 6 strict-concurrency cleanliness; Phase 8's `@Observable @MainActor` VM bridges via `await`.
5. **Notes are a side table**, not part of the Move/UndoStack timeline. `NotesGrid` = 9-bit-per-cell `UInt16` mask. Justification: Phase 2 `Move` only carries `placeDigit`; toggling pencil notes is cheap and intentionally uncoupled from undo.
6. **Completion is sticky** — once `.playing → .completed`, subsequent `complete()` and `undo()` both throw. Simplifies state-machine reasoning; matches typical puzzle-app UX.
7. **`MonotonicClock` is a local protocol** (over `TimeInterval`), not stdlib `Clock`. Reason: stdlib `Clock`'s associated `Instant` type is awkward to thread through `any Clock` existentials in actor inits; we only need second resolution for elapsed time.
8. **`GameStateTelemetry` is a local protocol seam** with `NoOpGameStateTelemetry` default. Phase 4 will swap for the real `Telemetry` module via either adapter or direct dep.
9. **`GameSessionSnapshot` flattens `UndoStack`** into `undoMoves: [Move] + redoMoves: [Move]` because `UndoStack` is currently only `Sendable + Equatable`. `restore()` rebuilds the split using public `push`/`undo` API. Filed as SudokuEngine follow-up (non-urgent).

## Rejected alternatives

- Keep `applyNakedPair` reporting candidate-elimination changes and patch `propagate()` instead — rejected because the dishonest `changed` value would still leak through anyone calling `applyOnce` directly.
- Move notes into the Move enum (`.note(row, col, digit, added: Bool)`) — rejected; pencil-note undo is rare UX and adds significant complexity to UndoStack inversion logic.
- Stdlib `Clock` protocol for elapsed time — rejected for `any Clock` existential awkwardness in actors.

## Hand-offs

### Subagent dispatches

| Dispatch | Scope | Commits |
|---|---|---|
| Developer (TDD bugfix) | Phase 2 follow-ups #1, #2 | `fdf1478` (solver), `8da3086` (calibrator) — +6 tests |
| Developer (Phase 3 full) | Steps 3.1–3.5 | `af7596a` / `e06fb01` / `9613fb7` / `11c6901` / `ea3b4cd` — +35 tests |

### Test tally

| Phase | Tests after |
|---|---|
| After 2.7+2.8 | 74 |
| After P2 follow-ups | 80 |
| After Phase 3 | **114** |

All green, 0 warnings on Swift 6 strict, lefthook passes.

## Open questions / Phase 4 forecast

1. **`UndoStack: Hashable + Codable` enhancement** in SudokuEngine — would let Phase 3 snapshot type embed UndoStack directly; current flatten-and-rebuild via public API works fine, no urgency.
2. **`GameStateEvent` ↔ `TelemetryEvent` mapping** in Phase 4 — local `GameStateEvent.sessionCompleted(elapsedMs:)` needs to project to plan.md §4.1's `TelemetryEvent.puzzleCompleted(puzzleId:, mode:, difficulty:, elapsedSeconds:)`. The adapter pattern (a) lets us add `puzzleId / mode / difficulty` at the adapter without changing GameSession's payload; the direct-dep pattern (b) requires GameSession to know about Practice / Daily mode (currently outside its concern). **Recommend (a)** — preserves GameSession's mode-agnosticism. Phase 4 dispatch should default to adapter pattern.
3. **Phase 2 follow-up #4** (Generator RNG seam for exhaustion testing) still open — not Phase 3 territory; can address as a tiny SudokuEngine PR later or roll into Phase 6 (PuzzleStore wrapping).

## Leader behavior note

Subagent dispatch + return latency was ~16 minutes total for this session (Phase 2 follow-up ~10 min, Phase 3 ~6 min). Per `[[leader-parallel-work-discipline]]` memory just written, Leader should have used those windows to write meeting logs in parallel rather than waiting. This log is being written after the fact — better than nothing, but not the target behavior.

## Next session

Phase 4 — `Telemetry` module. 6 steps (TelemetryEvent, TelemetrySink, Telemetry actor, OSLogSink, NoOpTrackingSink, MetricKitSink). Bridges to GameState via the adapter pattern decided above.
