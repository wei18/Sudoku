# Impl notes — #278 Tier-1 Phase 2b — Minesweeper theme + board application

Date: 2026-06-03 · Developer subagent · branch `feat/ms-theme-phase2b-278`

## Scope (from dispatch)
Additive MS-side counterpart to Phase 2a. Give Minesweeper a concrete `Theme`
(`MinesweeperTheme`) + MS cell tokens (`\.minesweeperCell` env key), inject at
`MinesweeperAppComposition.rootView`, apply tokens to `MinesweeperBoardView`
(tokens only — Tier-0 layout untouched), add MS snapshot harness + baselines.
Do NOT touch SudokuUI / Sudoku.

## Key decisions

1. **Mirror of Sudoku's pattern.** `MinesweeperCellTokens` + `\.minesweeperCell`
   env key mirror `SudokuUI/Theme/CellTokens.swift` + `\.sudokuCell`. The
   default value of the env key is `MinesweeperTheme().cell` (same as Sudoku's
   `DefaultTheme().cell` default) — keeps un-injected previews legible.

2. **Cell tokens are MS-shaped.** `covered / revealed / flagged / mine / mineHit`
   + `number(_:) -> ThemeColor` (1–8). Distinct shape from Sudoku's
   given/selected/error tokens, exactly why they live per-app (Phase 2a rationale).

3. **Number palette dark variants.** The prototype defines `--n1..--n8` as
   single-value CSS vars (no `-dark` companion), used identically in light/dark
   in the mockup. So `number(n)` uses the same hex for light + dark. Source of
   truth: prototype tokens panel lines 51–52.

4. **MinesweeperTheme hex = prototype tokens panel** (lines 18–55). Light/dark
   pairs copied verbatim. `status.warning` = the prototype's `--status-flag`
   (`#D9822B·#E8A560`) — semantically the flag/warning token. `difficulty`
   easy/medium/hard = beginner/intermediate/expert.

5. **Board application — tokens only.** Replaced raw primitives in
   `MinesweeperCellButton`:
   - covered bg `Color.secondary.opacity(0.25)` → `cell.covered.resolved`
   - revealed bg `Color.secondary.opacity(0.08)` → `cell.revealed.resolved`
   - mine bg `Color.red.opacity(0.6)` → `cell.mineHit.resolved` (detonated look)
   - flag glyph `.orange` → `theme.status.warning.resolved`
   - mine glyph `.white` kept (burst glyph reads on the mineHit red in both modes)
   - number glyphs system colors → `cell.number(n).resolved`
   `MinesweeperCellButton` reads `@Environment(\.theme)` + `@Environment(\.minesweeperCell)`.
   GeometryReader scaling, reveal/flag toggle, layout, glyphSize: UNCHANGED.

   Note on `cell.mine` token: prototype distinguishes `cell.mine` (revealed mine,
   non-detonated, soft red bg `#FBE3E1`) from `cell.mineHit` (the detonated cell,
   solid red). The current engine/`Cell` model has no "detonated vs other mine"
   distinction at the view layer — a revealed mine is just `isMine`. Tier-0 used
   one red for all revealed mines, so we map the single revealed-mine case to
   `mineHit` (the bold detonation color, matching Tier-0's `Color.red.opacity(0.6)`
   intent). `cell.mine` (soft) is defined on the token bundle for future use when
   the engine distinguishes the two; not wired to a view branch yet. Flagged
   cells stay covered-style in Tier-0 (no separate flagged bg branch), so
   `cell.flagged` is likewise defined-but-unwired. Documented rather than dropped
   so the token set matches the prototype 1:1.

6. **Snapshot harness.** Mirrored `SudokuKit/Package.swift`'s snapshot dep
   (`swift-snapshot-testing` from 1.17.0) + `.copy("__Snapshots__")` resource on
   the MS test target. Added `SnapshotConfig.swift` mirroring Sudoku's (NSHosting
   wrapper, tolerant image strategy, XCC bundle path) but injecting
   `MinesweeperTheme()` + `\.minesweeperCell`.

7. **Snapshot states recorded.** Covered Beginner board, light + dark, iPhone.
   `init(difficulty:seed:)` yields an all-hidden idle board deterministically;
   the view's `.task { refresh() }` pulls the actor's idle snapshot which is
   also all-hidden — so the covered board renders deterministically.
   MID-REVEAL DEFERRED: a revealed/flagged state requires driving the actor
   async before render, but the view's in-body `.task { refresh() }` would
   overwrite any pre-seeded snapshot, and the async refresh does not complete
   before `host.layoutSubtreeIfNeeded()` captures the image. Reliably recording
   mid-reveal needs a production seam (pre-seeded snapshot + suppress refresh)
   = scope creep beyond "tokens only". Covered light+dark is the deterministic
   primary themed surface; Designer can visual-verify the covered-cell token,
   chrome, and accent against the prototype. Flagged me as an open question.

## Open questions for Leader
- Mid-reveal snapshot deferred (see #7). Worth a follow-up seam, or is the
  covered board sufficient for Designer visual-verify this phase?
