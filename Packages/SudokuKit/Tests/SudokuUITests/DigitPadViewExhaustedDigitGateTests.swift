// DigitPadViewExhaustedDigitGateTests — #855 adjudicated extra: unify the
// exhausted-digit notes path.
//
// Before this fix, the selected-cell gate (`hasSelection && remaining == 0`)
// disabled an exhausted digit unconditionally, even in pencil mode — but
// the no-selection (digit-first arming) path never gated on `remaining` at
// all, since arming an exhausted digit is valid for notes use. That meant a
// player mid-pencil-note who happened to have a cell selected hit a
// disabled key for a digit they could freely arm one tap later by
// deselecting. Owner adjudication (2026-07-17): unify to ALLOW — notes are
// annotations, remaining-count is irrelevant to them, on both paths.

import Testing
@testable import SudokuUI

@Suite("DigitPadView — exhausted-digit gate agrees across selection state (#855)")
struct DigitPadViewExhaustedDigitGateTests {

    @Test func noSelection_exhaustedDigit_neverDisabled_regardlessOfPencilMode() {
        // Digit-first arming path: never gates on remaining count.
        #expect(DigitPadView.isDigitDisabled(hasSelection: false, remaining: 0, pencilMode: false) == false)
        #expect(DigitPadView.isDigitDisabled(hasSelection: false, remaining: 0, pencilMode: true) == false)
    }

    @Test func selectedCell_pencilMode_exhaustedDigit_notDisabled() {
        // Selected-cell path, but in pencil mode — a note isn't a placement,
        // so it must agree with the no-selection path above and stay enabled.
        #expect(DigitPadView.isDigitDisabled(hasSelection: true, remaining: 0, pencilMode: true) == false)
    }

    @Test func selectedCell_directPlacement_exhaustedDigit_staysDisabled() {
        // Selected-cell path, pencil mode OFF — direct placement of a 10th
        // instance of this digit is genuinely invalid; this case must stay
        // disabled (unchanged behavior, not part of the adjudication).
        #expect(DigitPadView.isDigitDisabled(hasSelection: true, remaining: 0, pencilMode: false) == true)
    }

    @Test func nonExhaustedDigit_neverDisabled() {
        #expect(DigitPadView.isDigitDisabled(hasSelection: true, remaining: 3, pencilMode: false) == false)
        #expect(DigitPadView.isDigitDisabled(hasSelection: true, remaining: 3, pencilMode: true) == false)
        #expect(DigitPadView.isDigitDisabled(hasSelection: false, remaining: 3, pencilMode: false) == false)
    }
}
