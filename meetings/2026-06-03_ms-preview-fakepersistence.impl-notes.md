# MS preview → FakePersistence (#261) — impl notes

## Spec deviation (IMPORTANT for Leader)
- Brief assumed `FakePersistence` already lives in `PersistenceTesting` (cited
  `Preview.swift:29` + `SudokuKit/Package.swift:83`).
- **Reality**: `FakePersistence` is defined in **`SudokuKitTesting`**
  (`SudokuKit/Sources/SudokuKitTesting/SudokuUI/FakePersistence.swift`), NOT in
  `PersistenceTesting`. `SudokuKit/Package.swift:83` adds `PersistenceTesting`
  to `SudokuKitTesting` only for `PuzzleFixtures`, and Sudoku's AppComposition
  pulls `FakePersistence` via its `"SudokuKitTesting"` dep, not PersistenceTesting.
- `SudokuKitTesting`'s `FakePersistence` is a Sudoku-test-target type; pulling it
  into MinesweeperKit would couple MS to Sudoku's test target — wrong.

## Decision
- Add a generic `FakePersistence` (zero-IO `PersistenceProtocol` conformer) to
  the shared `PersistenceTesting` target (which already deps Persistence +
  SudokuEngine + GameState — the only types the protocol needs). This is the
  reusable home both apps *should* share; MS consumes it now.
- Did NOT move Sudoku's existing `SudokuKitTesting.FakePersistence` (would
  break many Sudoku tests / exceed #261 surgical scope). Left untouched.
- MS `Package.swift`: add `PersistenceTesting` product to `MinesweeperAppComposition`.
- `Live.swift` `.preview()`: swap `LivePersistence(... .minesweeper ...)` →
  `FakePersistence()`. `.live()` unchanged. `MinesweeperLivePuzzleLoaderUnavailable`
  kept (still used by `.live()`).

## FakePersistence config
- No config arg needed; `FakePersistence()` no-arg init (mirrors Sudoku's call shape).
