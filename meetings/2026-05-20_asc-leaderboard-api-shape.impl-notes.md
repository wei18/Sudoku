# Impl Notes — ASC Leaderboard API shape fix (2026-05-20)

Status: COMPLETE
Owner: Senior Developer
Dispatched by: Leader
Started: 2026-05-20
Completed: 2026-05-20
Issue: https://github.com/wei18/Sudoku/issues/17
Branch: fix/asc-leaderboard-api-shape (Leader-managed)

## Problem statement

`swift run ASCRegister apply` POST to `/v1/gameCenterLeaderboards` returned HTTP 409
with four field-level errors:

1. `recurrenceRule`: Expected STRING, got OBJECT
2. `defaultFormatter`: Expected STRING, got OBJECT
3. `defaultFormatter`: must be one of `ELAPSED_TIME_CENTISECOND` (and other enums)
4. `scoreFormat`: not an attribute on `gameCenterLeaderboards`

Current body builds nested objects for `defaultFormatter` and `recurrenceRule`, and uses
a non-existent attribute `scoreFormat`. Three previously-`UNCONFIRMED` shapes are now
resolved by the real 409 response.

## Design decisions

- **Adopt ASC ceiling: `ELAPSED_TIME_CENTISECOND`** (2 decimal places, mm:ss.SS). Apple's
  highest-precision elapsed-time formatter. design.md §How.3.1 previously specified
  `mm:ss.SSS` (ms, 3 decimals) — amended to `mm:ss.SS` (centiseconds, 2 decimals). Internal
  `PersonalRecord` keeps ms precision; conversion happens only at the GC submit boundary.
- **Drop `scoreRangeStart` / `scoreRangeEnd` from create body**. Error #4 ("not an attribute
  on gameCenterLeaderboards" for `scoreFormat`) implies the schema validator rejects unknown
  attributes. We had no documented home for these range fields after `defaultFormatter`
  becomes a plain string. v1 leaderboards accept any submitted score; the 2-hour upper bound
  is enforced client-side by §How.3.1 abandon rule (>7200 s → skip submit). See §偏離.
- **`recurrenceRule = "DAILY"`** — best guess. Error said "Expected STRING" but didn't
  enumerate allowed values. Documented in §未決 for Leader to validate on next apply.
