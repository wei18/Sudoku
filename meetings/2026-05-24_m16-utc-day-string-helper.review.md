# M16 utcDayString Extraction — Code Review — 2026-05-24

## Verdict

**APPROVE.** The extraction is minimal, surgical, and correctly placed. The `SudokuEngine` (leaf) target is the right home; all four caller modules reach it through pre-existing dependency edges (PuzzleStore→SudokuEngine direct; Persistence→GameState→SudokuEngine; GameCenterClient→Persistence re-exports SudokuEngine via `public import SudokuEngine` in LivePersistence.swift, enabling the `internal import SudokuEngine` in SubmitGuards/AchievementEvaluator without a Package.swift edit). The `TimeZone(identifier: "UTC") ?? .gmt` fallback is observationally identical to UTC for the `"YYYY-MM-DD"` literal and eliminates four `// swiftlint:disable:next force_unwrapping` directives. The Persistence `dayPrefix(for:)` 4th variant (previously had an unreachable empty-string fallback) is folded into the same helper without affecting `.dailyCompletedOn(dayPrefix:)` enum-case label callers. Test shims at `AchievementTests.swift:133` and `SinkTests.swift:138` keep behavioral equivalence — both fakes still bucket by the same UTC `YYYY-MM-DD` key.

## Soundness checklist

| Check | Pass |
| --- | --- |
| Location (SudokuEngine) appropriate | ✓ |
| TimeZone fallback safe (`.gmt` ≡ UTC for date string) | ✓ |
| `dayPrefix` renamed cleanly (only enum-case labels remain) | ✓ |
| Test shims updated (`UTCDay.string(from:)` equivalent) | ✓ |
| 0 hits for old function name `utcDayString` | ✓ (only doc-comment mentions in PuzzleStore.swift:23,122 — descriptive, not symbols) |
| Public API minimal (`enum UTCDay { static func string(from:) }`) | ✓ |
| All 4 call sites use new helper | ✓ (SubmitGuards:47, AchievementEvaluator:81, SavedGameStore:140, PuzzleIdentity:28 + PuzzleStore:55/125) |

## Required changes

None. Optional follow-up (out of M16 scope, per impl-notes §未決): consider folding `AchievementEvaluator.utcDay(offsetFrom:byDays:)` into `UTCDay` in a future small refactor — track in `docs/foundations.md §Backlog` if Leader chooses.

## Notes / observations (non-blocking)

- The two surviving `utcDayString` matches in `PuzzleStore.swift` lines 23 and 122 are descriptive doc-comment prose (`"In-memory cache of fetchDailyTrio. Keyed by (utcDayString, ...)"` and `"stableHash(generatorVersion, utcDayString, difficulty)"`) — these refer to the conceptual key, not the deleted symbol. Leaving as-is is fine; renaming to `utcDay` in prose would be a nit, not a defect.
- `LivePersistence.swift` only gained `public import SudokuEngine` (line 16) — a deliberate re-export to satisfy `GameCenterClient`'s `internal import SudokuEngine`. Correct and minimal.
- `Package.resolved` change is unrelated noise (likely an SPM resolve side-effect); not part of this refactor.
