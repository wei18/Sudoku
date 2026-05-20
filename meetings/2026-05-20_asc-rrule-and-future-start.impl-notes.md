# ASC recurrenceRule RRULE syntax + recurrenceStartDate future-only (issue #26)

- Status: COMPLETE

## 設計決定

Round-5 ASC 409 revealed two more contract details:

1. `recurrenceRule` is an iCalendar RFC 5545 RRULE string of the form
   `FREQ=[MINUTELY,HOURLY,DAILY];INTERVAL=$INT`. Picked `"FREQ=DAILY;INTERVAL=1"`
   for daily cadence — minimum-viable RRULE consistent with our `PT24H`
   `recurrenceDuration`.
2. `recurrenceStartDate` must be strictly in the future. Renamed
   `currentRecurrenceStartDateUTC(at:)` → `nextRecurrenceStartDateUTC(at:)`
   and changed the algorithm:
     - Floor `now` to today's UTC 00:00 via gregorian calendar pinned to UTC.
     - If today's midnight ≤ `now`, add 86_400 s → tomorrow's UTC midnight.
     - Else return today's midnight (defensive branch for injected pre-epoch
       test dates; unreachable with the real wall clock).
   Practically every real call returns tomorrow's UTC 00:00, guaranteeing
   strict-future per ASC's rule.

Test file renamed `RecurrenceStartDateTests.swift` → `NextRecurrenceStartDateTests.swift`
to match the new function. Added a 5th test that round-trips the formatter
output back to `Date` and asserts `>` input across all 4 boundary inputs.

## 未決

1. `FREQ=DAILY;INTERVAL=1` was inferred from ASC's round-5 enum hint listing
   `MINUTELY,HOURLY,DAILY` and `INTERVAL=$INT`. Apple's docs do not state
   whether they enforce the UTC midnight reset window we expect from a
   daily leaderboard. If round-6 accepts the apply but cycles roll at an
   unexpected wall time, we'll learn the actual semantics empirically —
   no further `recurrenceRule` shape changes anticipated unless rejected.
