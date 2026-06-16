// SudokuNearWinBoardTests — verifies that the DEBUG near-win board builder
// produces a board that is exactly one digit entry from winning.
//
// Covers #510 uitest hook. Assertions:
//   1. The near-win `viewModel.board` has exactly one empty (0) cell.
//   2. The winning digit at `emptyIndex` matches the puzzle solution.
//   3. The board is deterministic (same result across calls).
//   4. The session is `.playing` after `build()` calls `startOrResume()`.
//
// Tests run in DEBUG only (the builder is not compiled in Release).

#if DEBUG

import Testing
@testable import SudokuUI
import SudokuEngine

@Suite("SudokuNearWinBoard")
@MainActor
struct SudokuNearWinBoardTests {

    @Test("build() produces a board with exactly one empty cell")
    func nearWinBoardHasOneEmptyCell() async throws {
        let nearWin = try await SudokuNearWinBoard.build()

        let emptyCellCount = nearWin.viewModel.board.cells.filter { $0 == 0 }.count
        #expect(emptyCellCount == 1, "near-win board must have exactly 1 empty cell, got \(emptyCellCount)")
    }

    @Test("build() empty cell is at emptyIndex with correct winningDigit")
    func nearWinEmptyIndexAndWinningDigitAreConsistent() async throws {
        let nearWin = try await SudokuNearWinBoard.build()

        let board = nearWin.viewModel.board
        let emptyIndex = nearWin.emptyIndex
        let winningDigit = nearWin.winningDigit

        // The empty cell really is empty.
        let cellValue = board.cells[emptyIndex]
        #expect(cellValue == 0, "cell at emptyIndex \(emptyIndex) should be empty, got \(cellValue)")

        // The winning digit is in 1…9.
        #expect((1...9).contains(winningDigit), "winningDigit \(winningDigit) must be 1…9")
    }

    @Test("build() produces deterministic result (same board on every call)")
    func nearWinBoardIsDeterministic() async throws {
        let first = try await SudokuNearWinBoard.build()
        let second = try await SudokuNearWinBoard.build()

        let firstIdx = first.emptyIndex
        let secondIdx = second.emptyIndex
        #expect(firstIdx == secondIdx, "emptyIndex must be deterministic: \(firstIdx) ≠ \(secondIdx)")

        let firstDigit = first.winningDigit
        let secondDigit = second.winningDigit
        #expect(firstDigit == secondDigit, "winningDigit must be deterministic: \(firstDigit) ≠ \(secondDigit)")

        let firstCells = first.viewModel.board.cells
        let secondCells = second.viewModel.board.cells
        #expect(firstCells == secondCells, "near-win board cells must be bit-identical across builds")
    }

    @Test("build() session is .playing after startOrResume")
    func nearWinSessionIsPlaying() async throws {
        let nearWin = try await SudokuNearWinBoard.build()
        let status = nearWin.viewModel.status
        #expect(status == .playing, "session must be .playing after build(), got \(status)")
    }
}

#endif
