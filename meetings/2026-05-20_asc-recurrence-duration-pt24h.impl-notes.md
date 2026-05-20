# ASC recurrenceDuration P1D → PT24H (issue #24)

- Status: COMPLETE

## 設計決定

Chose `"PT24H"` (24 hours, time-component form) per ASC's enum hint
("Expected an ISO 8601 duration with time components"). Simpler and more
idiomatic than the full `"P0Y0M1DT0H0M0S"` form; semantically equivalent
to 1 day for `DAILY` `recurrenceRule`.

## 未決

(none)
