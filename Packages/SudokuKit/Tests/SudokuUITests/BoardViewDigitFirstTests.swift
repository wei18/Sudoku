// BoardViewDigitFirstTests — armed-digit rendering (#722).
//
// Lives in its own file (not BoardViewTests.swift) because that file sits at
// the SwiftLint file_length ceiling; same seam and snapshot conventions.
//
// Locks the digit-first visual affordances. #722 gave this file ONE
// whole-screen snapshot covering two things: the keypad's armed-digit
// highlight, and the `isSameDigit` background tint every board cell carrying
// that digit picks up (BoardView+Highlighting.swift).
//
// #1022 had to split those two. The armed key is now tinted Liquid Glass, and
// **tinted glass blanks this capture path entirely** — the recorded PNG came
// back with zero opaque pixels, whole screen, background included, and every
// gate stayed green because a blank capture matches a blank reference. See
// `SnapshotBlankBaselineGuardTests` for the measured numbers and the standing
// guard that now fails on any blank baseline.
//
// So the coverage is split by what this renderer can actually capture:
//   - the `isSameDigit` cell tint is ordinary board content → still a pixel
//     snapshot, now taken on `BoardCellView` directly, which is tighter than
//     the old whole-screen shot anyway (a keypad change could never have
//     failed it for the right reason);
//   - the armed KEY's own highlight is uncapturable here and is verified on
//     the simulator instead, where Liquid Glass composites correctly — see
//     #1022's PR evidence.
// Re-recording the old fixture would just re-commit a blank; #1054 tracks the
// renderer, #1057 the "green gates, wrong artifact" class.

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
    /// The `isSameDigit` tint a cell picks up when it carries the armed digit.
    /// Rendered as a single `BoardCellView` (the same construct
    /// `BoardViewTests` uses for its cell-variant assertions) so no tinted
    /// glass enters the capture — see this file's header.
    @Test(.enabled(if: !SnapshotEnv.isXcodeCloud)) func snapshotSameDigitCell_light() throws {
        let host = hostingView(
            BoardCellView(
                row: 0, column: 0,
                digit: 6, isGiven: false, isSelected: false,
                isError: false, isHighlighted: false, isSameDigit: true,
                isPencilNotes: false, noteMask: 0, side: 44
            )
            .frame(width: 44, height: 44),
            size: CGSize(width: 44, height: 44),
            colorScheme: .light,
            sizeClass: .compact
        )
        withSnapshotTesting(record: SnapshotMode.recordMode) {
            assertSnapshot(of: host, as: .image, named: "Cell-light-sameDigit")
        }
    }

    /// Control: the same cell WITHOUT the armed-digit tint. Without this pair
    /// the tinted baseline could quietly become the untinted rendering and
    /// still pass — one image proves nothing about a highlight.
    @Test(.enabled(if: !SnapshotEnv.isXcodeCloud)) func snapshotPlainCell_light() throws {
        let host = hostingView(
            BoardCellView(
                row: 0, column: 0,
                digit: 6, isGiven: false, isSelected: false,
                isError: false, isHighlighted: false, isSameDigit: false,
                isPencilNotes: false, noteMask: 0, side: 44
            )
            .frame(width: 44, height: 44),
            size: CGSize(width: 44, height: 44),
            colorScheme: .light,
            sizeClass: .compact
        )
        withSnapshotTesting(record: SnapshotMode.recordMode) {
            assertSnapshot(of: host, as: .image, named: "Cell-light-plain")
        }
    }
    #endif
}
