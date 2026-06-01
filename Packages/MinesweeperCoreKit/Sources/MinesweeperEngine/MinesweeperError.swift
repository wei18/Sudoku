// MinesweeperError — public error type for engine operations.

public enum MinesweeperError: Error, Sendable, Equatable {
    case outOfBounds(row: Int, col: Int)
    case tooManyMines(requested: Int, capacity: Int)
}
