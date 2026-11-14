# `docs/designs/` index

Design documents for both apps. The current design is in `v3/`. Everything else in this folder is the v1/v2 record.

Status values are defined in [`docs/README.md`](../README.md).

## Current design (3.0)

| File | What it is | Status |
|---|---|---|
| [`v3/design.md`](v3/design.md) | The complete 3.0 design for Sudoku and Minesweeper: 3-tab shell, board-first layout, Liquid Glass, color layers | living |
| [`v3/prototype.html`](v3/prototype.html) | Full-screen prototype of that design | living |
| [`v3/README.md`](v3/README.md) | How the design reached its final revision | living |

The behavior of each shipped screen is specified outside this folder:

- [`docs/screen-contracts.md`](../screen-contracts.md): elements, interactions and state variants per screen.
- [`docs/navigation-flows.md`](../navigation-flows.md): routes, flow chains and negative flows.
- `mise run scan:design_contracts` checks that the 3.0 change table (`scripts/design/contracts.py`) still points at existing sections of those two files. CI runs it.

When you rename or remove a section heading or a row id in those two files, update `scripts/design/contracts.py` in the same PR and run the gate.

## v1/v2 record (historical)

These files describe the pre-3.0 UI. The HOME screen, the hand-written sidebar and the Leaderboard screen they describe no longer exist. Read them for the reasons behind a decision, not for the current layout.

| File | What it is |
|---|---|
| [`design-system.md`](design-system.md) | v1 tokens (color, type, spacing), accessibility baseline, SF Symbols list. Superseded in part by `v3/design.md` |
| [`01-root.md`](01-root.md) … [`08-settings.md`](08-settings.md) | Per-screen v1 specs: Root, Home, Daily hub, Practice hub, Board, Completion, Leaderboard, Settings |
| [`code/SnapshotMatrix.md`](code/SnapshotMatrix.md) | The v1 snapshot matrix. The live baselines are under `Packages/*/Tests/*/__Snapshots__/` |
| `code/` (`Package.swift`, `Sources/`, `Tests/`) | A standalone SwiftPM package of v1 design previews |
| [`captureguard-kit.md`](captureguard-kit.md) | RFC for a screen-capture guard (#286, parked) |
| [`sudoku-app-flow.prototype.html`](sudoku-app-flow.prototype.html) | Pre-3.0 Sudoku flow prototype; superseded frames are labelled inside the file |
| [`reminders-flow.prototype.html`](reminders-flow.prototype.html) | Reminders flow prototype (shipped) |
| [`../minesweeper/minesweeper-app-flow.prototype.html`](../minesweeper/minesweeper-app-flow.prototype.html) | Pre-3.0 Minesweeper flow prototype |

Each per-screen v1 spec has the same sections: identity, ASCII wireframe, SwiftUI preview skeleton, spec table, accessibility, rationale.

## Not in this folder

- Production Swift code: `Packages/SudokuKit/Sources/SudokuUI/`, `Packages/MinesweeperKit/Sources/MinesweeperUI/` and the shared kits.
- App Store screenshots and marketing assets: `docs/app-store/`.
- Binary design files (`.fig`, `.sketch`): the repo keeps none.
