// DigitPadView+Accessibility — pure helpers behind DigitPadView's opacity
// and VoiceOver strings. Extracted from DigitPadView.swift (#855) to stay
// under the 400-line SwiftLint `file_length` ceiling; these are `static`
// (not instance) methods so the split needs no new state or protocol.

import SwiftUI

extension DigitPadView {

    /// #855 adjudicated extra: unifies the two exhausted-digit paths.
    /// - No cell selected (`!hasSelection`, digit-first arming) — never
    ///   gates on `remaining`; arming an exhausted digit is valid for notes.
    /// - A cell IS selected — direct digit placement still gates on
    ///   `remaining == 0` (can't place a 9th "5"), UNLESS `pencilMode` is on:
    ///   pencil notes are annotations, not placements, so they don't care
    ///   about remaining count either. Before this fix the selected-cell
    ///   path disabled exhausted digits unconditionally, disagreeing with
    ///   the no-selection path whenever pencil mode was on.
    /// Extracted as a pure `static func` (mirrors `digitButtonOpacity`) so
    /// both paths can be pinned to agree without rendering the view.
    static func isDigitDisabled(hasSelection: Bool, remaining: Int, pencilMode: Bool) -> Bool {
        hasSelection && remaining == 0 && !pencilMode
    }

    /// #790 fix 3 / #855 F-2: opacity signals TRUE disablement only.
    /// - An exhausted-but-armed digit (`isArmed`, notes use) always stays
    ///   full-opacity — dimming it while it renders `.borderedProminent`
    ///   accent fill mixes "disabled" and "active" visual language.
    /// - An exhausted-but-ENABLED digit (`remaining == 0`, `!isDisabled` —
    ///   e.g. no selection yet, or pencil mode permits notes past
    ///   exhaustion) also stays full-opacity: whole-key dimming reads as
    ///   "disabled" even though the key is still tappable (#855 F-2 — light
    ///   contrast at the old 0.35 dim measured ~2.2:1, well under the 3:1
    ///   floor). `compactDigitLabel` carries the "fully placed" signal
    ///   instead via a checkmark badge at full-opacity ink (≥6.6:1).
    /// - Only the genuinely disabled case (`isDisabled`, a real cell is
    ///   selected and this digit can't be placed) keeps the 0.35 dim; WCAG
    ///   contrast requirements don't apply to disabled controls.
    /// Extracted as a pure `static func` (not inlined in `.opacity(...)`) so
    /// this decision is unit-testable without rendering the view.
    static func digitButtonOpacity(remaining: Int, isArmed: Bool, isDisabled: Bool) -> Double {
        guard remaining == 0, !isArmed else { return 1.0 }
        return isDisabled ? 0.35 : 1.0
    }

    /// #855 F-3: localizes the two accessibilityValue shapes that were
    /// bare String-typed ternary branches (`"%lld remaining"` / `"fully
    /// placed"` never made it into the xcstrings catalog — confirmed by the
    /// audit).
    static func digitAccessibilityValue(remaining: Int) -> String {
        remaining > 0
            ? String(localized: "\(remaining) remaining", bundle: .main)
            : String(localized: "fully placed", bundle: .main)
    }

    /// #855 F-8: a selected cell places the digit immediately; no selection
    /// only arms it (digit-first, #722) — VoiceOver users get the same
    /// disambiguation sighted users get from the armed-highlight affordance.
    static func digitAccessibilityHint(hasSelection: Bool) -> String {
        hasSelection
            ? String(localized: "Places the digit in the selected cell", bundle: .main)
            : String(localized: "Arms the digit for placement", bundle: .main)
    }

    /// #855 F-3: `"On"`/`"Off"` were bare String-typed ternary branches,
    /// bypassing L10n (the ternary's mixed-shape branches don't resolve to
    /// `LocalizedStringKey` the way a single string literal would — the
    /// audit confirmed `"Off"` never made it into the xcstrings catalog).
    /// `String(localized:)` is the established pattern for computed
    /// accessibility strings in this module (see `BoardCellView.swift`,
    /// `StatsView.swift`).
    static func pencilModeAccessibilityValue(_ pencilMode: Bool) -> String {
        pencilMode
            ? String(localized: "On", bundle: .main)
            : String(localized: "Off", bundle: .main)
    }
}
