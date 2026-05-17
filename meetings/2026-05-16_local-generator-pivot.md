# 2026-05-16 — Local Generator Pivot

Session id (continuation of): `ae54f5ea-6b89-4f59-9d9f-cafb8dff08f6`
Mode: AI Collaboration Mode (Leader + parallel subagents: Architect / Code Reviewer / UI Designer)

## Goal

Evaluate user-raised question "能不能不用 server, 本地端們自建一樣的數獨題目?" and, if feasible, pivot the v1 architecture from CloudKit Public DB-served puzzle pool to fully local deterministic generation. Apply changes to design.md / foundations.md / docs/designs/ with multi-agent review before commit.

## Decisions

### Architectural pivot (route A — full local generation)

1. **Daily and Practice puzzles are generated locally and deterministically** on every device. No server-side puzzle pool, no CloudKit Public DB writes, no Xcode Cloud Puzzle Delivery workflow, no `consumed.json`, no `PuzzleDeliveryLedger`, no Starter Pack bundle.
2. **`seed = stableHash(generatorVersion, dateUTC, difficulty)`** for Daily; `seed = stableHash(generatorVersion, randomSalt, difficulty)` for Practice (salt sourced via injected `RandomNumberGenerator`).
3. **RNG = SplitMix64** (or xoshiro256\*\*) — pure-integer arithmetic, deterministic across iOS arm64 + macOS arm64. Apple Silicon-only (macOS 26 floor already excludes Intel).
4. **`GeneratorVersion` is committed to be frozen post-ship**. Any algorithm change requires a version bump, which forks Game Center leaderboard family (`com.wei18.sudoku.leaderboard.{difficulty}.daily.v1` → `.v2`). On v2 ship, in-progress `SavedGame` rows with older `generatorVersion` are marked abandoned.
5. **No CloudKit override fallback in v1** (no `PuzzleOverride` record type). If a generator defect produces a bad puzzle on a given date, that bad puzzle ships. Risk accepted for full offline capability + zero secret management surface.
6. **`PuzzleOverride` record type reserved** for v2 (`recordName: override-YYYY-MM-DD-{difficulty}`, fields documented in design.md §How.2). v2 can introduce override fetch path without redesign.

### Engine / module shape

7. **`Puzzle` value type lives in `SudokuEngine`** (was previously in PuzzleStore). Pure math: `clues`, `solution`, `difficulty`, `generatorVersion`, `seed`. No `puzzleId` field (avoids product semantics leaking into the engine).
8. **`PuzzleIdentity` + `PuzzleEnvelope` live in `PuzzleStore`** — id assembly is product-level (date string for Daily, `practice-{base32(seed)}` for Practice).
9. **Protocol renamed**: `PuzzleStoreProtocol` → `PuzzleProviderProtocol`. Module / target name stays `PuzzleStore`. API names `fetchDailyTrio` / `fetchPracticePool` unchanged.
10. **Practice salt strategy**: option (b) non-persistent system entropy (not monotonic counter); logged via `OSLog .public` for debug reproducibility.
11. **Single retry loop** in generator (N=32) covers both uniqueness check + calibrator rejection in one budget. `GeneratorError.exhausted` on overflow is treated as a defect (.fault + MetricKit signal).
12. **Performance budget**: < 300 ms typical, < 500 ms p95 for Hard puzzle on iPhone 15 device, **including retry overhead**. Manually measured at Phase 0 + each major release; NOT gated in CI.

### UI / UX implications

13. **DailyHubView empty state removed** (`cloud.sun` SF Symbol dropped from inventory). The "no daily today" path no longer exists; only `GeneratorError.exhausted` as Alert.
14. **PracticeHubView gains shimmer state** (`drawing` state at >100 ms; per `design-system.md §Loading & Placeholder` HIG thresholds: 0–100 ms none, 100–500 ms shimmer, >500 ms ProgressView).
15. **SettingsView ABOUT row adds `Generator v1`** — exposes `GeneratorVersion` for power-user bug reports.
16. **Clear-cache copy reworded** to reflect deterministic re-derivation ("same seed → same puzzle").
17. **Snapshot baseline bumped 18 → 21** (added PracticeHubView 3 states: idle / drawing-shimmer / drawn).