- **Code-audit of ms→centisecond conversion** — The dispatch prompt specified dividing
  `elapsedMilliseconds` by 10 in `GameCenterSink`. Audit finding: the current
  `GameCenterClient.submitScore` protocol takes `elapsedSeconds: Int`, not ms; and
  `LiveGameCenterClient.submitScore` is a stub that throws `notAuthenticated`. There is no
  live submission path today. Therefore there is no actual mid-flight conversion to fix in
  `GameCenterSink`; the conversion (`elapsedSeconds × 100` for centiseconds, instead of
  design.md's prior `× 1000` for ms) belongs at the Live GC submit call site when that
  lands (next Phase 7.3 task). Recorded in §未決 #2.

## 折衷 (Tradeoffs)

- **Plain string `recurrenceRule = "DAILY"` vs ISO-8601 duration `"P1D"`** — ASC error
  named the field but not the enum domain. `DAILY` matches the documented GC leaderboard
  recurrence UI ("Daily / Weekly / Monthly"). If next apply rejects, swap to `WEEKLY`/
  `MONTHLY` is not the question — the question is whether the value is `DAILY` or `P1D`.
  Picking `DAILY` first because it matches the human-facing ASC console terminology.

## 偏離 (Deviations)

- **Removing `scoreRangeStart` / `scoreRangeEnd` from POST body** vs dispatch §未決 #2
  guidance. Dispatch said: "if you can't find a definitive answer, REMOVE them from the
  body entirely for v1". Confirmed no Apple docs surface a `scoreRange*` attribute on
  `gameCenterLeaderboards` at create time. Removed. The 2-hour upper bound is enforced
  client-side already (§How.3.1 row 4 of edge-case table). `Config.leaderboardScoreMaxMilliseconds`
  constant retained — it's referenced by the abandon-detection logic, just no longer sent
  to ASC. Documented in §未決 #3 in case Leader wants a later round to surface this through
  the leaderboard's separate `scoreFormatConfig` endpoint (out of scope for issue #17).

## 未決 (Open questions)

1. **`recurrenceRule` exact string value**: chose `"DAILY"`. If next apply round returns a
   422 with "must be one of: …", swap to whatever the enumeration says (likely `WEEKLY`/
   `MONTHLY` aren't right since we want daily; alternates are `P1D` / `ONCE_PER_DAY`).
   Leader to validate on next `swift run ASCRegister apply`.
2. **ms→centisecond conversion site** for live GC submission: should live in the future
   `LiveGameCenterClient.submitScore` when it's implemented (Phase 7.3), as
   `score = Int64(elapsedSeconds) * 100`. The current dispatch prompt asked to insert
   `/ 10` at `GameCenterSink` but there is no millisecond value flowing through Sink today
   — the protocol API takes `elapsedSeconds: Int`. No-op for this issue; flagged so Phase
   7.3 plan picks up the change.
3. **Where do score range constraints live in ASC?** Possibly on a separate
   `gameCenterLeaderboardEntrySubmissions` schema or in the localization payload. Not
   blocking issue #17. Defer to Phase 9 polish if Apple's leaderboard UI shows unbounded
   ranges after this fix lands.

## Implementation plan

1. `Config.swift`: replace `scoreFormatType` with `defaultFormatter` (string,
   `"ELAPSED_TIME_CENTISECOND"`); replace `recurrenceDurationDays` with `recurrenceRule`
   (string, `"DAILY"`). Remove related UNCONFIRMED comments.
2. `ASCClient.swift::createLeaderboard`: rename request key `scoreFormat` → `defaultFormatter`;
   value is a plain string now. Replace nested `recurrenceRule` object with plain string.
   Delete nested `defaultFormatter` object containing scoreRange fields. Remove UNCONFIRMED
   comments that are now resolved; keep the one about `gameCenterDetail` endpoint shape
   (already confirmed working separately per dispatch).
3. `design.md §How.3.1`: amend format `mm:ss.SSS` → `mm:ss.SS`, "毫秒" → "百分秒", add note
   re ASC API ceiling and internal-vs-boundary precision.
4. `ConfigConsistencyTests.swift`: add assertion `defaultFormatter == "ELAPSED_TIME_CENTISECOND"`
   for all 3 leaderboards, and `recurrenceRule == "DAILY"`.
5. Skip the `GameCenterSink` "divide by 10" test from dispatch §Tests #6 — no such code
   path exists yet (see §未決 #2). Will be picked up when Live submit lands.

## Verification

- `mise exec -- swift build` → Build complete (0 warnings, 0 errors).
- `mise exec -- swift test --filter ASCRegister` → 22 passed (was 20, +2).
- `mise exec -- swift test` (full suite) → 342 passed in 65 suites (was 340, +2).

## Files changed

| File | Δ | Change |
|------|---|--------|
| `Packages/SudokuKit/Sources/ASCRegister/Config.swift` | -10/+8 | `scoreFormatType` → `defaultFormatter` (= `"ELAPSED_TIME_CENTISECOND"`); `recurrenceDurationDays` → `recurrenceRule` (= `"DAILY"`); UNCONFIRMED comments removed. |
| `Packages/SudokuKit/Sources/ASCRegister/ASCClient.swift` | -19/+10 | `createLeaderboard` body: drop `scoreFormat` (not a valid attribute), drop nested `defaultFormatter` object with scoreRange fields, flatten `recurrenceRule` to string. Resolved-UNCONFIRMED comments removed. |
| `docs/design.md` | -1/+3 | §How.3.1 format `mm:ss.SSS` → `mm:ss.SS`, 毫秒 → 百分秒, score range `7_200_000` → `720_000`; `× 1000` → `× 100`; added ASC ceiling note linking issue #17. |
| `Packages/SudokuKit/Tests/ASCRegisterTests/ConfigConsistencyTests.swift` | +13 | Two new @Test funcs asserting `defaultFormatter == "ELAPSED_TIME_CENTISECOND"` and `recurrenceRule == "DAILY"` for all 3 boards. |

Test delta: 340 → 342 (+2). No new test file (per §未決 #2, the dispatch-requested
`GameCenterSink` divide-by-10 test has no production path to test).

## UNCONFIRMED markers

Removed (resolved by 409 response):
- `Config.swift:94-97` — `scoreFormatType` enum value (resolved: `ELAPSED_TIME_CENTISECOND`)
- `Config.swift:104-106` — `recurrenceRule` nesting shape (resolved: plain string)
- `ASCClient.swift:91-92` — "exact `type` literal and recurrence nesting"
- `ASCClient.swift:102` — "minimum/maximum field names" for score range
- `ASCClient.swift:107-108` — "ASC may want DURATION_DAYS / P1D / frequency enum"

Kept (out of scope for issue #17):
- `ASCClient.swift:71-74` — `gameCenterDetail` endpoint shape (confirmed working per Leader)
- `ASCClient.swift:82-84` — relationship path for listLeaderboards (confirmed working —
  used in plan/apply happy-path, no error reported)
