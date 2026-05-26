import Testing
@testable import SudokuEngine

@Suite("Solver naked-pair changed-flag accuracy")
struct SolverNakedPairTests {

    /// Build a board where row 0 has cells (0,0) and (0,1) with candidates
    /// {1,2}, and (0,2) with candidates {1,2,3,4} — the naked pair eliminates
    /// 1,2 from (0,2), reducing it to {3,4} (still > 1 candidate) so no Board
    /// cell gets filled. applyNakedPair must report `.unchanged`.
    @Test func nakedPair_eliminatesCandidates_butReportsUnchanged_whenNoBoardCellFilled() throws {
        var board = try Board(clues: BoardFixtures.empty)
        // Fill cols 4..8 of row 0 with digits 5..9 → row 0 still needs {1,2,3,4} in cols 0..3.
        for col in 4...8 {
            try board.setDigit(col + 1, atRow: 0, column: col) // cols 4..8 -> 5..9
        }
        // Block 3 and 4 from (0,0) and (0,1) so their candidates collapse to {1,2}.
        try board.setDigit(3, atRow: 3, column: 0)
        try board.setDigit(4, atRow: 4, column: 0)
        try board.setDigit(3, atRow: 5, column: 1)
        try board.setDigit(4, atRow: 6, column: 1)
        // (0,2) and (0,3) keep {1,2,3,4}. After naked-pair elimination they become {3,4} each
        // — still 2 candidates, no naked single produced, no Board cell filled.

        let solver = Solver()
        let result = solver.applyOnce(.nakedPair, to: &board)
        #expect(result == .unchanged, "naked pair must not report changed when no Board cell got filled")
        // Confirm (0,2) is still empty.
        #expect(board.digit(atRow: 0, column: 2) == nil)
    }

    /// Same shape as existing `nakedPairEliminatesFromUnitPeers`: the
    /// elimination cascades into a naked single on (0,2). applyNakedPair
    /// must report `.changed` because a Board cell got filled.
    @Test func nakedPair_reportsChanged_onlyWhenBoardCellFilled() throws {
        var board = try Board(clues: BoardFixtures.empty)
        for col in 3...8 {
            try board.setDigit(col + 1, atRow: 0, column: col) // cols 3..8 = 4..9
        }
        try board.setDigit(3, atRow: 3, column: 0)
        try board.setDigit(3, atRow: 4, column: 1)
        // (0,0) and (0,1) candidates {1,2}; (0,2) candidates {1,2,3}.
        let solver = Solver()
        let result = solver.applyOnce(.nakedPair, to: &board)
        #expect(result == .changed)
        #expect(board.digit(atRow: 0, column: 2) == 3)
    }

    /// Naked-pair-only board: candidate elimination is the only progress
    /// possible, but no cell can be filled. `propagate` must terminate and
    /// return false. Time-limited to catch the previous infinite loop.
    @Test(.timeLimit(.minutes(1)))
    func propagate_terminates_onNakedPairOnlyBoard() throws {
        var board = try Board(clues: BoardFixtures.empty)
        // Same setup as the first test: naked pair on (0,0)/(0,1), (0,2)/(0,3)
        // reduce to {3,4} but no single emerges.
        for col in 4...8 {
            try board.setDigit(col + 1, atRow: 0, column: col)
        }
        try board.setDigit(3, atRow: 3, column: 0)
        try board.setDigit(4, atRow: 4, column: 0)
        try board.setDigit(3, atRow: 5, column: 1)
        try board.setDigit(4, atRow: 6, column: 1)

        let solver = Solver()
        let solved = solver.propagate(to: &board)
        #expect(!solved)
    }
}
