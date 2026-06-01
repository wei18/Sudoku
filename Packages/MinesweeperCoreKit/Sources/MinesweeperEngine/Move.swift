// Move — value type for a single player action recorded by the engine.

public enum Move: Sendable, Equatable, Hashable, Codable {
    case reveal(row: Int, col: Int)
    case flag(row: Int, col: Int)
    case unflag(row: Int, col: Int)
}
