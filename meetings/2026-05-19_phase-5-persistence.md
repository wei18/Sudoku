# 2026-05-19 — Phase 5 Persistence

Session continuation of `ae54f5ea-6b89-4f59-9d9f-cafb8dff08f6`.
Mode: AI Collaboration Mode (Leader + 1 Developer subagent dispatch, background).

## Goal

Execute plan.md Phase 5 — `Persistence` (CloudKit Private DB): protocol + value types, custom zone, CKDatabaseSubscription, SavedGame CRUD with Telemetry, PersonalRecord dedup, per-field LWW conflict resolver, CKAccountChanged Case A/B/C. Live CloudKit access deferred to Phase 10; all unit tests via fake gateway.

## Decisions

1. **`puzzleLoader` injection on `SavedGameStore`** — `loadOrCreate(puzzleId:mode:difficulty:)` must return a `GameSessionSnapshot` (containing `Puzzle`), but CK records only store `puzzleId`. Store takes a `@Sendable (String) async throws -> Puzzle` loader closure; Phase 6 wires this to `PuzzleStore.puzzle(for:)`.
2. **`generatorVersion: String enum → Int(64) CK field`** — `GeneratorVersion.v1` deterministically maps to `1` via `SavedGameMapper.generatorVersionInt(_:)`. Schema bridge documented.
3. **`PrivateCKGateway` seam keeps CloudKit out of the Persistence test surface** — protocol uses primitive `RecordPayload` / `RecordPredicate` types; only `LivePrivateCKGateway` imports CloudKit. All other Persistence code (mappers, stores, resolver, monitor, cache) is unit-tested via `FakePrivateCKGateway`.
4. **`save(_:)` mode disambiguation** — added qualified overload `save(_:puzzleId:mode:difficulty:)` because `GameSessionSnapshot` doesn't carry `mode`/`difficulty`. The bare protocol-mandated `save(_:)` defaults `mode = "practice"` with `puzzleId = snapshot.puzzle.seed.description` as a fallback. **VM (Phase 8) should always call the qualified variant.** Flagged.
5. **`statusEnvelope: Data` extra CK field** — CK schema's status string only carries `"inProgress" | "completed"`. To preserve `GameSessionStatus` round-trip fidelity (including `.paused` / `.idle` / `.abandoned`), the mapper stores a Codable-encoded envelope alongside. Backward-compatible (falls back to string when envelope missing).
6. **`Board(encoded:against:)` private helper** — `Board(clues:)` marks every filled cell as `given`, which is wrong for in-progress boards. New helper starts from `puzzle.clues` and overlays player moves while preserving `givenMask`.
7. **`UndoEnvelope { undo, redo }` workaround** — Phase 3 follow-up #1 noted that `UndoStack` is now Hashable+Codable so snapshot could embed it directly. Phase 5 used the existing `undoMoves: [Move] / redoMoves: [Move]` pair via a tiny envelope wrapper. GameState simplification NOT done (per hard constraint); future opportunity logged but not blocked.
8. **`OSLogSink.receive(_:)` non-exhaustive switch caught** — appending `.gameSaved` / `.gameSaveFailed` to TelemetryEvent forced the switch update; added `.info` / `.error` mappings respectively, both `.public` privacy (puzzleId / reason are not PII).

## Telemetry additions

Two cases appended to `TelemetryEvent`:
- `.gameSaved(puzzleId: String)` — emitted after successful save
- `.gameSaveFailed(puzzleId: String, reason: String)` — emitted after CK failure (gateway error mapped to a short reason string)

Existing Phase 4 TelemetryEvent tests (`allCasesSendable` / `equatablePerCase` / `codableRoundTrip`) used generic conformance + representative case lists, so they pass unchanged. Only `OSLogSink.receive` needed manual update.

## Rejected alternatives

- **Wire Persistence to live CloudKit in unit tests**: rejected by hard constraint (Phase 10 territory).
- **Drop the qualified `save(_:puzzleId:mode:difficulty:)` overload and force VMs to embed metadata in snapshot**: rejected because GameState is mode-agnostic by Phase 3 decision; metadata flows through the adapter / store layer.
- **Modify `GameSessionSnapshot` to use `UndoStack` directly**: rejected per hard constraint; envelope workaround is clean enough.

## Subagent dispatch

| Step | Commit | New tests |
|---|---|---|
| 5.1 PersistenceProtocol + value types + PersistenceError | `70ef559` | 4 |
| 5.2 Custom zone + FakePrivateCKGateway | `3fc533c` | 3 |
| 5.3 CKDatabaseSubscription | `8987841` | 3 |
| 5.4 SavedGame CRUD + Telemetry events + generatorVersion | `6c91f44` | 7 |
| 5.5 PersonalRecord CRUD + dedup | `af47b42` | 8 |
| 5.6 Per-field LWW conflict resolver + 2-retry budget | `c034790` | 8 |
| 5.7 CKAccountChanged + LocalCache + Keychain | `e306817` | 4 (sequencing yields 184 total) |

**Total: ~36 new tests, 148 → 184, 0 warnings Swift 6 strict + complete concurrency + InternalImportsByDefault + ExistentialAny.**

### Files

Production (`Sources/Persistence/`):
- `PersistenceProtocol.swift`, `SavedGameSummary.swift`, `PersonalRecord.swift`, `PersistenceError.swift`
- `Live/LivePrivateCKGateway.swift` (compile-only; Phase 10 lights up)
- `Live/SavedGameStore.swift`, `Live/SavedGameMapper.swift`
- `Live/PersonalRecordStore.swift`
- `Live/SubscriptionInstaller.swift`
- `Live/ConflictResolver.swift`
- `Live/AccountMonitor.swift`
- `Live/LocalCache.swift`

Shared test helpers (`Sources/SudokuKitTesting/Persistence/`):
- `FakePrivateCKGateway.swift`, `PuzzleFixtures.swift` (latin-square puzzle), `FakeKeychain.swift`, `FakeAccountProvider.swift`

Tests (`Tests/PersistenceTests/`):
- 7 test files covering all 7 steps + protocol shape.

## Phase 6 readiness

- `PuzzleStore.puzzle(for: puzzleId)` will plug into the `SavedGameStore.PuzzleLoader` closure — that's the integration seam.
- `Persistence.fetchCompletedDailyIds(for:)` ready for `GameCenterSink`'s dedup cache (Phase 7).
- `PersistenceProtocol` is a protocol — `LivePersistence: PersistenceProtocol` facade composing `SavedGameStore + PersonalRecordStore + AccountMonitor` is App composition root (Phase 8) work, NOT Phase 6. Phase 6 consumes the protocol from PuzzleStore side.

## Leader-parallel work this session

During Phase 5's ~14-minute background run:
- Created task #17 + tracked progress
- Set up `.claude/settings.json` allowlist via `fewer-permission-prompts` skill — analysis showed 80% of user's prompt-pain is git-write commands which skill rules forbid allowlisting; rest is auto-allowed already. Limited net allowlist additions.
- Wrote this meeting log

## Next session

Phase 6 — `PuzzleStore`. 4 steps wrapping `PuzzleGenerator` + `Persistence`:
- 6.1 `PuzzleProviderProtocol` + types
- 6.2 `PuzzleStore` live impl wrapping generator + in-memory cache
- 6.3 `fetchDailyTrio` / `fetchPracticePool`
- 6.4 OSLog `.public` salt logging
