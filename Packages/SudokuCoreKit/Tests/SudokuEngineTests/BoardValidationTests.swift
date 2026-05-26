import Testing
@testable import SudokuEngine

@Suite("BoardValidation")
struct BoardValidationTests {

    @Test func solvedBoardHasNoConflicts() throws {
        let board = try Board(clues: BoardFixtures.solvedKnown)
        #expect(board.conflicts().isEmpty)
        #expect(board.isSolved)
    }

    @Test func easyPuzzleHasNoConflicts() throws {
        let board = try Board(clues: BoardFixtures.easyUnique)
        #expect(board.conflicts().isEmpty)
        // Not solved — has empty cells.
        #expect(!board.isSolved)
    }

    @Test func rowConflictReportedWithRowIndexAndDigit() throws {
        // Put a duplicate 5 in row 0, columns 0 and 4.
        var board = try Board(clues: BoardFixtures.empty)
        try board.setDigit(5, atRow: 0, column: 0)
        try board.setDigit(5, atRow: 0, column: 4)
        let conflicts = board.conflicts()
        #expect(conflicts.contains(.row(0, digit: 5)))
    }

    @Test func columnConflictReported() throws {
        var board = try Board(clues: BoardFixtures.empty)
        try board.setDigit(7, atRow: 1, column: 3)
        try board.setDigit(7, atRow: 6, column: 3)
        let conflicts = board.conflicts()
        #expect(conflicts.contains(.column(3, digit: 7)))
    }

    @Test func boxConflictReported() throws {
        // Place two 9s in box(0) = (rows 0..2, cols 0..2).
        var board = try Board(clues: BoardFixtures.empty)
        try board.setDigit(9, atRow: 0, column: 0)
        try board.setDigit(9, atRow: 2, column: 2)
        let conflicts = board.conflicts()
        #expect(conflicts.contains(.box(0, digit: 9)))
    }

    @Test func singleConflictAcrossRowColAndBox() throws {
        // Two 4s at (0,0) and (0,1): same row AND same box.
        var board = try Board(clues: BoardFixtures.empty)
        try board.setDigit(4, atRow: 0, column: 0)
        try board.setDigit(4, atRow: 0, column: 1)
        let conflicts = board.conflicts()
        #expect(conflicts.contains(.row(0, digit: 4)))
        #expect(conflicts.contains(.box(0, digit: 4)))
        #expect(!conflicts.contains(.column(0, digit: 4)))
        #expect(!conflicts.contains(.column(1, digit: 4)))
    }

    @Test func partiallyFilledNotSolved() throws {
        let board = try Board(clues: BoardFixtures.easyUnique)
        #expect(!board.isSolved)
    }

    @Test func filledButConflictingNotSolved() throws {
        // Fill an entire board with 1s — fully filled but heavily conflicting.
        let allOnes = String(repeating: "1", count: 81)
        let board = try Board(clues: allOnes)
        #expect(board.isFullyFilled)
        #expect(!board.conflicts().isEmpty)
        #expect(!board.isSolved)
    }

    @Test func boxIndexHelper() {
        #expect(Board.boxIndex(row: 0, column: 0) == 0)
        #expect(Board.boxIndex(row: 4, column: 4) == 4)
        #expect(Board.boxIndex(row: 8, column: 8) == 8)
        #expect(Board.boxIndex(row: 0, column: 8) == 2)
        #expect(Board.boxIndex(row: 8, column: 0) == 6)
    }
}
