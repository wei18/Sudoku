// PuzzleCalibrator — difficulty classification per design.md §How.4.4.
//
// Pure value-based; no Foundation; no RNG. Uses Solver + DFS guessing counter
// to estimate `branchingFactor` (the number of guesses needed to drive the
// solver past propagation-only deadlock).

public struct PuzzleCalibration: Sendable, Equatable {
    /// Number of filled cells (clues) in the input board.
    public let clueCount: Int
    /// Number of DFS branches taken to reach a solution after constraint
    /// propagation reaches fixed point. 0 = propagation alone solves.
    public let branchingFactor: Int
}

public enum Difficulty: String, Sendable, Equatable, Codable, CaseIterable {
    case easy
    case medium
    case hard
}

public enum PuzzleCalibrator {

    /// Compute (clueCount, branchingFactor) for a given clue board.
    public static func calibrate(_ board: Board) -> PuzzleCalibration {
        let clueCount = board.cells.reduce(0) { $0 + ($1 == 0 ? 0 : 1) }
        var work = board
        // Reset givens (we don't care for solving).
        let branches = countBranches(&work)
        return PuzzleCalibration(clueCount: clueCount, branchingFactor: branches)
    }

    /// Accept the board for the given difficulty label if it satisfies the
    /// design.md §How.4.4 calibrator rules:
    ///   - Easy: clueCount in [32, 50], branchingFactor == 0
    ///   - Medium: clueCount in [28, 38], branchingFactor <= 2
    ///   - Hard: clueCount in [22, 32], no branchingFactor cap (but > 3 only "warns")
    public static func accepts(_ board: Board, as label: Difficulty) -> Bool {
        let cal = calibrate(board)
        return accepts(cal, as: label)
    }

    public static func accepts(_ calibration: PuzzleCalibration, as label: Difficulty) -> Bool {
        switch label {
        case .easy:
            return (32...50).contains(calibration.clueCount) && calibration.branchingFactor == 0
        case .medium:
            return (28...38).contains(calibration.clueCount) && calibration.branchingFactor <= 2
        case .hard:
            return (22...32).contains(calibration.clueCount)
        }
    }

    // MARK: - DFS branch counter

    private static func countBranches(_ board: inout Board) -> Int {
        let solver = Solver()
        let solved = solver.propagate(to: &board)
        if solved { return 0 }
        // Need to guess. Pick MCV cell.
        var branches = 0
        _ = recursiveCount(board: &board, branches: &branches)
        return branches
    }

    /// Returns whether a solution was found. Counts each branch taken (digit tried).
    private static func recursiveCount(board: inout Board, branches: inout Int) -> Bool {
        var snapshot = board
        let solver = Solver()
        let solved = solver.propagate(to: &snapshot)
        if !snapshot.conflicts().isEmpty { return false }
        if solved { return true }
        let grid = CandidateGrid(board: snapshot)
        var chosenIdx = -1
        var chosenCount = 10
        for index in 0..<Board.cellCount where snapshot.cellRaw(at: index) == 0 {
            let count = CandidateGrid.popcount(grid.masks[index])
            if count == 0 { return false }
            if count < chosenCount {
                chosenCount = count
                chosenIdx = index
                if count == 2 { break }
            }
        }
        guard chosenIdx >= 0 else { return false }
        let mask = grid.masks[chosenIdx]
        for digit in CandidateGrid.digits(in: mask) {
            branches += 1
            var next = snapshot
            next.setCellRaw(UInt8(digit), at: chosenIdx)
            if recursiveCount(board: &next, branches: &branches) {
                board = next
                return true
            }
        }
        return false
    }
}
