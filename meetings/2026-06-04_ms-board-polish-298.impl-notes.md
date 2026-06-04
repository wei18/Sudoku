# Impl Notes — MS board Tier-2 polish + Mac side-rail (#298) (2026-06-04)

Status: COMPLETE
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

- **#8 mine glyph done; contrast/bevel DEFERRED (sandbox blocks baseline re-record).**
  Swapped the mine glyph `burst.fill` → `xmark.octagon.fill` (clearer hazard read);
  detonated mine = white on `mineHit` red, surfaced mine = `error` token on soft
  `mine` fill. The glyph only shows on revealed/lost cells, so it does NOT touch the
  covered-board snapshot baseline. The covered-vs-revealed CONTRAST raise + raised-
  cell bevel affordance were prototyped (deeper `covered` + new `coveredEdge` token +
  strokeBorder overlay) but REVERTED: they alter every covered cell, which churns the
  only recorded MS board snapshot (covered idle board), and the sandbox denies both
  `rm` of the stale PNG and the record-mode test run — so I could not regenerate the
  baseline to keep tests green. Deferred to a #298 follow-up that the Leader can
  re-record (delete the 2 covered PNGs + run with record mode). See §未決.

- **#9 ticker .task(id:) key = ObjectIdentifier(viewModel).** Sudoku keys its
  ticker on `identity.puzzleId`; MS has no per-game id, and the whole VM is swapped on
  Retry (so a `.task` without id would NOT restart). Keyed on the VM's object identity:
  Retry replaces the VM → new identity → loop restarts with a fresh clock. The loop
  gates on `status == .playing` and stays alive (cancelled on disappear) once terminal.

- **#11 spacing tokens: outer padding migrated, compact VStack literal deferred.**
  `.padding()` → `theme.spacing.medium` is value-identical (both 16), so safe. The
  compact `VStack(spacing: 12)` is the only remaining spacing-scale literal; migrating
  it (→ medium=16) shifts the covered-board snapshot, which the sandbox can't
  re-record. Grid geometry constants (`minCellSide: 32`, `cellSpacing: 2`, cell
  `cornerRadius: 4`) are tap-target / shape constants, NOT theme-spacing-scale values —
  intentionally left as literals.

## 折衷 (Tradeoffs)

- **#7 lost-flagged-mine keeps its flag glyph (not the mine).** On loss a cell that
  the player correctly flagged stays flagged rather than flipping to a mine glyph —
  `showsLostMine`'s `cell.state != .revealed` only repaints HIDDEN mines, while the
  content builder guards `cell.state == .hidden`, so flagged mines fall through to the
  `.flagged` case. Rationale: a correctly-flagged mine reading as a flag is the
  satisfying "you found it" signal; mirrors classic minesweeper. Wrong-flag marking
  (flagged-but-not-a-mine) is out of scope for #7 (it only asks to reveal mines).

## 未決 (Open questions)

- **#8 contrast/bevel re-record (load-bearing for the Designer #8 sign-off).** The
  covered-vs-revealed contrast + raised-tile affordance need the covered-board
  snapshot baseline re-recorded, which this sandbox cannot do (no `rm`, no record run).
  Leader: either re-record locally on a #298 follow-up, or confirm the contrast tweak
  is wanted before I re-apply. Default taken: shipped only the glyph (no baseline
  churn); contrast/bevel held.
