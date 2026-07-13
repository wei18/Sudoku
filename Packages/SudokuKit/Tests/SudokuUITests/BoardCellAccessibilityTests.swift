// BoardCellAccessibilityTests — #473: given (clue) cells are non-interactive.
//
// Their tap is a no-op (#472), so VoiceOver must announce them as static text,
// not a button. `BoardCellView.isInteractive` (= !isGiven) drives both the a11y
// trait (.isButton vs .isStaticText) and BoardView's decision to skip the
// Button wrapper. True VoiceOver behavior is confirmed on-device; this guards
// the decision headlessly.

import Testing
@testable import SudokuUI

@MainActor
@Suite("BoardCellView — accessibility interactivity (#473)")
struct BoardCellAccessibilityTests {

    @Test func givenCellsAreNonInteractive() {
        let given = BoardCellView(
            row: 0, column: 0, digit: 5, isGiven: true, isSelected: false,
            isError: false, isHighlighted: false, isSameDigit: false,
            isPencilNotes: false, noteMask: 0, side: 40
        )
        let editableEmpty = BoardCellView(
            row: 1, column: 1, digit: nil, isGiven: false, isSelected: false,
            isError: false, isHighlighted: false, isSameDigit: false,
            isPencilNotes: true, noteMask: 0, side: 40
        )
        let editableFilled = BoardCellView(
            row: 2, column: 2, digit: 7, isGiven: false, isSelected: true,
            isError: false, isHighlighted: false, isSameDigit: false,
            isPencilNotes: false, noteMask: 0, side: 40
        )
        #expect(given.isInteractive == false)
        #expect(editableEmpty.isInteractive == true)
        #expect(editableFilled.isInteractive == true)
    }
}

// MARK: - #790 fix 2: armed-digit VoiceOver hint

// A digit armed for digit-first placement changes an empty cell's tap
// semantics (select → place, BoardView+Highlighting.swift `tapCell`) with no
// prior a11y signal — the empty cell's label still read only "Empty". Locks
// the "will place N" suffix BoardCellView now appends while armed. Reads the
// REAL `accessibilityLabel` (made `internal` for this reason) rather than a
// re-implementation, so this test goes red on the pre-fix code.
@MainActor
@Suite("BoardCellView — armed-digit accessibility hint (#790 fix 2)")
struct BoardCellArmedAccessibilityTests {

    private func cell(digit: Int?, armedDigit: Int?) -> BoardCellView {
        BoardCellView(
            row: 0, column: 0, digit: digit, isGiven: false, isSelected: false,
            isError: false, isHighlighted: false, isSameDigit: false,
            isPencilNotes: true, noteMask: 0, side: 40, armedDigit: armedDigit
        )
    }

    @Test func emptyCell_noArmedDigit_labelUnchanged() {
        let unarmed = cell(digit: nil, armedDigit: nil)
        #expect(unarmed.accessibilityLabel == "Row 1, Column 1, Empty")
    }

    @Test func emptyCell_armedDigit_labelGainsPlacementHint() {
        let armed = cell(digit: nil, armedDigit: 5)
        #expect(armed.accessibilityLabel == "Row 1, Column 1, Empty, will place 5",
            "An armed empty cell's label must announce that a tap will place the armed digit")
    }

    @Test func filledCell_armedDigit_noHintAppended() {
        // Armed digits only place into EMPTY cells (tapCell falls back to
        // select() on a non-empty cell) — a filled cell's label must not
        // gain the hint even while some digit is armed elsewhere.
        let filled = cell(digit: 7, armedDigit: 5)
        #expect(filled.accessibilityLabel == "Row 1, Column 1, value 7")
    }
}
