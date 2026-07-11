// BoardViewDigitFirstTests — armed-digit rendering snapshot (#722).
//
// Lives in its own file (not BoardViewTests.swift) because that file sits at
// the SwiftLint file_length ceiling; same seam and snapshot conventions.
//
// Locks the digit-first visual affordances: the keypad's armed digit gets
// the same `.borderedProminent` highlight as the Notes toggle's active
// state, and every board cell carrying the armed digit gets the existing
// `isSameDigit` background tint (BoardView+Highlighting.swift) — no new
// color tokens introduced.

import Foundation
import SnapshotTesting
import SwiftUI
import Testing
@testable import SudokuUI

import SudokuEngine
import SudokuGameState
import SudokuPersistence

@MainActor
@Suite("BoardView — digit-first armed state (#722)")
struct BoardViewDigitFirstTests {

    /// Same mid-game clue set as BoardViewTests.inProgressClues (kept in
    /// sync by value; duplicated because that fixture is private).
    private static let inProgressClues =
        "53..7...." +
        "6..195..." +
        ".98....6." +
        "8...6...3" +
        "4..8.3..1" +
        "7...2...6" +
        ".6....28." +
        "...419..5" +
        "....8..79"

    private static let identityEasy = PuzzleIdentity(
        puzzleId: "test-easy",
        kind: .practice,
        difficulty: .easy
    )

    #if canImport(AppKit)
    @Test(.enabled(if: !SnapshotEnv.isXcodeCloud)) func snapshotArmedDigit_iPhone_light() throws {
        // Digit 6 is armed with no cell selected: the keypad's "6" button
        // must show the armed highlight, and every board cell already
        // holding a 6 must carry the same-digit tint (no selection tint).
        var board = try Board(clues: Self.inProgressClues)
        try board.setDigit(4, atRow: 0, column: 2)
        let viewModel = GameViewModel(
            identity: Self.identityEasy,
            board: board,
            status: .playing,
            elapsedSeconds: 201,
            selection: nil,
            armedDigit: 6
        )
        let host = hostingView(
            BoardView(viewModel: viewModel),
            size: SnapshotLayouts.iPhone,
            colorScheme: .light,
            sizeClass: .compact
        )
        withSnapshotTesting(record: SnapshotMode.recordMode) {
            assertSnapshot(of: host, as: .image, named: "Board-iPhone-light-armedDigit")
        }
    }
    #endif
}
