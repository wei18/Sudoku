// SudokuBoardPreviewMapper — Sudoku's `boardState` string ↔ `BoardPreview` (#1017).
//
// Pure, testable mapping: no CloudKit, no `.live()` construction. `Live.swift`
// is the only caller that touches async/CloudKit-adjacent state — it fetches
// `summary.boardState` (already in hand from `latestInProgress()`, #1017 no
// new round-trip) and the puzzle's `givenMask` (via `PuzzleProviderProtocol`,
// a deterministic local regeneration from `puzzleId` — the same lookup
// `Persistence.loadOrCreate` already performs to restore a board, not a new
// network call), then hands both to this mapper.
//
// `boardState` is the 81-char encoded board ('.' = blank, digit otherwise);
// it carries no given/filled distinction on its own (see `Board(encoded:against:)`
// in `SavedGameMapper`), so `givenMask` (from `Puzzle.clues`) is required to
// tell a clue apart from a player-entered digit.

public import GameShellUI

public enum SudokuBoardPreviewMapper {

    /// `nil` on anything malformed: wrong-length `boardState`, mismatched
    /// `givenMask` length, or an invalid character. Never throws/crashes —
    /// resume must keep working with a text-only pill (design.md §3.6).
    public static func make(boardState: String?, givenMask: [Bool]) -> BoardPreview? {
        guard let boardState else { return nil }
        let columns = 9
        let rows = 9
        guard boardState.count == columns * rows, givenMask.count == columns * rows else { return nil }

        var cells: [CellMark] = []
        cells.reserveCapacity(columns * rows)
        for (index, character) in boardState.enumerated() {
            if character == "." {
                cells.append(.empty)
            } else if character.isNumber {
                cells.append(givenMask[index] ? .given : .filled)
            } else {
                return nil
            }
        }
        return BoardPreview(columns: columns, rows: rows, cells: cells)
    }
}
