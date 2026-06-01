# Impl Notes — Minesweeper UI MVP (2026-06-02)

Status: COMPLETE
Owner: Senior Developer (Track A)
Dispatched by: Leader
Started: 2026-06-02

## 設計決定 (Design decisions)

- **Module name `MinesweeperGameState` (not `GameState`)** — `MinesweeperCoreKit/Package.swift` already warns: a second SwiftPM target named `GameState` would collide in the Xcode project graph with `SudokuCoreKit/GameState`. Picked the namespaced name as the package comment suggested. Library product also exported as `MinesweeperGameState`.

- **Two-file split for the actor module** (mirroring SudokuCoreKit/GameState shape but trimmed for MVP scope):
  - `MinesweeperSession.swift` — actor wrapping `MinesweeperEngine`, owns mutable state + elapsed-time accounting.
  - `MinesweeperSessionSnapshot.swift` — `Sendable` value type for board state, status, elapsed seconds, mine count.
  - `MinesweeperSessionStatus.swift` — `.idle / .playing / .won / .lost` enum (simpler than Sudoku's 5-state FSM because Minesweeper has no pause/abandon flow in MVP).
  - `MonotonicClock.swift` — copy of Sudoku's clock seam (1-second resolution monotonic clock; live + protocol). Keeps tests fully synchronous.

  The full Sudoku architecture has 8 files (telemetry, undo stack, notes grid, etc.) — MVP omits telemetry/undo/notes per dispatch spec ("No persistence, no undo/redo this round").

- **Status FSM minimal** — `.idle → .playing` (first action), `.playing → .won` (all safe revealed), `.playing → .lost` (mine revealed). No pause/abandon — engine + dispatch don't ask for them. Adding later is additive.

- **Elapsed time freezes on `.won` / `.lost`** — same pattern as Sudoku: track `runningSince: TimeInterval?` + `accumulatedSeconds: Int`. When session reaches terminal status, freeze.

- **`reveal` / `toggleFlag` API** — `async throws`, returning `MinesweeperSessionSnapshot` (the post-mutation board). Callers (ViewModel) bind to this snapshot. Errors forward `MinesweeperError` from the engine.

- **`MinesweeperGameViewModel` is `@MainActor @Observable`** — holds `let session: MinesweeperSession` and `var snapshot: MinesweeperSessionSnapshot`. Each user action `await`s the actor then assigns the returned snapshot. ViewModel exposes plain sync props (`status`, `cells`, `mineCount`, `elapsed`, `flagCount`).

- **Long-press = flag on iOS, secondary-click = flag on macOS** — used `.contextMenu` for macOS right-click hint via `Button("Toggle Flag")` and `.onLongPressGesture` for iOS. Both wired in the cell view; tap is just a plain `Button` action.

- **Preview boots a beginner board (9×9, 10 mines)** — per spec. Uses a fixed seed so the preview is deterministic.

## 偏離 (Deviations)

- **No telemetry / undo / notes / persistence** — explicitly carved out by dispatch spec. Not a deviation, just confirming the omission.

- **Platforms iOS 26 / macOS 26** — `apple-platform-targets` skill default is iOS 18 / macOS 15, but the existing `MinesweeperCoreKit/Package.swift` and `MinesweeperKit/Package.swift` already pin `.iOS(.v26)` / `.macOS(.v26)`. Matching siblings; not introducing inconsistency.

- **`flagCount` derived from cells** — engine doesn't track flag count separately. ViewModel computes `cells.filter { $0.state == .flagged }.count` lazily. Acceptable for 9×9..16×30 boards.

## 折衷 (Tradeoffs)

- **Actor vs `final class @unchecked Sendable`** — picked actor for Swift 6 strict-concurrency cleanliness, matching the SudokuCoreKit precedent and `swift6-concurrency` skill.

- **Snapshot push vs published cell-by-cell** — picked whole-snapshot push: simpler, board is small (≤480 cells), and SwiftUI diffs the array. Avoids per-cell binding complexity.

- **Test framework: swift-testing** — per `swift-testing-baseline` skill; matches engine tests.

## 未決 (Open questions)

- **None blocking** — all decisions above are reversible in follow-up rounds; none of them are load-bearing in a way that affects Sudoku or persistence schema.

## Round 2 (CR follow-up — 6 mechanical fixes)

- **Fix 1: Engine call before `ensurePlaying`** — `MinesweeperSession.swift:85-108` (reveal) and `:104-114` (toggleFlag). Swapped order so an OOB throw leaves status `.idle` and clock at 0.
- **Fix 2: TimelineView 1Hz status bar** — `MinesweeperBoardView.swift:44-62` wraps the HStack in `TimelineView(.periodic(from: .now, by: 1))` with an inner `.task { await viewModel.refresh() }` so elapsed-seconds tick during `.playing`.
- **Fix 3: Platform-gate flag gesture** — `MinesweeperBoardView.swift:118-134` replaces stacked `.onLongPressGesture` + `.contextMenu` with `#if os(iOS)` long-press / `#elseif os(macOS)` context menu. Eliminates the iOS double-toggle.
- **Fix 4: Split ViewModel init** — `MinesweeperGameViewModel.swift:41-65`. Two inits: `init(difficulty:seed:)` (convenience, builds session) and `init(session:)` (derives difficulty from the session). Union init removed; difficulty/seed cannot disagree.
- **Fix 5: Concurrency test reflects real contention** — `MinesweeperSessionTests.swift:201-217`. 20 toggles on the same cell (0,0); asserts `.hidden` (even parity) after the group drains.
- **Fix 6: OOB-leaves-idle tests** — `MinesweeperSessionTests.swift:220-242`. New `MinesweeperSessionOutOfBoundsTests` suite with `revealOutOfBoundsLeavesStatusIdle` and the paired `toggleFlagOutOfBoundsLeavesStatusIdle`.

Deferred: IMP#8 (BoardView `@State` re-init footgun) and CR cosmetic findings #10–#17 — per dispatch note.
