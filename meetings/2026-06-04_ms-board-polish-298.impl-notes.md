# Impl Notes — MS board Tier-2 polish + Mac side-rail (#298) (2026-06-04)

Status: IN_PROGRESS
Owner: Senior Developer
Dispatched by: Leader
Started: 2026-06-04

Scope: 6 items, all touching `MinesweeperBoardView.swift` (+ cell button / theme /
engine as each item needs). Commit + push after each item. Mirror Sudoku where it
has the analog.

## 設計決定 (Design decisions)

- **#7 reveal-all-mines: NO engine accessor needed.** The actor snapshot already
  exposes the full `cells` array, and `Cell.isMine` is populated for every cell once
  mines are placed (`MinesweeperEngine.placeMines` sets `isMine` on all mine cells,
  not just revealed ones). On a loss the snapshot already carries the complete mine
  set — the renderer just needs `viewModel.status == .lost` + `cell.isMine` to draw a
  mine on cells that are still `.hidden`. So #7 is a pure VIEW change: pass a
  `revealMines: Bool` (derived from status == .lost) into `MinesweeperCellButton`.
  No MinesweeperCoreKit change. (Confirms the dispatch's "add a minimal accessor IF
  needed" — not needed.)

- **#6 Mac rail content = status + mode toggle (no digit pad).** Sudoku's macLayout
  rail holds the digit pad; MS has no digit pad, so the rail holds the status bar +
  Reveal/Flag toggle. Caps: outer 900pt / board 600pt square / rail 260pt — scaled
  down from Sudoku's 960/640/260 because MS's status+toggle rail is lighter than
  Sudoku's digit pad. Board centered (not leading) since the rail is narrow.

## 偏離 (Deviations)

- **#11 partial / deferred for compact layout.** Migrated the NEW Mac layout to
  `theme.spacing.{medium,large}` tokens, but kept the compact `VStack(spacing: 12)`
  + outer `.padding()` verbatim to avoid re-recording the iPhone covered-board
  snapshot baselines (12 is between `.small`=8 and `.medium`=16; mapping it to 16
  shifted the dark baseline past the tolerant-image threshold). Full compact-layout
  token migration + deliberate baseline re-record is the remaining #11 work.

## 折衷 (Tradeoffs)

## 未決 (Open questions)
