// PuzzleFixtures — minimal Puzzle/Board factories for PersistenceTests.
//
// Shared with future Phase 6 PuzzleStoreTests so the helpers live here in
// SudokuKitTesting rather than duplicated per test target.

import Foundation
public import SudokuEngine
internal import SudokuGameState

public enum PuzzleFixtures {

    /// Build a deterministic puzzle whose solution is the shifted Latin
    /// square `((index % 9) + 1)`. NOT a valid Sudoku — but
    /// `currentBoard == solution` round-trips and completion detection
    /// works, which is enough for Persistence round-trip tests.
    public static func latinSquarePuzzle(missingRow: Int = 0, missingCol: Int = 0) -> Puzzle {
        var solution = Board()
        var cluesString = ""
        for index in 0..<Board.cellCount {
            let row = index / 9
            let col = index % 9
            let digit = (index % 9) + 1
            // swiftlint:disable:next force_try
            try! solution.setDigit(digit, atIndex: index)
            if row == missingRow && col == missingCol {
                cluesString.append(".")
            } else {
                cluesString.append(String(digit))
            }
        }
        // swiftlint:disable:next force_try
        let clues = try! Board(clues: cluesString)
        return Puzzle(
            clues: clues,
            solution: solution,
            difficulty: .easy,
            generatorVersion: .v1,
            seed: 0
        )
    }
}
