// Direction — the four slide directions in classic 2048.

public enum Direction: String, Sendable, Codable, Hashable, CaseIterable {
    case left
    case right
    case up
    case down
}
