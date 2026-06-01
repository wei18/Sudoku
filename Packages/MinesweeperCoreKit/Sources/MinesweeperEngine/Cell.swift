// Cell — value type for a single Minesweeper grid square.

public enum CellState: String, Sendable, Codable, Hashable, CaseIterable {
    case hidden
    case revealed
    case flagged
}

public struct Cell: Sendable, Codable, Hashable {
    public var isMine: Bool
    public var neighborMineCount: Int
    public var state: CellState

    public init(isMine: Bool = false, neighborMineCount: Int = 0, state: CellState = .hidden) {
        self.isMine = isMine
        self.neighborMineCount = neighborMineCount
        self.state = state
    }
}
