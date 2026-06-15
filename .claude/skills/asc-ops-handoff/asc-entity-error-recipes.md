# ASC `ENTITY_ERROR` fix recipes (ASCRegister apply rounds)

Hard-won map from the Game Center registration retry loop (issues #17 #19 #22 #24
#26 #31 #37 #40). Each recipe is a hint, not a guarantee — always verify against
the current `Packages/ASCRegisterKit/Sources/ASCRegister/Config.swift`.

Migrated from the retired `.claude/workflows/asc-apply-round.js` (2026-06-12); the
loop itself is now manual: `swift run ASCRegister plan|apply` → decode
`ENTITY_ERROR.<CODE>` below → patch Config.swift → re-run.

| ENTITY_ERROR code | Cause | Likely fix | Rounds |
|---|---|---|---|
| `LOCALE_INVALID` | Apple rejects the leaderboard/achievement locale code | `Config.ascLocaleCode`: script-only `zh-Hant`/`zh-Hans` (not `zh-Hant-TW`), and **bare `th`/`ko` for Game Center too** — GC rejects region-suffixed `th-TH`/`ko-KR` (live leaderboard-loc apply 2026-06-15), same as IAP/metadata. Region forms `en-US`/`es-ES` ARE accepted by GC. | #31 #37 + th/ko 2026-06-15 |
| `INVALID_POINTS_RANGE` | Achievement points must be 0–100 | Clamp every achievement points value to 0–100 (no raw centiseconds / large counts) | #40 |
| `RECURRENCE_RULE_INVALID` | Apple wants RFC 5545 RRULE, not plain `DAILY` | `recurrenceRule: "DAILY"` → `"FREQ=DAILY;INTERVAL=1"`; update ConfigConsistencyTests | #26 |
| `RECURRENCE_START_CANNOT_BE_PAST` | `recurrenceStartDate` must be future-only | Use `LeaderboardConfig.nextRecurrenceStartDateUTC()` (tomorrow UTC 00:00); NextRecurrenceStartDateTests covers the 23:59 UTC edge | #26 |
| `RECURRENCE_DURATION_INVALID` | Duration needs ISO 8601 *with time components* | `"P1D"` → `"PT24H"`; update tests | #24 |
| `RECURRENCE_START_DATE_REQUIRED` | `recurrenceStartDate` + `recurrenceDuration` both required | Recurring leaderboards include both fields; assert in ConfigConsistencyTests | #22 |
| `SCORE_SORT_TYPE_INVALID` | Invalid `scoreSortType` OR missing `submissionType` | `scoreSortType ∈ {ASCENDING, DESCENDING}`; `submissionType ∈ {RECURRING, MANUAL}`; verify ASCClient request shape | #19 |
