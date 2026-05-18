# 2026-05-18 / 2026-05-19 — Phase 1 + Phase 2 Execution

Session continuation of `ae54f5ea-6b89-4f59-9d9f-cafb8dff08f6`.
Mode: AI Collaboration Mode (Leader + multiple Developer subagent dispatches).

## Goal

Execute plan.md Phase 0 (prerequisite gates) → Phase 1 (repo bootstrap + tooling) → Phase 2 (SudokuEngine pure core). Land all locally-completable work as commits; defer ASC / GitHub UI work to user.

## Decisions

### Repo collapse (2026-05-17 carryover)
1. **Implementation lives in this same repo** (Sudoku-spec), not a sibling `Sudoku/`. All path references in plan.md / foundations.md / README.md updated.

### Tooling architecture (Phase 1)
2. **Tuist** chosen as Xcode-project generator (not xcodegen, not manual Xcode UI). `Project.swift` is source of truth; `*.xcodeproj` / `*.xcworkspace` gitignored.
3. **lefthook** runs three pre-commit commands in parallel: `gitleaks` (secret content scan), `hygiene` (file-name pattern check folded in from spec'd `test_repo_hygiene.sh`), `swiftlint`. No standalone shell hygiene script.
4. **mise backend**: all 6 tools (swiftlint / swiftformat / xcbeautify / gitleaks / lefthook / tuist) via `aqua:<owner>/<repo>` plugin format. No `ubi:` fallbacks needed in practice.
5. **gitleaks pin**: bumped 8.18 (spec) → 8.30.1 (aqua registry's available tag). Still satisfies "≥ 8.18".
6. **Swift tools version**: bumped 6.0 (spec) → 6.2 in `Package.swift` because `.iOS(.v26)` / `.macOS(.v26)` require PackageDescription 6.2.

### SudokuEngine architecture (Phase 2)
7. **Solver propagation seam**: `PuzzleGenerator` runs its own fixed-point loop using `Solver.applyOnce(.nakedSingle)` and `applyOnce(.hiddenSingle)` directly rather than `Solver.propagate()`, because the latter has a pre-existing infinite-loop bug when only naked-pair eliminations make progress (Phase 2.4 follow-up filed).
8. **PuzzleCalibrator skipped for Hard**: `calibrate()`'s exponential `branchingFactor` DFS is unusable on Hard low-clue boards. Generator uses cheap clue-count band check + UniquenessValidator for Hard correctness; `accepts(..., as: .medium)` is called only for Medium puzzles.
9. **Masking strategy**: single-pass progressive removal in RNG-shuffled cell order; each tentative removal accepted iff propagation alone re-derives the solved grid. Per-difficulty clue floors: Easy 42, Medium 32, Hard 26.
10. **Generator retry budget**: N=32 attempts; each attempt mutates seed via `seed + attemptIndex`. On exhaustion → throw `GeneratorError.exhausted`.
11. **Frozen snapshot contract** (cross-arch determinism per design.md §How.4.6): `(seed=0, .v1)` outputs locked in `Tests/SudokuEngineTests/Fixtures/PuzzleGeneratorSnapshots.swift`. All three difficulties share the same solved grid; only the mask differs.
12. **`Board.Equatable` quirk**: `Board` compares both `cells` and `givenMask`. Tests comparing generated puzzle vs. expected solution compare `.cells` only (the solved grid has empty givenMask, but a `Board(clues:)` reconstruction has populated givenMask).

### Tuist deviation
13. **Project generated at repo root** (not under `App/` as plan.md §1.4 hints) — Tuist anchors output at the manifest's directory. Functional outcome matches the spec (multiplatform App, bundle `com.wei18.sudoku`, iOS 26 + macOS 26, links `SudokuUI`); only the path detail differs. plan.md left untouched per hard constraint.

## Rejected alternatives

- **xcodegen** for Xcode project generation: ecosystem older, less Swift-native; Tuist won.
- **Standalone `ci_scripts/test_repo_hygiene.sh`**: redundant with `lefthook` + `gitleaks`. Folded into `lefthook.yml`.
- **Continuing the dead subagent's WIP 2.7 files**: cleaned up + restarted from scratch in fresh dispatch. Cleaner than salvaging partial work.

## Hand-offs

### Subagent dispatches this session

| Dispatch | Scope | Outcome |
|---|---|---|
| Software Architect | Apply path collapse (`Sudoku/` → repo root) across plan.md / foundations.md / README.md | All 55 plan.md + 2 foundations.md occurrences updated; 1 prose note retained for historical context |
| general-purpose | Phase 0 prerequisite gates | 3/3 PASS; SplitMix64 cross-arch byte-identical; Hard p95 = 2.23 ms; ASC policy clear |
| general-purpose | Phase 1.1-1.7 (local portion) | 4 commits; mise + lefthook + gitleaks + SudokuKit skeleton + entitlements + ci_scripts; 4 manual items deferred to user |
| general-purpose | Phase 1.4 Tuist completion | Project.swift + tuist generate + xcodebuild green both platforms |
| general-purpose | Phase 2.1-2.6 SudokuEngine | 6 commits; Board / Conflict / SplitMix64 / Solver / UniquenessValidator / PuzzleCalibrator; subagent then hit usage limit |
| general-purpose | Phase 2.7-2.8 (fresh dispatch) | 2 commits; PuzzleGenerator + Move/UndoStack; 74/74 tests pass |

### Phase 0 evidence
`meetings/2026-05-17_phase0-gates.md` — SplitMix64 reference vectors + p95 measurements + App Store policy conclusion.

### Plan.md correction
plan.md §0.1 `seed=42` reference values were wrong in the original draft; Phase 0 subagent corrected them to match canonical Vigna output.

## Open questions / Phase 3 follow-ups

1. **`Solver.applyNakedPair` infinite-loop bug**: needs either fix-in-place or documented unsafe-to-call warning. Affects future GameState usage if it calls `Solver.propagate()` on a partially-clued board.
2. **`PuzzleCalibrator.calibrate` exponential branchingFactor**: needs DFS budget cap or short-circuit at `branchingFactor > 2`. Currently usable only on Easy/Medium boards.
3. **`Move.previous` capture in Phase 3**: `GameState.placeDigit` must read the cell's prior digit BEFORE writing the new one and pass it as `previous:` to `UndoStack.push`. Without that, undo can't restore previous digits.
4. **Generator RNG seam**: For testing exhaustion paths cleanly, Phase 3 (or a Phase 2.7 follow-up) could add `protocol PuzzleGenerating` with injectable RNG.
5. **User-side manual work outstanding**: Xcode Cloud workflows in ASC, GitHub public repo + Secret Scanning Alerts + branch protection, ASC bundle ID + iOS/macOS app records + CloudKit container `iCloud.com.wei18.sudoku`.

## Final state going into Phase 3

- 29 commits, working tree clean.
- 74 tests pass (`swift test --package-path Packages/SudokuKit`), 0.19s wall.
- 0 warnings on Swift 6 strict concurrency.
- Phase 0 / 1 / 2 all green; design.md §How.4 status **FINAL**.

## Next session

Phase 3 — `GameState`. Builds on `SudokuEngine`; introduces state machine (idle / playing / paused / completed / abandoned), Clock-injected `elapsedSeconds`, debounced save trigger, Telemetry event emission. Lighter than Phase 2 (5 steps vs 8) but introduces the first protocol seam consumed by SudokuUI.
