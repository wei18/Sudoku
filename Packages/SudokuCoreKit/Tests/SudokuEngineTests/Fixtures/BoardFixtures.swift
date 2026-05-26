@testable import SudokuEngine

enum BoardFixtures {
    /// A fully-solved canonical Sudoku.
    static let solvedKnown: String =
        "534678912672195348198342567859761423426853791713924856961537284287419635345286179"

    /// A well-known easy puzzle (30 clues) with a unique solution.
    static let easyUnique: String =
        "53..7....6..195....98....6.8...6...34..8.3..17...2...6.6....28....419..5....8..79"

    /// Solution to easyUnique above.
    static let easyUniqueSolution: String = solvedKnown

    /// An empty board.
    static let empty: String = String(repeating: ".", count: 81)
}
