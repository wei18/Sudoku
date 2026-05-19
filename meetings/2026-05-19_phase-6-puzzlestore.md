# 2026-05-19 — Phase 6 PuzzleStore

Session continuation of `ae54f5ea-6b89-4f59-9d9f-cafb8dff08f6`.
Mode: AI Collaboration Mode (Leader + 1 Developer subagent dispatch, background).

## Goal

Execute plan.md Phase 6 — `PuzzleStore` module: wrap `PuzzleGenerator` (Phase 2) with identity assembly, in-memory daily cache, OSLog `.public` salt logging. 4 steps.

## Decisions

1. **Practice puzzleId format**: `practice-{crockfordBase32(salt)}-{difficulty}`. Crockford base32 alphabet `"0123456789ABCDEFGHJKMNPQRSTVWXYZ"` (no I/L/O/U) chosen over RFC 4648 standard base32 because these ids surface in `OSLog .public` and player bug reports — unambiguous transcription matters.
2. **Daily puzzleId format**: `YYYY-MM-DD-{difficulty}` — UTC floor via fixed Gregorian calendar with `TimeZone(identifier: "UTC")`. Resilient to caller passing any timestamp.
3. **Seed derivation = FNV-1a 64-bit** with explicit per-element length-prefix framing. Reason: `Swift.Hasher`'s output is process-randomized (security feature, not portable); we need bit-identical cross-arch output per §How.4.6.
4. **`PuzzleGenerating` protocol seam**: only `LivePuzzleGenerating` ships in production. Wraps the static `SudokuEngine.PuzzleGenerator.generate(...)` call. Synchronous (matches engine signature) — keeping it async would have forced await-propagation downstream.
5. **`FakeGenerator` not an actor** — `final class @unchecked Sendable` with internal lock. Because `PuzzleGenerating.generate` is sync, an actor would have introduced an unnecessary async boundary.
6. **Cache key `(day: String, generatorVersion: GeneratorVersion)`** — version included so v2 bump (per §How.4.5) auto-invalidates without an explicit flush. v1 only ships v1 but architecture is forward-ready.
7. **NoOpLogger default** in `PuzzleStore.init`. Production wiring (App composition root, Phase 9.1) passes the real `OSLoggerAdapter`. Reason: `OSLoggerAdapter` is `internal` to Telemetry intentionally; PuzzleStore can't construct one directly without leaking that internal type.
8. **Practice does NOT cache** — every `fetchPracticePool` call increments `FakeGenerator.callCount`. Daily caches; practice draws fresh salt each call.

## Rejected alternatives

- **RFC 4648 base32 alphabet**: rejected for transcription ambiguity (`I` vs `1`, `0` vs `O`).
- **Caching practice draws**: rejected because that would defeat the "fresh salt per call" UX.
- **Actor `FakeGenerator`**: rejected because the underlying protocol is sync.
- **Process-randomized `Swift.Hasher` for seed**: rejected per cross-arch determinism contract (§How.4.6).

## Subagent dispatch — Phase 6 background

| Step | Commit | New tests |
|---|---|---|
| 6.1 PuzzleProviderProtocol + PuzzleIdentity + PuzzleEnvelope | `33d303a` | 7 |
| 6.2 Live PuzzleStore wrapping PuzzleGenerator + FakeGenerator | `54c7683` | 9 |
| 6.3 In-memory daily trio cache | `0bd17ec` | 4 |
| 6.4 PracticeSalt + OSLog `.public` salt logging | `f1a9c6c` | 3 |

**Total: 23 new tests, 184 → 207, 0 new warnings Swift 6 strict.**

Package.swift edit: `PuzzleStore` target deps changed from `["SudokuEngine"]` to `["SudokuEngine", "Telemetry"]` (single line). No other changes.

## Phase 7 readiness flagged by subagent

- `PuzzleEnvelope.identity.puzzleId` is the per-puzzle leaderboard submit key — GameCenterClient consumes it directly.
- `PuzzleIdentity.puzzleId` is the deterministic, OSLog-safe string surfaced from this layer; `SudokuEngine.Puzzle.seed` stays internal.
- `SubmitGuards.completedDailyPuzzleIds: Set<String>` (Phase 7.3) will hold these strings, seeded from `Persistence.fetchCompletedDailyIds(for:)`.

## Leader-parallel work this session

During Phase 6's ~10-minute background run:
- Created task #18, marked in_progress
- Spot-checked Phase 5 production (8 source files, 7 test files, TelemetryEvent has new cases) — all verified clean
- Read Phase 7 / 8 / 9 / 10 specs to have full project picture
- Wrote this meeting log

## Next session

Phase 7 — `GameCenterClient`. 7 steps wrapping live `GKLocalPlayer` / `GKLeaderboard` / achievements + Telemetry sink. Already dispatched in background while writing this log.
