// Difficulty — Minesweeper preset board sizes + mine counts.
// Beginner 9×9/10 · Intermediate 16×16/40 · Expert 16×30/99.

public enum Difficulty: String, Sendable, Codable, CaseIterable, Hashable {
    case beginner
    case intermediate
    case expert

    public var rows: Int {
        switch self {
        case .beginner: return 9
        case .intermediate: return 16
        case .expert: return 16
        }
    }
    public var columns: Int {
        switch self {
        case .beginner: return 9
        case .intermediate: return 16
        case .expert: return 30
        }
    }
    public var mineCount: Int {
        switch self {
        case .beginner: return 10
        case .intermediate: return 40
        case .expert: return 99
        }
    }
    public var cellCount: Int { rows * columns }
}