### Infrastructure simplifications (from pivot)

18. **Xcode Cloud workflows reduced 4 → 3**: PR / Main / Release. Puzzle Delivery row deleted from foundations.md §4.
19. **CloudKit server-to-server PEM secret class removed** from foundations.md §7.2 secret classification (v1 no Public DB writes).
20. **CloudKit Public DB scope is provisioned but unused in v1** — container still exists for Private DB (SavedGame + PersonalRecord in `com.wei18.sudoku.userZone`).

## Rejected alternatives

- **Route B — Hybrid (local generation + `PuzzleOverride` escape hatch)**: I (Leader) initially recommended this for safety. User chose A explicitly to maximize architectural simplicity for v1. Override mechanism preserved in v2 backlog with full record schema reserved in §How.2.
- **Route C — Keep CloudKit-served pool**: rejected for complexity vs. v1 portfolio scope.
- **Route D — Defer the pivot to v2**: rejected because no implementation code has been written yet; cost of pivot is near zero now and high later.
- **Monotonic per-device counter for Practice salt**: rejected because reinstalls would replay the same draw order — feels like a bug. Non-persistent system entropy chosen.

## Hand-offs

### Subagents dispatched (5 total)

1. **Software Architect round 1** — Apply pivot to design.md + foundations.md. Returned with the new §How.4 Deterministic Local Generator section plus all cross-section updates.
2. **Code Reviewer round 1** — Verified pivot correctness. Found 1 BLOCKER (SavedGame schema stale ref to Public DB) + 3 MAJORs + 4 MINORs.
3. **Architect Cross-Check round 1** — Independent architectural review. Found 8 GAPs (Puzzle.puzzleId format leak, PuzzleStoreProtocol naming, GeneratorVersion transition undefined, Practice salt entropy, retry budget clarity, Puzzle.seed logging, perf enforcement, v2 PuzzleOverride naming reserve).
4. **UI Designer round 1** — UX implication review. Found 6 NEEDS-UPDATE proposals (DailyHub empty, Practice shimmer, GeneratorError alert, Settings, design-system shimmer section, snapshot baseline).
5. **Software Architect round 2** — Applied 13 fixes (1 BLOCKER + 3 MAJOR + 8 GAP + 1 MINOR). All landed cleanly.
6. **UI Designer round 2** — Applied 5 UX fixes to docs/designs/. Surfaced 3 cross-file inconsistencies for Leader resolution.

### Leader inline fixes (after subagent passes)

- `design-system.md` SF Symbols inventory: removed `cloud.sun (DailyHubView empty state)`.
- `04-practice-hub.md` §f: "pool-draw logic" → "generator-draw logic".
- `design.md` §How.5.8 + cross-refs: snapshot baseline 18 → 21 (added PracticeHubView row).

## Open questions

- **v2 generator algorithm change strategy**: even though v1 commits to never bumping `GeneratorVersion`, the cross-version transition runtime is now spec'd (§How.4.5). Whether to bump in v2 remains a v2-era decision.
- **Performance prerequisite verification**: §How.4.9 lists 3 fresh `[ ]` Unconfirmed items (SplitMix64 cross-arch, Hard p95 < 300 ms baseline, App Store policy spot-check). Plan.md Phase 0 owns these.
- **§How.4.3 worst-case 32-retry CPU vs 300 ms budget**: theoretical max not empirically validated; Phase 0 performance baseline should measure.

## Next session

Resume the `plan.md` writing dispatch (deferred during the pivot). Plan should incorporate:
- Phase 0 prerequisites refreshed (3 new items)
- Phase 2 (`SudokuEngine`): adds DeterministicRNG, PuzzleGenerator, frozen-seed reproducibility tests
- Phase 6 (`PuzzleStore`): now a thin generator wrapper + PuzzleIdentity assembly; no CloudKit Public DB
- Phase 10 (Puzzle Delivery): **DELETED** — no longer needed
- L10n / TestFlight / submission phases unchanged
- Net plan length: ~80 steps → ~60 steps (12 phases → 10 phases)
