# MS per-difficulty DAILY Game Center leaderboards + ASCRegister — impl notes

Live design decisions for the dispatch: "Add MS Game Center leaderboards mirroring
Sudoku's (per-difficulty recurring DAILY) — both the ASCRegister config AND the MS
program-side submit wiring."

## Spec-vs-reality conflict (RESOLVED — flag for Leader)

The shipped #291 work (`MinesweeperLeaderboardID`) registers per-difficulty
**best-time, non-recurring** leaderboards keyed by MS-native difficulty names:

```
com.wei18.minesweeper.leaderboard.{beginner,intermediate,expert}.besttime.v1
```

This dispatch explicitly requires leaderboards that **mirror Sudoku exactly** —
"per-difficulty recurring DAILY" with the `…{easy,medium,hard}.daily.v1` shape,
and instructs: "map to easy/medium/hard ids if the names differ, and note the
mapping." The brief therefore **supersedes #291's Decision 3** (which had said
"MS has no daily/practice split … one best-time board per difficulty").

Resolution: change the MS runtime IDs to the Sudoku-mirroring shape and register
them as recurring-daily in ASCRegister. The MS *engine* difficulty enum stays
`beginner/intermediate/expert`; only the leaderboard ID **segment** is mapped to
Sudoku's `easy/medium/hard` for byte-shape parity.

### Difficulty → leaderboard-id segment mapping (note the translation)

| MS engine `Difficulty` | leaderboard id segment | full id                                         |
|------------------------|------------------------|-------------------------------------------------|
| `.beginner`            | `easy`                 | `com.wei18.minesweeper.leaderboard.easy.daily.v1`   |
| `.intermediate`        | `medium`               | `com.wei18.minesweeper.leaderboard.medium.daily.v1` |
| `.expert`              | `hard`                 | `com.wei18.minesweeper.leaderboard.hard.daily.v1`   |

Rationale for mapping names (not keeping beginner/intermediate/expert in the id):
the brief names the exact target IDs (`…{easy,medium,hard}.daily.v1`) and demands
"mirror Sudoku exactly," whose segments are easy/medium/hard. The id is opaque to
players (only the localized title shows), so the segment choice is purely an
internal/ASC concern; mirroring keeps Sudoku and MS Config code structurally
identical.

## ASCRegister: how the GC config was made app-aware (the seam)

The GC `plan`/`apply` path (`runRemote` in main.swift) was Sudoku-only: it built
`ConfigSnapshot.live` from the hard-coded `Config.leaderboards`. I mirrored the
existing `metadata --app <sudoku|minesweeper>` precedent (#310):

- New `GCApp` enum (`sudoku` | `minesweeper`) in Config.swift, `CaseIterable`,
  String-raw — same shape as `MetadataApp`.
- `Config.leaderboards(for: GCApp)` returns the per-app set; the existing
  `Config.leaderboards` static stays as Sudoku's set (no Sudoku call site changes;
  also keeps `validate`'s `expectedXCStringsKeys` Sudoku default working unless
  `--app` is passed).
- `ConfigSnapshot.live(for:)` parameterizes the snapshot; `.live` (no-arg) stays =
  Sudoku for back-compat with every existing test/IAP path.
- `runRemote` reads an optional `--app` flag (defaults to `sudoku`) and selects the
  app's leaderboard set. Achievements + IAPs are unchanged (Sudoku-only achievements;
  IAPs already multi-app via productId match). Reconciler is NOT duplicated — it
  already takes a `ConfigSnapshot`, so only the snapshot's leaderboard list varies.

Sudoku safety: `--app` defaults to `sudoku`; `Config.leaderboards` and `.live`
unchanged; ConfigConsistencyTests still pin the 3 Sudoku ids byte-for-byte.

## Localization

Sudoku leaderboard titles come from `gc-strings.xcstrings.patch` keys
`gc.leaderboard.<difficulty>.daily.title`. For MS I add parallel keys
`gc.minesweeper.leaderboard.<difficulty>.daily.title` and teach the validate /
reconcile leaderboard-title lookup to use an app-scoped key prefix. en + zh-Hant
filled; ja/zh-Hans/es/th/ko marked `<TRANSLATE>` (translation-agent flow).

## Submit gating (daily-only?) — divergence flagged

Sudoku's `GameCenterSink.submitScoreIfEligible` submits **only when `mode == .daily`**
(practice solves never reach the leaderboard). The shipped MS submit
(`MinesweeperGameViewModel.submitBestTimeIfWon`) fires on **any** win — it has no
mode awareness (the VM isn't told daily vs practice).

Decision: keep MS submitting on all wins for this PR (surgical — Part B scope is the
difficulty→id mapping + latched non-blocking submit, not re-architecting mode
threading into the VM). The leaderboards are recurring-daily on the ASC side, so a
practice-solve submit still lands in *today's* cycle; the divergence is that MS
practice times count where Sudoku's don't. **Flagged for Leader as an open decision**
— true Sudoku-mirror would require threading the AppRoute mode (.daily/.practice)
into the VM and gating, a larger change.

## Files touched
- ASCRegister/Config.swift — `GCApp`, `leaderboards(for:)`, `.live(for:)`,
  app-scoped leaderboard localization key.
- ASCRegister/main.swift — `--app` on `plan`/`apply`/`validate`; app-aware
  `expectedXCStringsKeys`.
- ASCRegister/XCStringsParser.swift — app-scoped leaderboard title lookup.
- ASCRegister/Strings/gc-strings.xcstrings.patch — MS leaderboard title keys.
- ASCRegisterTests/ConfigConsistencyTests.swift — MS leaderboard id pins.
- MinesweeperUI/Leaderboard/MinesweeperLeaderboardID.swift — daily ids + mapping.
- MinesweeperUITests — update id-shape assertions.
