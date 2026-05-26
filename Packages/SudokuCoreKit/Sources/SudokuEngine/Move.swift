// Move — value type representing a single player action on a Board.
//
// `placeDigit` carries the cell's prior digit so that `undo` can be
// computed without recomputing or storing whole-Board snapshots.
// Pure value, Codable for snapshot persistence (§How.2 SavedGame fields).

public enum Move: Sendable, Equatable, Hashable, Codable {
    /// Place a digit (1...9) at (row, col). `previous` is the digit that
    /// occupied that cell immediately before this move, or nil if it was empty.
    case placeDigit(row: Int, col: Int, digit: Int, previous: Int?)

    /// Clear the digit at (row, col). `previous` is the digit that occupied
    /// the cell immediately before the clear (nil if the cell was already
    /// empty — recorded for completeness even though it is a no-op effect).
    /// Added per impl-notes 2026-05-20_wave-2-blocker-fixes §B1 so that
    /// clear-cell flows through `GameSession` like place and participates in
    /// the undo/redo stack.
    case clearDigit(row: Int, col: Int, previous: Int?)
}
