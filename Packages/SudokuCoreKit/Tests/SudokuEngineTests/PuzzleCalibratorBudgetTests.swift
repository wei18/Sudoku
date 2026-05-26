import Testing
@testable import SudokuEngine

@Suite("PuzzleCalibrator budget cap")
struct PuzzleCalibratorBudgetTests {

    /// A heavily-branching board (near-empty / very low clue) must not blow
    /// the DFS budget. Without a cap, `calibrate` enumerates exponentially
    /// many branches and hangs. Uses the empty board as the worst-case
    /// stand-in for a low-clue Hard board the calibrator might be handed.
    @Test(.timeLimit(.minutes(1)))
    func calibrate_returnsWithinBudget_evenForHardBoard() throws {
        let board = try Board(clues: BoardFixtures.empty)
        let cal = PuzzleCalibrator.calibrate(board)
        #expect(cal.clueCount == 0)
        #expect(cal.branchingFactor >= 0)
    }

    /// branchingFactor must be capped at the documented sentinel (8). An
    /// empty board's true branchingFactor would be enormous; the calibrator
    /// must short-circuit and report the cap value rather than the true count.
    @Test(.timeLimit(.minutes(1)))
    func calibrate_capsBranchingFactorAtN() throws {
        let board = try Board(clues: BoardFixtures.empty)
        let cal = PuzzleCalibrator.calibrate(board)
        #expect(cal.branchingFactor == PuzzleCalibrator.branchingFactorCap,
                "branchingFactor must be capped at the sentinel (8) for ≥ 8 actual branches")
    }

    /// `accepts(.hard)` must return within the budget for a Hard board.
    @Test(.timeLimit(.minutes(1)))
    func accepts_hardBoard_withinBudget() throws {
        let board = try Board(clues: PuzzleGeneratorSnapshots.hardSeed0Clues)
        // No claim about true/false — only that the call terminates.
        _ = PuzzleCalibrator.accepts(board, as: .hard)
    }
}
