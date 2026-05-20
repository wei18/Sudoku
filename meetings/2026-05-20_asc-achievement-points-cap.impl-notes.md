# impl-notes: ASC achievement points cap (issue #40)

**Branch**: `fix/asc-achievement-points-cap`
**Date**: 2026-05-20
**Trigger**: Round-8 ASC apply → `INVALID_POINTS_RANGE: points between 0 and 100` on first achievement POST.

## Changes

| File | Change |
|---|---|
| `Packages/SudokuKit/Sources/ASCRegister/Config.swift` | `hard.master` points 150 → 100; doc-comments updated (550 → 500; ASC 0-100 cap, issue #40) |
| `Packages/SudokuKit/Tests/ASCRegisterTests/ConfigConsistencyTests.swift` | `pointsBudget` assertion 550 → 500; added new `pointsRange` test asserting every entry is within `0...100` (regression guard for issue #40) |
| `docs/design.md` §How.3.2 | Points table: `hard.master` 150 → 100; total 550 → 500; v2 budget recomputed (500 ceiling 1000 − 500 used = 500 remaining); added note about ASC's 0-100 cap with issue #40 link |
| `docs/feature-tour.md` | Promo-copy alignment: total 550 → 500; Hard 累積 25 題 150 → 100 |

`docs/methodology.md` references "550 點" in historical narrative (round-1 retrospective) and was intentionally left as-is — that's the snapshot of what was agreed at the time, not a live spec.

## Verification

- `swift build` — clean, 0 warnings, 3.03s
- `swift test` — 364/364 passed (was 363; +1 from new `pointsRange` test)
- TODO sweep on `Sources/ASCRegister/`: 1 pre-existing TODO in `ASCClient.swift:37` ("remove if still unused after error refactor settles") — unrelated to this fix, left untouched per Karpathy Rule 3 (surgical changes).

## §未決

- **Whether ASC's "between 0 and 100" is inclusive of 100.** All capped entries (`daily.streak_7`, `practice.complete_100`, `hard.master`) sit exactly at the upper boundary. If round-9 still rejects with 100 itself failing, Leader iterates by lowering those 3 boundary entries to 95 (would bring total to 485).

Status: **COMPLETE**
