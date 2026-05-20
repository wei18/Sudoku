# Impl Notes — ASC Leaderboard sortOrder + submissionType fix (2026-05-20)

Status: COMPLETE
Owner: Senior Developer
Dispatched by: Leader
Started: 2026-05-20
Completed: 2026-05-20
Issue: https://github.com/wei18/Sudoku/issues/19
Branch: fix/asc-leaderboard-sort-submission (Leader-managed)

## Problem statement

After round-1 fixes (issue #17 — defaultFormatter / recurrenceRule / removed scoreFormat
and nested scoreRange) landed, `swift run ASCRegister apply` round-2 returned two
remaining ASC field errors on `POST /v1/gameCenterLeaderboards`:

1. `ENTITY_ERROR.ATTRIBUTE.TYPE` — `scoreSortType: 'ASCENDING' is not a valid value.
   Expected one of: 'ASC', 'DESC'`.
2. `ENTITY_ERROR.ATTRIBUTE.REQUIRED` — `submissionType: You must provide a value for
   the attribute 'submissionType'`.

Both are pure schema-token fixes; the leaderboard semantics (low-time-wins, daily best
score per player) do not change.

## 設計決定 (Design decisions)

- **`sortOrder` token = `"ASC"`** (was `"ASCENDING"`). ASC 409 response enumerated the
  valid set explicitly: `'ASC' | 'DESC'`. Semantic stays "low time = better" per
  design.md §How.3.1 "Low to High". Only the wire token changes.
- **`submissionType` = `"BEST_SCORE"`** for all 3 leaderboards. Sudoku domain demands
  retention of a player's *best* daily completion time. The alternative
  `"MOST_RECENT_SCORE"` would overwrite the stored score on each submit, destroying
  the personal-best record that the daily leaderboard exists to publish. `BEST_SCORE`
  is the only option that aligns with §How.3.1 ("保留每位玩家當日最佳完成時間").
- **Modeled as a stored `let`, not a computed-property constant.** `defaultFormatter`,
  `sortOrder`, `recurrenceRule` were all introduced as computed `var` returning a
  literal string in round 1, so `submissionType` follows the same shape for visual
  consistency. The dispatch wording "add `submissionType: String` field" is honored
  semantically — the value is fixed across all 3 boards today, so a computed `var`
  is the minimum change that matches sibling style. (Karpathy §3 surgical changes:
  do not refactor the round-1 sibling fields just to make all four `let` properties.)

## 折衷 (Tradeoffs)

- **`BEST_SCORE` vs `MOST_RECENT_SCORE` vs unknown enum names** — ASC's 409 listed
  the attribute as REQUIRED but did not enumerate the valid set. `BEST_SCORE` and
  `MOST_RECENT_SCORE` are the two values surfaced in App Store Connect's GUI for
  "Score submission type" on the leaderboard create form (per Apple support docs).
  Picking `BEST_SCORE` because it matches sudoku semantics; if ASC rejects with
  a 422 naming the legal set, see §未決 #1 for fallback order.
- **Computed `var` vs stored `let` on `LeaderboardConfig`** — see §設計決定. Choosing
  consistency with round-1 sibling fields over the dispatch-prompt's literal "field"
  wording. Test assertion treats it identically either way.

## 偏離 (Deviations)

None. Touched exactly the 3 files the dispatch listed; only the 2 attributes named.
Did not revisit any other UNCONFIRMED marker.

## 未決 (Open questions)

1. **`submissionType` exact enum value**: chose `"BEST_SCORE"`. If next apply round
   returns 422 with "must be one of: …", swap in order of likelihood:
   - `"BEST"` (shorter ASC-API style, matches `ASC`/`DESC` brevity convention)
   - `"MOST_RECENT"` would be wrong even if accepted — it loses player records;
     Leader should reject this fallback and instead consult Apple devforums.
   Leader to validate on next `swift run ASCRegister apply`.

## Implementation plan

1. `Config.swift::LeaderboardConfig`:
   - `sortOrder` returns `"ASC"` instead of `"ASCENDING"`.
   - Add `submissionType` returning `"BEST_SCORE"`.
   - Update neighboring doc comments to cite the round-2 409 response.
2. `ASCClient.swift::createLeaderboard`:
   - Add `"submissionType": config.submissionType` to the attributes dict.
3. `ConfigConsistencyTests.swift`:
   - `@Test sortOrder` — assert all 3 boards have `sortOrder == "ASC"`.
   - `@Test submissionType` — assert all 3 boards have `submissionType == "BEST_SCORE"`.

## Verification

- `mise exec -- swift build` → Build complete (0 warnings, 0 errors).
- `mise exec -- swift test --filter ASCRegister` → 24 passed (was 22, +2).
- `mise exec -- swift test` (full suite) → 344 passed (was 342, +2).

## Files changed

| File | Δ | Change |
|------|---|--------|
| `Packages/SudokuKit/Sources/ASCRegister/Config.swift` | -1/+5 | `sortOrder` value `"ASCENDING"` → `"ASC"`; add `submissionType` = `"BEST_SCORE"`; doc comments cite round-2 409 response. |
| `Packages/SudokuKit/Sources/ASCRegister/ASCClient.swift` | +1 | Add `"submissionType": config.submissionType` to attributes block in `createLeaderboard`. |
| `Packages/SudokuKit/Tests/ASCRegisterTests/ConfigConsistencyTests.swift` | +14 | Two new `@Test` funcs asserting `sortOrder == "ASC"` and `submissionType == "BEST_SCORE"` for all 3 boards. |

Test delta: 342 → 344 (+2).
