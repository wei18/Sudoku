# M16 — Extract `utcDayString` Shared Helper (impl-notes)

- **Issue**: GH #69 (Wave 3 audit M16, refactor)
- **Branch context**: applied on top of current `refactor/m11-livepersistence-actor` working tree (no main branch checkout — Leader will rebase/cherry-pick as needed)
- **Date**: 2026-05-24

## Location Decision — Option C (SudokuEngine)

Chosen **Option C**: add `Packages/SudokuKit/Sources/SudokuEngine/UTCDay.swift`.

Reasoning:
- SudokuEngine is the deepest leaf (depends on nothing); all four callers either already import it directly (`PuzzleStore`, `Persistence/SavedGameStore`) or reach it transitively through `Persistence → GameState → SudokuEngine` (`GameCenterClient`).
- Option A (new `SudokuTime` target) is over-engineered for a one-function utility.
- Option B (co-locate in `Telemetry`) inverts dependency direction — `PuzzleStore` would gain a `Telemetry` dep just to format a date.
- No Package.swift change to declare the new file (target globbed).
- For `GameCenterClient`, added `internal import SudokuEngine` — this works because Persistence (already a GameCenterClient dep) re-exports SudokuEngine transitively under SwiftPM's `InternalImportsByDefault`. Verified empirically: build succeeds without touching Package.swift.

## Force-Unwrap Elimination

Single `TimeZone(identifier: "UTC") ?? .gmt` fallback in `UTCDay.utcCalendar` — `.gmt` is a non-optional `TimeZone` constant, so no swiftlint disable is needed. The four prior `// swiftlint:disable:next force_unwrapping` lines were deleted along with their host functions.

## Call Sites Updated (4 files + 2 test files)

| File | Range removed | Range edited |
| --- | --- | --- |
| `Sources/SudokuEngine/UTCDay.swift` | (new file, 43 LOC) | n/a |
| `Sources/PuzzleStore/PuzzleIdentity.swift` | L52–L61 (helper) | L28 (call site) |
| `Sources/PuzzleStore/PuzzleStore.swift` | n/a | L55, L125 (call sites) |
| `Sources/GameCenterClient/SubmitGuards.swift` | L86–L98 (helper + comment) | L23 (added import), L46 (call site) |
| `Sources/GameCenterClient/AchievementEvaluator.swift` | L137–L146 (helper) | L23 (added import), L80 (call site) |
| `Sources/Persistence/Live/SavedGameStore.swift` | L188–L197 (`dayPrefix(for:)` helper) | L140 (call site) |
| `Tests/GameCenterClientTests/AchievementTests.swift` | n/a | L5 (added `import SudokuEngine`), L133 (call site `UTCDay.string`) |
| `Tests/GameCenterClientTests/SinkTests.swift` | n/a | L8 (added `import SudokuEngine`), L138 (call site `UTCDay.string`) |

Notes on the Persistence rename: the previous helper was named `dayPrefix(for:)` (different signature, same `"%04d-%02d-%02d"` UTC body) — the audit issue called it out as the 4th duplicate. The empty-string fallback on `TimeZone(identifier: "UTC") == nil` was unreachable in practice; the new `UTCDay` falls back to `TimeZone.gmt` which is observationally identical for the UTC literal.

## Tests touched outside spec

Two test files (`AchievementTests.swift`, `SinkTests.swift`) called `AchievementEvaluator.utcDayString(from:)` as a date→key shim against fake `PersistenceProtocol` implementations. Removing the static would have broken them. Updated to `UTCDay.string(from:)` — minimum delta required for the dedup to actually land.

## Verification

```
swift build       → Build complete!
swift test --filter "SubmitGuards|PuzzleStore|AchievementEvaluator|SavedGameStore"
                   → <see report>
rg "utcDayString" Sources/  → 0 hits (function fully removed)
rg "dayPrefix" Sources/Persistence/  → only enum-case parameter labels remain
```

## §未決

- None. Leader to decide whether to bring the existing `AchievementEvaluator.utcDay(offsetFrom:byDays:)` into `UTCDay` as well (separate helper, returns `Date` not `String`). Out of M16 scope; tracked as candidate for a future small refactor in `docs/foundations.md §Backlog` (if Leader chooses).
