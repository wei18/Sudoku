# Design-system difficulty tokens — impl notes

**Date**: 2026-05-21
**Branch**: `feat/design-system-difficulty-tokens`
**Resolves**: Brand audit §未決 #1 (option (a))

## 1. design-system.md table added

New subsection `### Difficulty (v2+)` in `docs/designs/design-system.md` (between §Status and §Contrast verification):

```
| Token              | Light                 | Dark                          | Use                                                       |
| `difficulty.easy`   | `#5C7A4F` (sage)      | `#9BB87E` (lighter sage)      | Easy puzzles — matches `accent.primary`                  |
| `difficulty.medium` | `#C97D5F` (clay)      | `#D89A82` (lighter clay)      | Medium puzzles — warm terracotta, new in v2              |
| `difficulty.hard`   | `#E6A857` (amber)     | `#EFC07F` (lighter amber)     | Hard puzzles — warm amber, new in v2                     |
```

Plus calmness-contract paragraph (difficulty-signaling only, not general accent) and cross-reference footnote to `docs/app-store/icons/finalists/light-difficulty-trio.svg` / #63.

## 2. Swift Color constants

- `Packages/SudokuKit/Sources/SudokuUI/Theme/Theme.swift` L18 — added `var difficulty: DifficultyTokens { get }` to `Theme` protocol.
- `Theme.swift` L137-149 — new `DifficultyTokens` struct (`easy` / `medium` / `hard: ThemeColor`).
- `Packages/SudokuKit/Sources/SudokuUI/Theme/DefaultTheme.swift` L49-53 — `DifficultyTokens` instance with the 3 light + 3 dark hexes.

Reused the existing `ThemeColor(light: 0xRRGGBB, dark: 0xRRGGBB)` + `Color(hex:)` helpers — no new conversion utility needed.

## 3. UI files touched

- **`Daily/DailyHubView.swift`** — `DailyPuzzleCard` now leads with a 10 pt tint circle + the difficulty label rendered in `theme.difficulty.{easy,medium,hard}.resolved` (was `text.primary`). Added private `difficultyTint` helper that maps `card.difficulty` string → token, falling back to `text.primary` for unknown strings.
- **`Practice/PracticeHubView.swift`** — segmented `Picker` `.tint(...)` and "Draw new puzzle" button `.tint(...)` now both follow the currently-selected difficulty (was static `accent.primary`). Added private `tint(for: Difficulty)` helper.

## 4. Snapshot tests

6 baselines re-recorded (all green, diffs limited to color additions, no layout shift):

- `DailyHubViewTests`: 3 (`unfinished` / `easyDone` / `allDone`)
- `PracticeHubViewTests`: 3 (`idle` / `drawn` / `shimmer`)

Procedure: flipped `SnapshotMode.recordMode` from `.missing` → `.all`, ran filtered tests, flipped back to `.missing`, re-ran — all 18 tests in 5 suites pass.

## 5. §未決

1. **Per-segment Picker tinting**: SwiftUI segmented `Picker` exposes only one `.tint(...)`, so the Practice Picker tints the *selected* chip with the active difficulty's color (the two unselected chips stay neutral). A custom segmented control would unlock all-three-tinted-simultaneously, but felt out of scope. Re-open if Brand wants the always-visible trio on the Picker.
2. **Dark-mode hexes** chosen by the AI Designer (lighter siblings of the light tokens, matching the sage→lighter-sage pattern from `accent.primary`). Not verified against AppIcon 07 dark variant (no dark-mode icon finalist exists yet). Re-check once a dark-mode icon is selected.
3. **Card background tint**: only the leading dot + label text are tinted. The card body stays neutral glass per §Liquid Glass usage. If Brand wants a stronger tint footprint (e.g. tinted border), say the word.
