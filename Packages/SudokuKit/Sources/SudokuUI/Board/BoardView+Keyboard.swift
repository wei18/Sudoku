// BoardView+Keyboard — Mac keyboard handling (arrows / 1–9 / 0 / delete / p).
//
// Extracted from BoardView.swift (#1023) to keep that file under SwiftLint's
// file_length ceiling (repo convention: extract a `+Feature.swift` sibling
// rather than disabling the rule) after the #1023 Daily-progress wiring
// pushed it over 400 lines.

import SwiftUI

extension BoardView {

    // MARK: - Keyboard

    func handleKeyPress(_ keyPress: KeyPress) -> KeyPress.Result {
        // #763: a paused/completed board must not eat key presses meant for
        // its overlay's own controls (e.g. Space re-toggling pause underneath).
        guard modalOverlayPresentation == nil else { return .ignored }
        // Arrow keys: move focus.
        switch keyPress.key {
        case .leftArrow:
            viewModel.moveSelection(rowDelta: 0, columnDelta: -1); return .handled
        case .rightArrow:
            viewModel.moveSelection(rowDelta: 0, columnDelta: 1); return .handled
        case .upArrow:
            viewModel.moveSelection(rowDelta: -1, columnDelta: 0); return .handled
        case .downArrow:
            viewModel.moveSelection(rowDelta: 1, columnDelta: 0); return .handled
        case .delete:
            Task { await viewModel.placeDigit(nil) }; return .handled
        default:
            break
        }
        // Character keys.
        let chars = keyPress.characters
        if chars == "p" || chars == "P" {
            viewModel.togglePencil()
            return .handled
        }
        if chars == "0" {
            Task { await viewModel.placeDigit(nil) }
            return .handled
        }
        if let scalar = chars.unicodeScalars.first,
           let digit = Int(String(scalar)),
           (1...9).contains(digit) {
            Task { await dispatchKeyboardDigit(digit) }
            return .handled
        }
        return .ignored
    }

    /// #790 fix 1: keyboard digits now share the SAME `keypadDigit` arm/place/
    /// pencil-note dispatch as the pointer-driven digit pad (`digitPad`'s
    /// `onDigit:` closure). `internal` (not `private`) so
    /// `BoardViewKeyboardDigitTests` can exercise it directly: SwiftUI's
    /// `KeyPress` has no public initializer (confirmed against Apple's
    /// Accessibility/SwiftUI sample code, which only ever receives one from
    /// `onKeyPress`'s closure, never constructs one), so the full
    /// `onKeyPress` → `handleKeyPress` chain isn't unit-testable — this is
    /// the closest testable proxy for "what a digit key does."
    func dispatchKeyboardDigit(_ digit: Int) async {
        await viewModel.keypadDigit(digit)
    }
}
