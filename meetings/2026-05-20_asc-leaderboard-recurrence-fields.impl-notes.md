# Impl Notes — ASC Leaderboard recurrence fields + inspect subcommand (2026-05-20)

Status: COMPLETE
Owner: Senior Developer
Dispatched by: Leader
Started: 2026-05-20
Completed: 2026-05-20
Issue: https://github.com/wei18/Sudoku/issues/22
Branch: fix/asc-leaderboard-recurrence-fields (Leader-managed)

## Problem statement

ASC `apply` round 3 returned two remaining required-field errors on
`POST /v1/gameCenterLeaderboards`:

```
recurrenceStartDate: required
recurrenceDuration: required
```

Per design.md §How.3.1: recurrence start = 發版當日 UTC 00:00, duration = 1 day.

To break the multi-round whack-a-mole on ASC's undocumented schema, this PR
also adds an `inspect` subcommand that GETs an existing leaderboard so Apple's
full attribute set can be read in one shot.

## 設計決定 (Design decisions)

### Concern A — recurrence fields

- **`recurrenceDuration` = `"P1D"`** (ISO 8601 duration, 1 day). Modeled as a
  computed `var` on `LeaderboardConfig`, matching the sibling pattern used for
  `recurrenceRule` / `submissionType` (round 1/2). Fixed across all 3 boards.
- **`recurrenceStartDate` is computed at apply time, not stored.** A static
  helper `LeaderboardConfig.currentRecurrenceStartDateUTC(at: Date = .init())`
  returns the current UTC 00:00 ISO 8601 datetime string. Reason: hardcoding a
  date in `Config.swift` would bit-rot the moment we re-apply; the field is
  about "when does the recurrence anchor live" and "now, floored to UTC 00:00"
  matches §How.3.1 semantics ("發版當日 UTC 00:00") regardless of which day we
  invoke `apply`.
- **Wire shape: `yyyy-MM-dd'T'00:00:00Z`** (ISO 8601 datetime, UTC, no
  fractional seconds). See §未決 #1 for fallback alternatives if ASC round 4
  rejects this shape.
- **`Reconciler.Action.createLeaderboard` shape unchanged** — the start-date
  is computed inside `execute()` in `main.swift` right before the client
  call, keeping the Action enum free of time-of-execution side-effects (the
  Reconciler stays a pure function over inputs).

### Concern B — inspect subcommand

- **Scope limited to leaderboards** (KISS). Achievement inspection is out of
  scope per dispatch — flagged in §未決 #2.
- **Filter happens client-side** in `main.swift`, not as a new ASCClient
  helper. The client already exposes `listLeaderboards(detailId:)` returning
  `[APIResource]`; iterating + matching `vendorIdentifier` is two lines and
  doesn't justify a new actor method.
- **Output format: one `key=value` per line**, sorted by key for stable
  output. Matches dispatch wording exactly.
- **Exit codes**: 0 found, 1 not-found. The not-found message lists the
  collection's vendor identifiers so the operator can see what *was* found.

## 偏離 (Deviations from dispatch)

None.

## 折衷 (Tradeoffs)

- `currentRecurrenceStartDateUTC` is a *function*, not a stored property,
  because the wall-clock changes between invocations. Tests inject a `Date`
  to keep them deterministic.
- The DateFormatter is built inline with explicit `posix` locale + `UTC`
  timezone (not `ISO8601DateFormatter`) because we want the exact literal
  shape `yyyy-MM-dd'T'00:00:00Z` with no fractional-second or offset
  variability across platforms.

## 未決 (Open questions)

1. **`recurrenceStartDate` shape — UNCONFIRMED**. ISO 8601 datetime
   (`yyyy-MM-dd'T'00:00:00Z`) is the most likely candidate; ASC may instead
   want date-only (`yyyy-MM-dd`) or epoch ms. If round 4 returns a 4xx on
   this field, swap the formatter pattern. The error body will say.
2. **`inspect` achievement support — DEFERRED**. The same Apple-undocumented
   surface exists for `gameCenterAchievements`; this dispatch scopes only
   leaderboards. Add `--achievement <vendor-id>` later if needed.

## Verification

- `swift build` — 0 warnings
- `swift test` — full suite green
- Sample CLI:
  ```
  swift run ASCRegister inspect \
    --key /path/to/AuthKey_XXX.p8 --key-id XXX --issuer YYY \
    --app-id 1234567890 --leaderboard test.bootstrap.delete
  ```
