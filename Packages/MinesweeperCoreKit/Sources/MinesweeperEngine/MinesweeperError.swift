// MinesweeperError — public error type for engine operations.

public enum MinesweeperError: Error, Sendable, Equatable {
    case outOfBounds(row: Int, col: Int)
    case tooManyMines(requested: Int, capacity: Int)
    /// #841: a fixed-layout construction (`init(difficulty:seed:fixedMineIndices:)`)
    /// was handed a set whose size doesn't match `difficulty.mineCount`, or that
    /// contains an out-of-bounds index — a corrupt/legacy persisted layout, not a
    /// normal gameplay condition.
    case invalidFixedLayout(expected: Int, found: Int)
}
