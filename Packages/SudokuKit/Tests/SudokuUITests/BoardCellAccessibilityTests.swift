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

// MARK: - #790 fix 2 / #939: armed-digit VoiceOver hint

// A digit armed for digit-first placement changes an empty cell's tap
// semantics (select → place, BoardView+Highlighting.swift `tapCell`) with no
// prior a11y signal — the empty cell's label still read only "Empty". Locks
// the "will place N" suffix BoardCellView now appends while armed. Reads the
// REAL `accessibilityLabel` (made `internal` for this reason) rather than a
// re-implementation, so this test goes red on the pre-fix code.
//
// #939 made armed mode STICKY: `tapCell` no longer falls back to `select()`
// on a non-empty cell (that fallback, and the disarm it caused, no longer
// exist). A user-filled cell already holding the ARMED digit now CLEARS on
// tap (destructive) — `filledCell_sameDigitArmed_gainsClearHint` locks the
// new "will clear N" hint for that case. A mismatched digit or a given cell
// stays a silent no-op with NO label change (`filledCell_*_labelUnchanged`
// below) — nothing about those taps' outcome changed, so there is nothing
// new to announce.
@MainActor
@Suite("BoardCellView — armed-digit accessibility hint (#790 fix 2 / #939)")
struct BoardCellArmedAccessibilityTests {

    private func cell(digit: Int?, armedDigit: Int?, isGiven: Bool = false, pencilMode: Bool = false) -> BoardCellView {
        BoardCellView(
            row: 0, column: 0, digit: digit, isGiven: isGiven, isSelected: false,
            isError: false, isHighlighted: false, isSameDigit: false,
            isPencilNotes: true, noteMask: 0, side: 40, armedDigit: armedDigit, pencilMode: pencilMode
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

    @Test func filledCell_differentDigitArmed_labelUnchanged() {
        // #939: a mismatched tap (armed digit != this cell's digit) is a
        // silent no-op — the label must not gain any hint.
        let filled = cell(digit: 7, armedDigit: 5)
        #expect(filled.accessibilityLabel == "Row 1, Column 1, value 7")
    }

    @Test func givenCell_matchingArmedDigit_labelUnchanged() {
        // #939: a given always stays a silent no-op while armed, even when
        // its digit matches the armed one (givens are never "user-filled").
        let given = cell(digit: 5, armedDigit: 5, isGiven: true)
        #expect(given.accessibilityLabel == "Row 1, Column 1, given 5")
    }

    @Test func filledCell_sameDigitArmed_gainsClearHint() {
        // #939: tapping a user-filled cell that already holds the armed
        // digit CLEARS it — a destructive outcome that needs its own
        // announcement, distinct from "will place".
        let filled = cell(digit: 5, armedDigit: 5)
        #expect(filled.accessibilityLabel == "Row 1, Column 1, value 5, will clear 5",
            "A same-digit armed tap on a user-filled cell must announce that it will clear the cell")
    }

    @Test func filledCell_sameDigitArmed_pencilMode_labelUnchanged() {
        // #939: in pencil mode the SAME tap toggles a note (non-destructive),
        // not a clear — the "will clear" hint would be actively wrong here,
        // so pencil mode keeps the bare "value N" label (BoardCellView has
        // no per-note-bit a11y signal today; this is the accepted gap, not a
        // regression — the pre-#939 label was equally silent about notes).
        let filled = cell(digit: 5, armedDigit: 5, pencilMode: true)
        #expect(filled.accessibilityLabel == "Row 1, Column 1, value 5")
    }
}
