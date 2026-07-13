// DigitPadViewOpacityTests — #790 fix 3: an exhausted-but-armed keypad digit
// (remaining == 0, armed for notes use — arming never gates on remaining
// count, only direct placement does) must render at full opacity. Before the
// fix, `compactDigitButton` dimmed to 0.35 purely off `remaining == 0`,
// ignoring `isArmed`, so an exhausted-and-armed button looked disabled while
// `.borderedProminent` accent fill made it visually "active" at the same
// time (DigitPadView.swift:153-154, per #790's finding 3).
//
// `macDigitButton` has no such gate at all (Mac never disables on remaining
// count, per its own doc comment) — confirmed by reading the source; no
// analogous fix needed there.

import Testing
@testable import SudokuUI

@Suite("DigitPadView — exhausted+armed opacity (#790 fix 3)")
struct DigitPadViewOpacityTests {

    @Test func exhaustedAndUnarmed_dims() {
        #expect(DigitPadView.digitButtonOpacity(remaining: 0, isArmed: false) == 0.35)
    }

    @Test func exhaustedAndArmed_staysFullOpacity() {
        #expect(DigitPadView.digitButtonOpacity(remaining: 0, isArmed: true) == 1.0,
            "An exhausted digit that is armed for notes use must not look disabled")
    }

    @Test func notExhausted_unarmed_fullOpacity() {
        #expect(DigitPadView.digitButtonOpacity(remaining: 3, isArmed: false) == 1.0)
    }

    @Test func notExhausted_armed_fullOpacity() {
        #expect(DigitPadView.digitButtonOpacity(remaining: 3, isArmed: true) == 1.0)
    }
}
