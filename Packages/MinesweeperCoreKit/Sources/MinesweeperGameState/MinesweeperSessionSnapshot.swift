// MinesweeperSessionSnapshot — Sendable value summarizing a session for UI.
//
// `MinesweeperSession` (actor) produces a fresh snapshot after every
// mutation; the ViewModel binds to this and SwiftUI diffs the cell array.
//
// Pure value type — no Apple-framework imports beyond Foundation (for Date,
// which is intentionally NOT included in MVP — we expose `elapsedSeconds:
// Int`, not a wall clock).

public import MinesweeperEngine

public struct MinesweeperSessionSnapshot: Sendable, Equatable, Hashable, Codable {
    public let difficulty: Difficulty
    /// Seed the owning `MinesweeperEngine` was built from. Persisted so a
    /// restored session reconstructs the identical seed-derived board (#455).
    public let seed: UInt64
    public let cells: [Cell]
    public let status: MinesweeperSessionStatus
    public let elapsedSeconds: Int
    public let mineCount: Int
    public let flagCount: Int

    public var rows: Int { difficulty.rows }
    public var columns: Int { difficulty.columns }

    public init(
        difficulty: Difficulty,
        seed: UInt64 = 0,
        cells: [Cell],
        status: MinesweeperSessionStatus,
        elapsedSeconds: Int,
        mineCount: Int,
        flagCount: Int
    ) {
        self.difficulty = difficulty
        self.seed = seed
        self.cells = cells
        self.status = status
        self.elapsedSeconds = elapsedSeconds
        self.mineCount = mineCount
        self.flagCount = flagCount
    }

    public func cell(row: Int, col: Int) -> Cell {
        cells[row * difficulty.columns + col]
    }
}
