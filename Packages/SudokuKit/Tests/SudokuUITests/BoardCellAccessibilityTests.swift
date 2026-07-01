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
