import Testing
@testable import SudokuEngine

@Suite("Solver")
struct SolverTests {

    @Test func nakedSingleFillsLonelyCell() throws {
        // Construct a board where cell (0,0) has only digit 1 as candidate:
        // place 2..9 across row 0 cols 1..8.
        var board = try Board(clues: BoardFixtures.empty)
        for col in 1...8 {
            try board.setDigit(col + 1, atRow: 0, column: col) // 2..9
        }
        let solver = Solver()
        #expect(solver.applyOnce(.nakedSingle, to: &board) == .changed)
        #expect(board.digit(atRow: 0, column: 0) == 1)
    }

    @Test func hiddenSingleFillsUniqueFitCell() throws {
        // Make digit 1 only fit in (0,0) for row 0 — block 1 in all other row-0
        // columns by placing 1 elsewhere in those columns, in rows that don't
        // share box 0 with (0,0) (i.e., not rows 0..2 for cols 1..2; not rows 0..2
        // for cols 1,2; for cols 3..8 any row outside 0 works as long as it doesn't
        // conflict with itself).
        var board = try Board(clues: BoardFixtures.empty)
        // Col 1: place 1 at row 3 (outside box 0).
        try board.setDigit(1, atRow: 3, column: 1)
        // Col 2: place 1 at row 4 (outside box 0).
        try board.setDigit(1, atRow: 4, column: 2)
        // Cols 3..8: place 1 at row 5..8 plus row 1, avoiding row collisions and
        // avoiding box 0.
        try board.setDigit(1, atRow: 5, column: 3)
        try board.setDigit(1, atRow: 6, column: 4)
        try board.setDigit(1, atRow: 7, column: 5)
        try board.setDigit(1, atRow: 8, column: 6)
        try board.setDigit(1, atRow: 1, column: 7) // row 1, col 7 → box 2 (rows 0..2 cols 6..8)
        try board.setDigit(1, atRow: 2, column: 8) // row 2, col 8 → box 2
        // Now in row 0, digit 1 can only go in column 0 (col 0 has no 1 in its
        // column, row, or box).
        let solver = Solver()
        let result = solver.applyOnce(.hiddenSingle, to: &board)
        #expect(result == .changed)
        #expect(board.digit(atRow: 0, column: 0) == 1)
    }

    @Test func nakedPairEliminatesFromUnitPeers() throws {
        // Construct row 0: two cells (0,0) and (0,1) both with candidates {1,2};
        // a third cell (0,2) with candidates {1,2,3}. Naked pair should remove 1,2
        // from (0,2), leaving 3 → naked-single in next pass.
        var board = try Board(clues: BoardFixtures.empty)
        // Place 3..9 in row 1 col 0 and 1 to block 3..9 from (0,0), (0,1).
        // Actually simpler: set the rest of row 0 (cols 3..8) to specific values
        // so that only cols 0,1,2 are empty in row 0.
        // We need: (0,0) candidates = {1,2}; (0,1) candidates = {1,2}; (0,2) = {1,2,3}.
        // The 3 remaining row-0 cells to fill must collectively cover digits {1,2,3}
        // and digits 4..9 go in cols 3..8.
        for col in 3...8 {
            try board.setDigit(col + 1, atRow: 0, column: col) // cols 3..8 = 4..9
        }
        // Now row 0 needs {1,2,3} in cols 0,1,2. To restrict (0,0) and (0,1) to {1,2}
        // (excluding 3), place a 3 in column 0 (row 1) — eliminates 3 from (0,0); and
        // a 3 in column 1 (row 2) — eliminates 3 from (0,1).
        try board.setDigit(3, atRow: 3, column: 0)
        try board.setDigit(3, atRow: 4, column: 1)
        // (0,2) still has {1,2,3}. Now apply naked pair.
        let solver = Solver()
        let result = solver.applyOnce(.nakedPair, to: &board)
        #expect(result == .changed)
        // Naked-pair eliminated 1,2 from (0,2) leaving 3 → fills (0,2).
        #expect(board.digit(atRow: 0, column: 2) == 3)
    }

    @Test func propagationSolvesEasyPuzzle() throws {
        var board = try Board(clues: BoardFixtures.easyUnique)
        let solver = Solver()
        let solved = solver.propagate(to: &board)
        #expect(solved)
        #expect(board.encoded() == BoardFixtures.easyUniqueSolution)
        #expect(board.isSolved)
    }

    @Test func propagationTerminatesWhenNoProgress() throws {
        // Empty board: propagation should not change anything.
        var board = try Board(clues: BoardFixtures.empty)
        let solver = Solver()
        let solved = solver.propagate(to: &board)
        #expect(!solved)
        #expect(board.encoded() == BoardFixtures.empty)
    }

    @Test func applyOnceUnchangedWhenNoSinglesAvailable() throws {
        var board = try Board(clues: BoardFixtures.empty)
        let solver = Solver()
        #expect(solver.applyOnce(.nakedSingle, to: &board) == .unchanged)
        #expect(solver.applyOnce(.hiddenSingle, to: &board) == .unchanged)
        #expect(solver.applyOnce(.nakedPair, to: &board) == .unchanged)
    }
}
