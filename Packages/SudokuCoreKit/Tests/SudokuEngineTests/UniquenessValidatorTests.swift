import Testing
@testable import SudokuEngine

@Suite("UniquenessValidator")
struct UniquenessValidatorTests {

    @Test func uniqueSolutionFoundForKnownPuzzle() throws {
        let clues = try Board(clues: BoardFixtures.easyUnique)
        let result = UniquenessValidator.validate(clues: clues)
        guard case .unique(let solution) = result else {
            Issue.record("Expected .unique, got \(result)")
            return
        }
        #expect(solution.encoded() == BoardFixtures.easyUniqueSolution)
        #expect(solution.isSolved)
    }

    @Test func unsolvableForConflictingClues() throws {
        var clues = try Board(clues: BoardFixtures.empty)
        // Two 5s in row 0 ⇒ immediate contradiction.
        try clues.setDigit(5, atRow: 0, column: 0)
        try clues.setDigit(5, atRow: 0, column: 5)
        let result = UniquenessValidator.validate(clues: clues)
        #expect(result == .unsolvable)
    }

    @Test func underconstrainedBoardYieldsMultipleSolutionsShortCircuit() throws {
        // Clear the entire bottom 3 rows from the canonical solved board.
        // That removes too many constraints to uniquely determine the bottom band;
        // many valid completions exist. Short-circuit at 2.
        var board = try Board(clues: BoardFixtures.solvedKnown)
        for row in 6...7 {
            for col in 0...8 {
                try board.setDigit(nil, atRow: row, column: col)
            }
        }
        let result = UniquenessValidator.validate(clues: board)
        guard case .multiple(let count, let examples) = result else {
            Issue.record("Expected .multiple, got \(result)")
            return
        }
        #expect(count == 2)
        #expect(examples.count == 2)
        #expect(examples[0] != examples[1])
        #expect(examples[0].isSolved)
        #expect(examples[1].isSolved)
    }

    @Test func solvedBoardIsAlreadyUnique() throws {
        let clues = try Board(clues: BoardFixtures.solvedKnown)
        let result = UniquenessValidator.validate(clues: clues)
        guard case .unique(let solution) = result else {
            Issue.record("Expected .unique, got \(result)")
            return
        }
        #expect(solution.encoded() == BoardFixtures.solvedKnown)
    }

    @Test func twoUVTrapsReportsMultiple() throws {
        // A known unavoidable-rectangle pattern: 4 cells forming a 2x2 grid
        // across rows {0,1} and cols {7,8} that can swap a pair of digits.
        // In the canonical solved board:
        //   (0,7) = 1, (0,8) = 2, (1,7) = 4, (1,8) = 8
        // Just clearing those 4 alone is NOT enough to introduce ambiguity
        // (box / col constraints lock them). Use a heavier removal: clear
        // rows 7 and 8 entirely — two empty rows guarantee ambiguity.
        var board = try Board(clues: BoardFixtures.solvedKnown)
        for row in 7...8 {
            for col in 0...8 {
                try board.setDigit(nil, atRow: row, column: col)
            }
        }
        let result = UniquenessValidator.validate(clues: board)
        guard case .multiple(let count, _) = result else {
            Issue.record("Expected .multiple, got \(result)")
            return
        }
        #expect(count == 2)
    }
}
