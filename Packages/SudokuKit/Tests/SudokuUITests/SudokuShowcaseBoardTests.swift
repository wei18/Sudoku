// SudokuShowcaseBoardTests — verifies the DEBUG showcase-board builder
// produces a deterministic, marketing-ready fixture (#1054).
//
// Assertions:
//   1. Every given cell in `currentBoard` matches the puzzle's clue board
//      (givens are untouched).
//   2. Exactly one non-given cell conflicts with the board (the visible red
//      error highlight).
//   3. `notes` is non-empty, and every pencilled candidate is legal under
//      the final board (no already-placed peer holds that digit).
//   4. The snapshot is deterministic across every call.
//
// Tests run in DEBUG only (the builder is not compiled in Release).

#if DEBUG

import Testing
@testable import SudokuUI
import SudokuEngine
import SudokuGameState

@Suite("SudokuShowcaseBoard")
struct SudokuShowcaseBoardTests {

    @Test("snapshot's givens exactly match the puzzle's clue board")
    func showcaseSnapshotGivensMatchPuzzle() throws {
        let snapshot = try SudokuShowcaseBoard.snapshot()
        for index in 0..<Board.cellCount where snapshot.puzzle.clues.givenMask[index] {
            #expect(
                snapshot.currentBoard.digit(atIndex: index) == snapshot.puzzle.clues.digit(atIndex: index),
                "given cell at \(index) must be untouched"
            )
        }
    }

    @Test("snapshot has exactly one conflicting (non-given) cell")
    func showcaseSnapshotHasExactlyOneConflict() throws {
        let snapshot = try SudokuShowcaseBoard.snapshot()
        let board = snapshot.currentBoard
        var conflictCount = 0
        for index in 0..<Board.cellCount {
            guard !board.givenMask[index], let digit = board.digit(atIndex: index) else { continue }
            if Self.hasConflict(digit: digit, atRow: index / Board.dimension, col: index % Board.dimension, in: board) {
                conflictCount += 1
            }
        }
        #expect(conflictCount == 1, "expected exactly 1 conflicting cell, got \(conflictCount)")
    }

    @Test("snapshot's notes are non-empty and every candidate is legal")
    func showcaseSnapshotNotesAreLegal() throws {
        let snapshot = try SudokuShowcaseBoard.snapshot()
        let board = snapshot.currentBoard
        var noteCellCount = 0
        for row in 0..<Board.dimension {
            for col in 0..<Board.dimension {
                let candidateDigits = (1...9).filter { snapshot.notes.contains(digit: $0, row: row, col: col) }
                guard !candidateDigits.isEmpty else { continue }
                noteCellCount += 1
                #expect(
                    board.digit(atRow: row, column: col) == nil,
                    "a noted cell at (\(row),\(col)) must still be blank"
                )
                for digit in candidateDigits {
                    #expect(
                        !Self.hasConflict(digit: digit, atRow: row, col: col, in: board),
                        "candidate \(digit) at (\(row),\(col)) must not conflict with the board"
                    )
                }
            }
        }
        #expect(noteCellCount > 0, "expected at least one noted cell")
    }

    @Test("snapshot is deterministic across every call")
    func showcaseSnapshotIsDeterministic() throws {
        let first = try SudokuShowcaseBoard.snapshot()
        let second = try SudokuShowcaseBoard.snapshot()
        #expect(first == second, "showcase snapshot must be bit-identical across calls")
    }

    // Mirrors `GameViewModel.hasConflict` (private, MainActor) — duplicated
    // here so the test independently proves the same conflict property the
    // production `recomputeErrors()` will compute, without reaching into a
    // private VM method.
    private static func hasConflict(digit: Int, atRow row: Int, col: Int, in board: Board) -> Bool {
        for col2 in 0..<Board.dimension where col2 != col {
            if board.digit(atRow: row, column: col2) == digit { return true }
        }
        for row2 in 0..<Board.dimension where row2 != row {
            if board.digit(atRow: row2, column: col) == digit { return true }
        }
        let boxRowOrigin = (row / 3) * 3
        let boxColOrigin = (col / 3) * 3
        for row2 in boxRowOrigin..<boxRowOrigin + 3 {
            for col2 in boxColOrigin..<boxColOrigin + 3 where !(row2 == row && col2 == col) {
                if board.digit(atRow: row2, column: col2) == digit { return true }
            }
        }
        return false
    }
}

#endif
