// BoardError — public error type for Board construction failures.
// Pure value, no Foundation imports required.

public enum BoardError: Error, Sendable, Equatable {
    /// Encoded string length is not exactly 81 characters.
    case malformedLength(actual: Int)
    /// Encoded string contains a character that is neither '.', '0', nor '1'–'9'.
    case malformedCharacter(index: Int, character: Character)
    /// Row / column / digit out of bounds.
    case outOfRange
}
