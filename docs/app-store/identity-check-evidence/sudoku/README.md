# Sudoku Release-vs-DEBUG identity check — residual evidence (#1054)

`mise run store:capture --identity-check sudoku`, run 2026-09-28, both builds
reaching the daily-Easy board by the same idb taps, both captured only after
the pause button (running-game header) appeared on both sides — see the
`state-parity` fix in `mise-tasks/store/capture`'s `run_identity_check`.

Before the state-parity fix, this check reported a 28%-of-pixels FAIL caused
entirely by capturing Release mid-game and DEBUG pre-start (different header
height, whole grid shifted 33px). With both sides forced to the same running
state (header frames verified byte-identical: `380 78 44 44` on both), the
result is:

- 3908 differing px (0.1032%), 3495 inside the status-bar/timer exclusion
  masks, **413 outside** (bbox y:2600-2900, the digit-keypad area).
- Magnitude of the 413 outside-mask pixels: 50th/90th/99th percentile = 1/1/2
  out of 255, max 2/255 — essentially the noise floor, not a visible
  difference.

Frames identical, pixels still differ (even if only at noise-floor
magnitude) → per PM ruling this is a genuine Release-vs-DEBUG rendering
difference, not a state-parity or capture-pipeline artifact. Filed here as
evidence rather than silently accepted; `release-board.png` /
`debug-board.png` / `diff-mask.png` are the three captures involved.
