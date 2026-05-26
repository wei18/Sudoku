import Testing
@testable import SudokuEngine

@Suite("PuzzleCalibrator")
struct PuzzleCalibratorTests {

    @Test func clueCountMatchesFilledCells() throws {
        let board = try Board(clues: BoardFixtures.easyUnique)
        let cal = PuzzleCalibrator.calibrate(board)
        #expect(cal.clueCount == 30)
    }

    @Test func clueCountForFullySolvedBoardIs81() throws {
        let board = try Board(clues: BoardFixtures.solvedKnown)
        let cal = PuzzleCalibrator.calibrate(board)
        #expect(cal.clueCount == 81)
    }

    @Test func branchingFactorZeroForPropagationOnlySolvable() throws {
        let board = try Board(clues: BoardFixtures.easyUnique)
        let cal = PuzzleCalibrator.calibrate(board)
        #expect(cal.branchingFactor == 0)
    }

    @Test func easyAcceptsPropagationOnly30Clues() throws {
        // easyUnique has 30 clues — below the easy lower bound (32). So even
        // though it's propagation-solvable, the clue count fails. Confirm reject.
        let board = try Board(clues: BoardFixtures.easyUnique)
        #expect(!PuzzleCalibrator.accepts(board, as: .easy))
    }

    @Test func easyRejectsClueCountAbove50() throws {
        // Add clues to easyUnique to push past 50 by filling extra cells.
        var board = try Board(clues: BoardFixtures.easyUnique)
        let solved = try Board(clues: BoardFixtures.easyUniqueSolution)
        var added = 0
        for index in 0..<Board.cellCount where board.cellRaw(at: index) == 0 && added < 25 {
            board.setCellRaw(solved.cellRaw(at: index), at: index)
            added += 1
        }
        let cal = PuzzleCalibrator.calibrate(board)
        #expect(cal.clueCount == 55)
        #expect(!PuzzleCalibrator.accepts(cal, as: .easy))
    }

    @Test func easyAcceptsAt32Clues() throws {
        // Push easyUnique up to 32 clues while remaining propagation-solvable.
        var board = try Board(clues: BoardFixtures.easyUnique)
        let solved = try Board(clues: BoardFixtures.easyUniqueSolution)
        var added = 0
        for index in 0..<Board.cellCount where board.cellRaw(at: index) == 0 && added < 2 {
            board.setCellRaw(solved.cellRaw(at: index), at: index)
            added += 1
        }
        let cal = PuzzleCalibrator.calibrate(board)
        #expect(cal.clueCount == 32)
        #expect(cal.branchingFactor == 0)
        #expect(PuzzleCalibrator.accepts(cal, as: .easy))
    }

    @Test func easyClueCountBoundary31Reject() throws {
        // 31 clues fails the easy floor.
        var board = try Board(clues: BoardFixtures.easyUnique)
        let solved = try Board(clues: BoardFixtures.easyUniqueSolution)
        // 30 + 1 = 31
        for index in 0..<Board.cellCount where board.cellRaw(at: index) == 0 {
            board.setCellRaw(solved.cellRaw(at: index), at: index)
            break
        }
        let cal = PuzzleCalibrator.calibrate(board)
        #expect(cal.clueCount == 31)
        #expect(!PuzzleCalibrator.accepts(cal, as: .easy))
    }

    @Test func hardAcceptsClueCountInRange() throws {
        // easyUnique has 30 clues — falls within hard's [22, 32].
        let board = try Board(clues: BoardFixtures.easyUnique)
        let cal = PuzzleCalibrator.calibrate(board)
        #expect((22...32).contains(cal.clueCount))
        #expect(PuzzleCalibrator.accepts(cal, as: .hard))
    }

    @Test func mediumAcceptsClueCountInRange() throws {
        let board = try Board(clues: BoardFixtures.easyUnique)
        let cal = PuzzleCalibrator.calibrate(board)
        #expect(PuzzleCalibrator.accepts(cal, as: .medium))
    }
}
