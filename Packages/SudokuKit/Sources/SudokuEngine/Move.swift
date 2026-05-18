// Move — value type representing a single player action on a Board.
//
// `placeDigit` carries the cell's prior digit so that `undo` can be
// computed without recomputing or storing whole-Board snapshots.
// Pure value, Codable for snapshot persistence (§How.2 SavedGame fields).

public enum Move: Sendable, Equatable, Hashable, Codable {
    /// Place a digit (1...9) at (row, col). `previous` is the digit that
    /// occupied that cell immediately before this move, or nil if it was empty.
    case placeDigit(row: Int, col: Int, digit: Int, previous: Int?)
}
