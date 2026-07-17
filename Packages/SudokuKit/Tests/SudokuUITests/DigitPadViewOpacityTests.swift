// DigitPadViewOpacityTests — #790 fix 3 / #855 F-2: opacity now signals TRUE
// disablement only, not "exhausted".
//
// Before #790 fix 3, `compactDigitButton` dimmed to 0.35 purely off
// `remaining == 0`, ignoring `isArmed`, so an exhausted-and-armed button
// looked disabled while `.borderedProminent` accent fill made it visually
// "active" at the same time (DigitPadView.swift:153-154, per #790's
// finding 3).
//
// #855 F-2 found the remaining case still wrong: an exhausted-but-ENABLED
// digit (no cell selected, or pencil mode permits notes past exhaustion)
// was ALSO dimmed to 0.35 — contrast collapsed to ~2.2:1 (light) even
// though the key stays tappable. The fix threads a third `isDisabled`
// parameter (mirroring the view's own `.disabled(...)` condition) so
// opacity only dims a digit that is genuinely non-interactive; the
// "fully placed" signal for an exhausted-but-enabled digit moves to a
// checkmark badge (`compactDigitLabel`) instead of whole-key dimming.
//
// `macDigitButton` has no such gate at all (Mac never disables on remaining
// count, per its own doc comment) — confirmed by reading the source; no
// analogous fix needed there.

import Testing
@testable import SudokuUI

@Suite("DigitPadView — digit-key opacity (#790 fix 3, #855 F-2)")
struct DigitPadViewOpacityTests {

    @Test func exhaustedAndDisabled_dims() {
        // A cell is selected, pencil mode is off, and this digit is fully
        // placed — direct placement is genuinely blocked. WCAG doesn't
        // require contrast for disabled controls, so the 0.35 dim stands.
        #expect(DigitPadView.digitButtonOpacity(remaining: 0, isArmed: false, isDisabled: true) == 0.35)
    }

    @Test func exhaustedAndArmed_staysFullOpacity() {
        #expect(DigitPadView.digitButtonOpacity(remaining: 0, isArmed: true, isDisabled: false) == 1.0,
            "An exhausted digit that is armed for notes use must not look disabled")
    }

    @Test func exhaustedButEnabled_staysFullOpacity() {
        // #855 F-2: no cell selected (digit-first arming) — the key stays
        // tappable, so whole-key dimming must not fire even though
        // remaining == 0. The "fully placed" signal is a checkmark badge,
        // not opacity.
        #expect(DigitPadView.digitButtonOpacity(remaining: 0, isArmed: false, isDisabled: false) == 1.0,
            "An exhausted digit that is still enabled (e.g. unselected, or pencil mode) must not look disabled")
    }

    @Test func notExhausted_unarmed_fullOpacity() {
        #expect(DigitPadView.digitButtonOpacity(remaining: 3, isArmed: false, isDisabled: false) == 1.0)
    }

    @Test func notExhausted_armed_fullOpacity() {
        #expect(DigitPadView.digitButtonOpacity(remaining: 3, isArmed: true, isDisabled: false) == 1.0)
    }
}
