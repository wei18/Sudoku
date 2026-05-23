// UniquenessValidator — DFS solver that short-circuits at the 2nd solution.
//
// Per docs/v1/design.md §How.4.4 / §How.4.5.

public enum ValidationResult: Sendable, Equatable {
    /// Exactly one solution exists. The unique solved Board is provided.
    case unique(solution: Board)
    /// Two or more solutions exist. We stop searching at the 2nd; `examples`
    /// contains the first two solutions found (in DFS discovery order).
    case multiple(count: Int, examples: [Board])
    /// The clue grid has no completion (contradiction).
    case unsolvable
}

public enum UniquenessValidator {

    /// Validate the uniqueness of a Sudoku puzzle.
    /// Runs constraint propagation between branches; short-circuits at the 2nd solution.
    public static func validate(clues: Board) -> ValidationResult {
        // Reject upfront if the clue board already has a conflict.
        if !clues.conflicts().isEmpty {
            return .unsolvable
        }
        var working = clues
        var solutions: [Board] = []
        _ = search(board: &working, solutions: &solutions, limit: 2)
        switch solutions.count {
        case 0:
            return .unsolvable
        case 1:
            return .unique(solution: solutions[0])
        default:
            return .multiple(count: solutions.count, examples: solutions)
        }
    }

    /// Returns false when the caller should abort further branching (limit reached).
    private static func search(board: inout Board, solutions: inout [Board], limit: Int) -> Bool {
        // Propagate first.
        var snapshot = board
        let solver = Solver()
        let solved = solver.propagate(to: &snapshot)
        if !snapshot.conflicts().isEmpty {
            return true // dead branch
        }
        if solved {
            solutions.append(snapshot)
            return solutions.count < limit
        }
        // Choose the empty cell with fewest candidates (MCV).
        let grid = CandidateGrid(board: snapshot)
        var chosenIdx = -1
        var chosenCount = 10
        for index in 0..<Board.cellCount where snapshot.cellRaw(at: index) == 0 {
            let count = CandidateGrid.popcount(grid.masks[index])
            if count == 0 {
                return true // contradiction
            }
            if count < chosenCount {
                chosenCount = count
                chosenIdx = index
                if count == 2 { break } // good enough
            }
        }
        guard chosenIdx >= 0 else {
            return true
        }
        let mask = grid.masks[chosenIdx]
        for digit in CandidateGrid.digits(in: mask) {
            var next = snapshot
            next.setCellRaw(UInt8(digit), at: chosenIdx)
            if !search(board: &next, solutions: &solutions, limit: limit) {
                return false // limit reached; stop propagating
            }
        }
        return solutions.count < limit
    }
}
