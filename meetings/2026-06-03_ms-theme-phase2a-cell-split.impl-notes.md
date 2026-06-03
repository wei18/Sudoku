# Impl Notes — #278 Tier-1 Phase 2a: split Sudoku `cell` tokens out of base `Theme`

Date: 2026-06-03
Branch: `refactor/split-cell-tokens-278-t1-p2a`

## Goal
Pull the Sudoku-shaped `cell: CellTokens` out of GameShellUI's generic `Theme`
protocol so a second game (Minesweeper, Phase 2b) can theme its own
differently-shaped cells. Sudoku must stay byte-identical (167-test snapshot
suite is the safety net — no re-recorded baselines).

## Decisions

### `\.sudokuCell` environment key
- `CellTokens` type definition moved from GameShellUI → SudokuUI
  (`Theme/CellTokens.swift`). It is Sudoku-shaped
  (base/prefilled/userFilled/highlighted/selected/error/errorBorder).
- Base `Theme` protocol no longer declares `var cell`. Base keeps the generic
  bundles: surface, text, accent, status, difficulty, spacing.
- `NeutralTheme` (GameShellUI fallback) drops its `cell` stored prop.
- SudokuUI's `DefaultTheme` keeps `let cell = CellTokens(...)` with the SAME
  hex values (byte-identical rendering).
- New env key `\.sudokuCell` (default `DefaultTheme().cell`) added in SudokuUI.
  Views read cell tokens via `@Environment(\.sudokuCell)` instead of
  `theme.cell`.
- Injected `.environment(\.sudokuCell, DefaultTheme().cell)` at the SAME two
  points Phase 1 injects `\.theme`: `AppComposition.rootView` (live) +
  `SnapshotConfig.hostingView` (tests).

### Rationale for a dedicated env key (vs. keeping on concrete theme)
- Views in SudokuUI hold `any Theme`, which no longer exposes `cell`. A
  separate env key keeps cell-token access decoupled from the generic theme
  contract and gives Phase 2b a clean parallel slot (`\.minesweeperCell`).

## Phase 2b note
2b adds the Minesweeper equivalent: a MS-shaped `CellTokens` (different shape)
+ its own `\.minesweeperCell` env key, injected at MS's composition root +
snapshot host. No shared base-protocol cell coupling.

## Rewired readers
- `SudokuUI/Board/BoardCellView.swift`: `theme.cell.*` → `@Environment(\.sudokuCell)`
  (5 reads: errorBorder, error, selected, prefilled, base).

## Constraints honored
- Zero MinesweeperKit changes.
- Same CellTokens hex values → byte-identical snapshots, no re-record.
