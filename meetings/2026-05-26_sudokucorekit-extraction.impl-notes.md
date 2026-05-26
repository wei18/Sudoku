# SudokuCoreKit Extraction — Impl Notes

**Branch**: `worktree-agent-a3f45bd926b01a33e` off `fb7a987`
**Mission**: Extract pure-Swift `SudokuEngine` + `GameState` from `Packages/SudokuKit/` into a NEW sibling SwiftPM package `Packages/SudokuCoreKit/` to break the Telemetry → GameState/SudokuEngine import cycle and enable a future Telemetry-only extraction.

## Spec discrepancy noted at start
- Dispatch prompt requires reading `meetings/2026-05-26_module-split-proposal.md` — **this file does not exist** in origin/main. Proceeding with dispatch prompt as authoritative spec (it contains the full rationale + scope inline).

## Pre-flight audit
- All files in `Sources/SudokuEngine/` and `Sources/GameState/` use only `import Foundation` — qualified as pure-core.
- GameState imports SudokuEngine via `internal import`/`public import` — cleanly stays inside SudokuCoreKit.
- 9 downstream modules in SudokuKit import SudokuEngine and/or GameState. After move, their target `dependencies:` lists must reference the new SudokuCoreKit products.
- 11 test files (across `PersistenceTests`, `GameCenterClientTests`, `PuzzleStoreTests`, `SudokuUITests`, `TelemetryTests`) use plain `import SudokuEngine` / `import GameState`. After move these become products of SudokuCoreKit; the test targets must declare the SudokuCoreKit products as deps. Plain `import` syntax unchanged.
- App target (`App/**`) has zero direct imports of `SudokuEngine`/`GameState` — Project.swift package list only needs the new local package added (so SwiftPM resolver sees it).

## Scope decisions
- Move ONLY: `Sources/SudokuEngine/**`, `Sources/GameState/**`, `Tests/SudokuEngineTests/**`, `Tests/GameStateTests/**`.
- DO NOT move: `Mode.swift` is inside `SudokuEngine/` already → moves with it. `UTCDay.swift`, `GameCenterIdentifiers.swift` also inside SudokuEngine/ → move with it (per dispatch: pure types qualify).
- Telemetry stays in SudokuKit and now imports SudokuCoreKit products to access GameState + SudokuEngine — the cycle is unchanged on the import graph (Telemetry → SudokuCoreKit → 0), but the package-level seam now exists so a future Telemetry extraction is unblocked.

## Commit plan (commit-first per methodology §10)
1. Create SudokuCoreKit package skeleton + Package.swift + empty dirs
2. git mv SudokuEngine source + tests; update SudokuKit Package.swift to remove + add dep
3. git mv GameState source + tests; same pattern
4. Update Tuist Project.swift (add `.local(path: "Packages/SudokuCoreKit")`)
5. Update docs/foundations.md §2

## Open questions / deviations
- None at start. Will record any mid-flight.

## 2026-05-26 strict-no-verify dispatch (3 commits on top of prep branch)

Resumed from Leader's prep branch `feat/sudokucorekit-extraction-prep` @ `63fbce4`. Prior 3 attempts hung on Monitor waiting for `swift build` / `swift test`; this dispatch was mandated to skip all verification and let Leader handle post-push validation.

### Commits added
1. `feat(modules): complete SudokuCoreKit Package.swift with SudokuEngine + GameState targets` — added `GameState` target (deps: `SudokuEngine`), `GameStateTests` test target, and `GameState` library product. Surgical: the file already had `SudokuEngine` wired so only 3 line insertions needed.
2. `refactor(modules): SudokuKit deps on SudokuCoreKit for SudokuEngine + GameState` — removed in-package `SudokuEngine` + `GameState` targets/products/test-targets; added `.package(name: "SudokuCoreKit", path: "../SudokuCoreKit")` to top-level deps; introduced two shorthand bindings `sudokuEngineDep` / `gameStateDep` (`.product(...)` form) and substituted into every impacted target. Impacted production targets: `PuzzleStore`, `Persistence`, `GameCenterClient`, `Telemetry`, `SudokuUI`, `SudokuKitTesting`, `AppComposition`. Removed obsolete test-target factory calls: `testTarget("SudokuEngine", ...)` and `testTarget("GameState", ...)`.
3. `docs(foundations): note SudokuCoreKit sibling extraction in §2` — appended ~10-line "演進（2026-05-26 module split）" subsection inside §2, preserving the existing dep-direction diagram (it remains valid).

### Decisions during edit
- **Shorthand bindings over inline `.product(...)`**: introduced `let sudokuEngineDep` / `let gameStateDep` at top of file to avoid scattering verbose `.product(name:package:)` literals across ~7 target sites. Tradeoff: one extra layer of indirection vs ~7 fewer noisy lines. Chose shorthand since the pattern repeats — matches readability bias in karpathy-guidelines §2.
- **`Project.swift` not edited**: grep confirmed the Tuist `Project.swift` has zero references to `SudokuEngine` / `GameState` / `SudokuCoreKit`. App target depends only on the `SudokuKit` umbrella product, and SwiftPM transitively resolves SudokuCoreKit through SudokuKit's `dependencies:` arrow. No Tuist change needed.
- **SwiftLint warnings on commit 2**: lefthook reported 3 swiftlint warnings (1 pre-existing `blanket_disable_command` line 2, 2 new `line_length` on lines 46 + 149). All non-blocking; the file already accepts these patterns (the original line 38 was 137 chars before this edit, so the project's de facto threshold tolerates them). Did not fix per karpathy-guidelines §3 (surgical changes — don't widen scope to lint-cleanup not requested).

### Not done (per dispatch rules)
- `swift build` / `swift test` / `git push` — Leader handles post-merge verification.
