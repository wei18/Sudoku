// BoardViewPencilNotesTests — pencil-notes rendering snapshot (#716).
//
// Lives in its own file (not BoardViewTests.swift) because that file sits at
// the SwiftLint file_length ceiling; same seam and snapshot conventions.
//
// #716 / audit-sud-13 claimed notes render as a "top-left vertical list";
// this snapshot is the standing counter-evidence and regression lock: notes
// render as the conventional positional 3×3 mini-grid — digit N sits in its
// own quadrant (row (N-1)/3, column (N-1)%3) and absent digits leave their
// slot blank (PencilNotesGrid in BoardCellView.swift).

import Foundation
import SnapshotTesting
import SwiftUI
import Testing
@testable import SudokuUI

import SudokuEngine
import SudokuGameState
import SudokuPersistence

@MainActor
@Suite("BoardView — pencil-notes positional mini-grid")
struct BoardViewPencilNotesTests {

    /// Same 33-clue mid-game layout as BoardViewTests.inProgressClues (kept
    /// in sync by value; duplicated because that fixture is private).
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
    @Test(.enabled(if: !SnapshotEnv.isXcodeCloud)) func snapshotPencilNotes_iPhone_light() throws {
        // Note patterns are chosen so a list-style regression is visually
        // unmistakable: {1,5,9} = main diagonal, {2,4,6,8} = the four edge
        // midpoints, 1...9 = full grid, {3,7} = opposite corners.
        var notes = NotesGrid()
        for digit in [1, 5, 9] { _ = notes.toggle(digit: digit, row: 0, col: 2) }
        for digit in [2, 4, 6, 8] { _ = notes.toggle(digit: digit, row: 0, col: 3) }
        for digit in 1...9 { _ = notes.toggle(digit: digit, row: 4, col: 4) }
        for digit in [3, 7] { _ = notes.toggle(digit: digit, row: 8, col: 0) }
        let viewModel = GameViewModel(
            identity: Self.identityEasy,
            board: try Board(clues: Self.inProgressClues),
            notes: notes,
            elapsedSeconds: 87
        )
        let host = hostingView(
            BoardView(viewModel: viewModel),
            size: SnapshotLayouts.iPhone,
            colorScheme: .light,
            sizeClass: .compact
        )
        withSnapshotTesting(record: SnapshotMode.recordMode) {
            assertSnapshot(of: host, as: .image, named: "Board-iPhone-light-pencilNotes")
        }
    }
    #endif
}
