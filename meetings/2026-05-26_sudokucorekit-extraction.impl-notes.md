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
