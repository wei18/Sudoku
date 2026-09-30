# Sudoku Release ≡ DEBUG identity check (#1054)

`mise run store:capture --identity-check sudoku`, both builds reaching the
daily-Easy board by the same idb taps, captured only after the pause button
(running-game header) appeared on both sides (state-parity fix — see git
history), and now judged against a **same-build control**, not a fixed zero
threshold.

## Method

1. **Release** capture (install → uninstall-then-reinstall guarantees a
   fresh container → taps → wait for the pause button → screenshot).
2. **control** capture: uninstall + reinstall the SAME Release build, same
   taps, same wait-for-pause-button — measures the launch-to-launch noise
   floor with zero possibility of a Release-vs-DEBUG difference.
3. **DEBUG** capture: same method, the DEBUG build.
4. Compare Release-vs-control (`control`) and Release-vs-DEBUG (`cross`)
   with the identical status-bar-band + timer-rect exclusion masks. PASS
   iff `cross.outside <= max(control.outside, 20)` AND
   `cross.maxdelta <= max(control.maxdelta, 3)`.

## Result: Release ≡ DEBUG to within the single-build launch noise floor

| | outside-mask px | max channel Δ |
|---|---|---|
| control (Release vs Release) | 0 | 166 |
| cross (Release vs DEBUG) | 0 | 166 |

Both control and cross differences sit entirely **inside** the timer-rect
mask (`x=[918,1105) y=[269,331)`) — i.e. every observed pixel difference,
same-build or cross-build, is explained by the elapsed-time digits ticking
between captures, not by anything Release/DEBUG-specific. Header frames
identical on all three captures (`380 78 44 44`); Release and DEBUG capture
dates both `2026-09-30` (UTC) — same calendar day, so the daily puzzle was
guaranteed identical.

**PASS.**

## History

An earlier run (before the same-build control existed, and before the
state-parity fix) reported a 28%-of-pixels FAIL: Release was captured
mid-game while DEBUG was captured pre-start (the DEBUG install had resumed
a leftover in-progress save from the previous Release install, since both
builds share a bundle id and therefore a container) — a header-height
difference that shifted the entire grid 33px, not a rendering bug. Fixed by
uninstalling between every install and polling for the pause button
(running-game state) before capturing either side.

Files: `release-board.png`, `control-board.png`, `debug-board.png`,
`diff-mask.png` (Release vs DEBUG), `control-diff-mask.png` (Release vs
Release, the noise-floor reference).
