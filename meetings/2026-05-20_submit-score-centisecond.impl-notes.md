# Impl Notes — submitScore ms→centisecond conversion (2026-05-20)

Status: COMPLETE
Owner: Senior Developer
Dispatched by: Leader
Started: 2026-05-20
Completed: 2026-05-20
Issue: filed by Leader (link TBD)
Branch: fix/submit-score-centisecond-conversion (Leader-managed)

## Problem statement

`design.md §How.3.1` specifies daily-leaderboard submissions as elapsed time in
**centiseconds** (`ELAPSED_TIME_CENTISECOND` ASC formatter, 1/100 sec resolution,
`mm:ss.SS` display) with the conversion `GameState.elapsedSeconds × 100 → Int64`.

`LiveGameCenterClient.submitScore(...)` was still a Phase-7-deferred stub that
threw `.notAuthenticated`. The conversion was never wired. Phase 7 has shipped,
so the actual wiring lands now — but the live `GKLeaderboard.submitScore(...)`
call still belongs to Phase 10 manual-device integration. This change wires the
conversion at the boundary today and leaves a test seam for the eventual GameKit
call.

## 設計決定 (Design decisions)

- **Conversion site = `LiveGameCenterClient.submitScore` only.** The public
  `GameCenterClient.submitScore(elapsedSeconds: Int, ...)` protocol keeps the
  seconds-only contract per the dispatch constraint ("callers shouldn't need to
  know about cs conversion"). The multiply lives at exactly one place — the
  live boundary — eliminating any chance of double-conversion.
- **Test seam: `SubmitScoreHook = @Sendable (String, Int64) async throws -> Void`.**
  Default value is a no-op closure, so existing production composition root
  (`AppComposition/Live.swift::LiveGameCenterClient(authDriver:)`) and the
  existing `AuthTests` continue to compile unchanged. The default-argument
  init keeps the public signature backward compatible — adding only an
  optional second parameter. Phase 10 will replace the default with a real
  `GKLeaderboard.submitScore(...)` adapter.
- **Hook takes `(leaderboardId, centiseconds)` not `(centiseconds)` alone.**
  The leaderboard ID resolution (`LeaderboardIDs.id(for: kind)`) also moves
  inside `submitScore` so that when Phase 10 wires GameKit, the hook gets
  exactly the two arguments `GKLeaderboard.submitScore(value:, leaderboardIDs:)`
  needs — no further refactor at that point.
- **`Int64(elapsedSeconds) * 100` not `Int(_) * 100` then widen.** Widen *before*
  the multiply so the 2-hour ceiling (7200 s → 720_000 cs) is safe on 32-bit
  platforms (academic guard; iOS-only targets are 64-bit, but cost is zero).
- **Audit path (1 multiply, end-to-end)**:
  ```
  GameSession.accumulatedSeconds (Int)              ← MonotonicClock
    → telemetry.dispatch(.sessionCompleted(elapsedSeconds: Int))
    → GameStateTelemetryAdapter.mapping(_:)         (passes Int through)
    → TelemetryEvent.puzzleCompleted(elapsedSeconds: Int)
    → GameCenterSink.receive(_:) → submitScoreIfEligible(elapsedSeconds: Int)
    → client.submitScore(elapsedSeconds: Int, ...)
    → LiveGameCenterClient.submitScore             ← ★ multiply HERE ★
        centiseconds = Int64(elapsedSeconds) * 100
    → submitScoreHook(leaderboardId, centiseconds)  (Phase 10 → GKLeaderboard)
  ```
  Searched every `elapsedSeconds`/`* 100` site to confirm no other multiply.
  Sink and adapter pass the Int through verbatim.

## 折衷 (Tradeoffs)

- **Default-arg init vs. two separate inits.** Picked default-arg
  (`submitScoreHook: @escaping SubmitScoreHook = { _, _ in }`) to keep the
  `CompositionTests` line `String(describing: type(of: gcChild)).contains(
  "LiveGameCenterClient")` and `AuthTests.swift` lines untouched (Karpathy §3
  surgical changes). Two-init alternative would have meant either touching
  every existing call site or marking the original `init` deprecated — both
  cost more for no semantic gain.
- **Hook signature: `async throws` vs. `Void`.** Chose `async throws` so the
  Phase-10 GameKit adapter can surface real submit failures back into the
  existing `GameCenterSink.submitScoreIfEligible` `do/catch` (which is already
  designed to swallow errors per §How.3.4). Cost today is zero — the default
  no-op closure doesn't throw and doesn't suspend.
- **Did NOT remove the `_ = (puzzleId, difficulty)` discards.** They remain
  because Phase 10 may need either for auxiliary logging (e.g. OSLog
  `private` puzzleId stamping per design.md §How.3.4); keeping the locals
  named avoids a churn-only diff next phase.

## 偏離 (Deviations)

- **design.md §How.3.1 unchanged.** Re-read lines 242-258: the spec already
  states `GameState.elapsedSeconds × 100 → Int64 centiseconds`,
  `ELAPSED_TIME_CENTISECOND`, `mm:ss.SS`, and the issue-#17 note. Nothing
  stale. Dispatch said "if anything's stale, fix" — nothing was, so no edit.
- **`GameCenterSink.swift` unchanged.** Re-read top-to-bottom: the sink
  receives `elapsedSeconds: Int` from `puzzleCompleted` and forwards it
  verbatim to `client.submitScore(elapsedSeconds:)`. No double-conversion
  risk. Dispatch said "verify the sink's call site passes the correct value
  ... don't double-convert" — verified, no change needed.

## 未決 (Open questions)

1. **GKLeaderboard submission wiring deferred to Phase 10.** The default
   `submitScoreHook = { _, _ in }` is a deliberate no-op. Phase 10 must
   replace this with a real `GKLeaderboard.submitScore(value: Int64,
   leaderboardIDs: [String], ...)` adapter, injected at the
   `AppComposition/Live.swift::LiveGameCenterClient(...)` construction site.
   The conversion test (`LiveGameCenterClientSubmitTests`) still passes
   today via the spy, so the multiply is locked-in regardless of when
   Phase 10 lands.
2. **Hook injection at composition root.** `AppComposition/Live.swift:48`
   still constructs `LiveGameCenterClient(authDriver: GKAuthDriver())` —
   no second argument. Phase 10 will add the GameKit adapter closure here.
   No change today (Karpathy §2 simplicity — don't add an empty closure
   to production wiring just to look explicit).

## Implementation plan

1. `LiveGameCenterClient.swift`:
   - Add `public typealias SubmitScoreHook = @Sendable (String, Int64) async throws -> Void`.
   - Add stored `private let submitScoreHook: SubmitScoreHook`.
   - Extend `init` with optional `submitScoreHook = { _, _ in }`.
   - Rewrite `submitScore(...)` body: compute `Int64(elapsedSeconds) * 100`,
     resolve `LeaderboardIDs.id(for: leaderboardKind)`, invoke hook.
   - Replace the stale "filled in 7.3" header comment with the actual story.
2. `LiveGameCenterClientSubmitTests.swift` (NEW):
   - `SubmitSpy` actor (Sendable-safe call capture).
   - 3 `@Test`s: 251 s → 25100, 0 → 0, 7200 → 720_000. Each also asserts
     the resolved leaderboard ID matches `LeaderboardIDs` for that kind.

## Verification

- `swift build` → Build complete (0 warnings, 0 errors).
- `swift test` → **355 passed** (was 352, +3 as targeted).
- Audit grep `\* 100` across `Packages/SudokuKit/Sources` — confirmed one
  multiply site (LiveGameCenterClient.swift). Sink + adapter pass Int through.
- Public `GameCenterClient.submitScore` signature byte-identical (callers
  still pass `Int seconds`).

## Files changed

| File | Δ | Change |
|------|---|--------|
| `Packages/SudokuKit/Sources/GameCenterClient/Live/LiveGameCenterClient.swift` | -7/+30 | Add `SubmitScoreHook` typealias + stored hook; default-arg init keeps backward compat; rewrite `submitScore` body to do `Int64(elapsedSeconds) * 100` and invoke the hook with resolved leaderboard ID. Header comment updated to cite §How.3.1 + impl-notes. |
| `Packages/SudokuKit/Tests/GameCenterClientTests/LiveGameCenterClientSubmitTests.swift` | NEW (+86) | 3 `@Test`s using a `SubmitSpy` actor: 251→25100, 0→0, 7200→720_000; each asserts the leaderboard ID matches `LeaderboardIDs`. |

Test delta: 352 → 355 (+3). Build: 0 warnings.
