# Minesweeper Release ≡ DEBUG identity check (#1054)

`mise run store:capture --identity-check minesweeper`, Release reached the
board by tap-drive (Practice tab → Beginner card → New Game), DEBUG via the
zero-click `-uitest-route board:beginner` (#1026 B-1) — both fresh boards,
captured only after the pause button appeared, judged against the same
same-build control described in the Sudoku evidence's README.

## Result: 3 runs, same-build-control criterion

| run | control outside / maxΔ | cross outside / maxΔ | verdict |
|---|---|---|---|
| 1 | 0 / 2 | 488 / 2 | **FAIL** (488 > floor 20) |
| 2 | 0 / 0 | 0 / 2 | PASS |
| 3 | 0 / 2 | 0 / 2 | PASS |

Committed images are from run 3 (clean PASS). Run 1's cross-build outside-
mask pixels (488, bbox roughly the mode-toggle/header area) are the same
small-magnitude (max channel Δ 2/255) residual glass-rendering jitter
documented elsewhere in this PR (the "Reveal"/"Flag" toggle pill,
`minesweeper.board.tapModeToggle`) — not a distinct Release-vs-DEBUG bug,
but it DOES mean the identity-check is not deterministically green: ~1/3
observed failure rate in this small sample, driven by the same per-launch
noise the rest of #1054 already found and did not solve. Header frames
identical across all three runs (`380 78 44 44`); no bottom/banner element
found at any point (this screen renders no ad banner).

Files: `release-board.png`, `control-board.png`, `debug-board.png`,
`diff-mask.png`, `control-diff-mask.png` — all from run 3.
