// Conflict — a duplicate digit found within a row / column / box unit.

public enum Conflict: Sendable, Equatable, Hashable {
    case row(Int, digit: Int)
    case column(Int, digit: Int)
    case box(Int, digit: Int)
}
