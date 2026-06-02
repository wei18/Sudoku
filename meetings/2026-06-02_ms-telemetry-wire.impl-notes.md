# MS Telemetry Wire — Impl Notes (2026-06-02)

Wire `Telemetry` + `ErrorReporter` seams into `MinesweeperAppComposition` to mirror Sudoku's bag shape. Phase 2 (no view-level usage; AppComposition seam only).

## Decisions

- **Sudoku API mirrored verbatim.** `Telemetry(sinks:)` actor + `LiveErrorReporter(telemetry:)` actor. No new abstractions.
- **Subsystem string**: `com.wei18.minesweeper` to mirror Sudoku's `com.wei18.sudoku`. Category `Telemetry` per Sudoku's exact value.
- **OSLog sink only** in `.live()`. MetricKit sink + retainer omitted — not needed in Phase 2; can be added when MS reaches that maturity. `NoOpTrackingSink` included for shape parity (mirrors Sudoku's two-sink list).
- **`.preview()`** uses empty-sinks `Telemetry` + `NoopErrorReporter` — byte-identical to Sudoku Preview.swift pattern.
- **Live file split**: extracted `.live()` into `LiveMinesweeperAppComposition.swift` (separate file). Rationale: mirrors Sudoku's `Live.swift` separation from `AppComposition.swift`. Keeps the struct definition file (`MinesweeperAppComposition.swift`) focused on shape; live wiring concentrates in its own file.
- **`bootMonetization()` analog NOT added** — explicitly out-of-scope per dispatch.
- **Package dep**: added `TelemetryKit` path dep + exposed `Telemetry` product to `MinesweeperAppComposition` target (NOT to `MinesweeperUI` — view-level telemetry is later).
- **No `LiveErrorReporter` source string param** — Sudoku's signature is `LiveErrorReporter(telemetry:)`. The `source:` arg is per-`report()` call site, not constructor. The dispatch text mentioned `source: "MinesweeperApp"` but Sudoku's init doesn't take one; I matched Sudoku's actual signature.

## Considered alternatives

- Merging `.live()` into `MinesweeperAppComposition.swift` directly (saves a file). Rejected: Sudoku splits them; mirror-parity wins.
- Adding `MetricKitSink` now. Rejected: out of scope; Minesweeper has no metrics consumption yet.

## Open questions for Leader / CR

- Should MS use `com.wei18.minesweeper` or `com.wei18.sudoku.minesweeper` as the OSLog subsystem? Chose the former (independent app identity); if user prefers nested under sudoku, easy 1-line swap.
- Test target is `MinesweeperUITests` (shared); dispatch text suggested `MinesweeperAppCompositionTests`. Followed existing convention (LiveRouteFactoryTests already lives in `MinesweeperUITests`) — flagged for review.
