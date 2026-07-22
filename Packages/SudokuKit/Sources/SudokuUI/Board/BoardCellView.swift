// BoardCellView — single 9×9 board cell.
//
// Per docs/designs/05-board.md. Five visual variants:
//   - empty / given / userFilled / error / selected
// Color-blind dual encoding for errors: bg tint + corner triangle + a
// cell-wrapping inset border (#850 — the only bordered board state, so
// error stays structurally dominant over the neutral `sameDigit` fill).

import SwiftUI
import SudokuEngine
import GameShellUI

struct BoardCellView: View {
    let row: Int
    let column: Int
    let digit: Int?
    let isGiven: Bool
    let isSelected: Bool
    let isError: Bool
    let isHighlighted: Bool   // shares row / column / box with selection
    let isSameDigit: Bool     // non-selected cell carrying the same digit
    let isPencilNotes: Bool
    let noteMask: UInt16
    let side: CGFloat
    /// #790 fix 2: the digit currently armed for digit-first placement
    /// (`GameViewModel.armedDigit`), or `nil`. Meaningful for empty cells
    /// (tapping ANY empty cell places it, `tapCell`) AND, per #939's sticky-
    /// armed decision, for a user-filled cell already holding this same
    /// digit (tapping it clears the cell instead of selecting it) — neither
    /// case is tied to a specific row/column.
    let armedDigit: Int?
    /// #939: whether digit input currently writes pencil notes. Needed ONLY
    /// to gate the "will clear" a11y hint below — in pencil mode, a tap on a
    /// user-filled cell holding the armed digit toggles a note (non-
    /// destructive), not a clear, so the hint must not claim otherwise.
    /// Defaults to `false` so every pre-#939 call site (none of which cared
    /// about pencil mode) keeps compiling unchanged.
    let pencilMode: Bool

    @Environment(\.theme) private var theme
    @Environment(\.sudokuCell) private var cell
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // #790: a `let` stored property with an inline default value does NOT
    // get a memberwise-init parameter (Swift bakes it in as a constant) —
    // this explicit init is required so `armedDigit` can both default to
    // `nil` (existing call sites keep compiling unchanged) AND be overridden
    // (BoardView+Highlighting.swift passes the live `viewModel.armedDigit`).
    init(
        row: Int,
        column: Int,
        digit: Int?,
        isGiven: Bool,
        isSelected: Bool,
        isError: Bool,
        isHighlighted: Bool,
        isSameDigit: Bool,
        isPencilNotes: Bool,
        noteMask: UInt16,
        side: CGFloat,
        armedDigit: Int? = nil,
        pencilMode: Bool = false
    ) {
        self.row = row
        self.column = column
        self.digit = digit
        self.isGiven = isGiven
        self.isSelected = isSelected
        self.isError = isError
        self.isHighlighted = isHighlighted
        self.isSameDigit = isSameDigit
        self.isPencilNotes = isPencilNotes
        self.noteMask = noteMask
        self.side = side
        self.armedDigit = armedDigit
        self.pencilMode = pencilMode
    }

    /// design-system.md §Motion "Error highlight pulse" (200 ms × 2,
    /// ease-in-out / reduced motion: static fill only). Starts at full
    /// opacity so a non-error cell never shows the pulse's low point; only
    /// `isError` becoming true (via `onChange` below) animates it down and
    /// back.
    @State private var errorPulseOpacity: Double = 1

    var body: some View {
        ZStack {
            background
                .animation(backgroundAnimation, value: isSelected)
            content
                .animation(digitAnimation, value: digit)
            if isError {
                // #850: bumped 0.18 → 0.30 of `side` — the triangle is a
                // colorblind-independent (shape, not hue) cue, and the
                // audit found the error state read weaker than the neutral
                // `sameDigit` green highlight at the old size.
                ErrorTriangle()
                    .fill(cell.errorBorder.resolved)
                    .frame(width: side * 0.30, height: side * 0.30)
                    // spacing-exempt: 2pt — board-cell geometry, sized off
                    // `side`; structural per design-system.md §Spacing scale
                    // and not on the 5-tier `SpacingTokens` scale (#762 PR2).
                    .padding(2)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .accessibilityHidden(true)
                // #850: cell-wrapping inset border — the ONLY bordered
                // state on the board (every other background priority tier
                // is a flat fill, see `background` below), so error stays
                // structurally dominant over `sameDigit`/`selected`/
                // `highlighted` regardless of how those fills get tuned
                // later. Third colorblind-independent channel alongside the
                // triangle and the (typical-vision) wash retune.
                RoundedRectangle(cornerRadius: 2)
                    .strokeBorder(cell.errorBorder.resolved, lineWidth: 3)
                    // spacing-exempt: 1.5pt — board-cell geometry, sized off
                    // `side`/the stroke width, not on the 5-tier
                    // `SpacingTokens` scale (#762 PR2 precedent).
                    .padding(1.5)
                    .accessibilityHidden(true)
            }
        }
        .frame(width: side, height: side)
        .overlay(borderOverlay)
        .opacity(errorPulseOpacity)
        .onChange(of: isError) { _, newValue in
            // #786 follow-up (#783 review): the reduce-motion decision routes
            // through the shared `MotionGate` (matching the two `.animation`
            // modifiers above) instead of a hand-written `!reduceMotion`
            // guard. `guard let` — not `withAnimation(nil)` — because a nil
            // animation would still dip the *value* to 0.55 for a frame;
            // MotionGate returning nil must mean "static fill only, no pulse"
            // (design-system.md §Motion reduced-motion column: off, not shorter).
            guard newValue,
                  let pulseLeg = MotionGate.animation(
                      .easeInOut(duration: 0.2), reduceMotion: reduceMotion
                  ) else {
                errorPulseOpacity = 1
                return
            }
            // Two explicit 200 ms ease-in-out legs (dip, then recover) rather
            // than `Animation.repeatCount(_:autoreverses:)` — the repeat/
            // autoreverse combination leaves the final *model* value
            // ambiguous, where chained `withAnimation(...completion:)` calls
            // land on a known `errorPulseOpacity` deterministically.
            withAnimation(pulseLeg) {
                errorPulseOpacity = 0.55
            } completion: {
                withAnimation(pulseLeg) {
                    errorPulseOpacity = 1
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(accessibilityTraits)
    }

    /// #473: a given (clue) cell is non-interactive — its tap is a no-op, so it
    /// must NOT be a VoiceOver button. Drives both the a11y trait below and
    /// `BoardView`'s decision to render givens without a `Button` wrapper.
    var isInteractive: Bool { !isGiven }

    private var accessibilityTraits: AccessibilityTraits {
        var traits: AccessibilityTraits = isInteractive ? .isButton : .isStaticText
        if isSelected { traits.insert(.isSelected) }
        return traits
    }

    // `internal` (not `private`) — like `isInteractive` above,
    // `BoardCellArmedAccessibilityTests` (#790 fix 2) reads this directly via
    // `@testable import` so the armed-digit hint is verified against the
    // REAL computed label, not a re-implementation that can't go red.
    var accessibilityLabel: String {
        // §How.5.7 format: "Row R, Column C, <state>". #755 routed the location
        // prefix through the catalog; #771 routes the state suffix too (was
        // bare interpolation bypassing l10n).
        let location = String(localized: "Row \(row + 1), Column \(column + 1)", bundle: .main)
        if isError, let digit {
            let conflictLabel = "\(location), \(String(localized: "conflict \(digit)", bundle: .main))"
            // #939 (round-2 review): `tapCell` doesn't special-case `isError`
            // — a conflicting user-filled cell holding the armed digit is
            // cleared exactly like a non-conflicting one, so the "will clear"
            // hint must fire here too (reusing the same catalog key; no new
            // string). Pencil mode is excluded for the same reason as the
            // non-error branch below: that tap toggles a note, not a clear.
            guard !isGiven, !pencilMode, digit == armedDigit else { return conflictLabel }
            return "\(conflictLabel), \(String(localized: "will clear \(digit)", bundle: .main))"
        }
        if let digit {
            if isGiven {
                return "\(location), \(String(localized: "given \(digit)", bundle: .main))"
            }
            let valueLabel = "\(location), \(String(localized: "value \(digit)", bundle: .main))"
            // #939: sticky-armed — tapping a user-filled cell that already
            // holds the ARMED digit clears it (destructive) instead of the
            // select() fallback this comment used to describe (that fallback
            // no longer exists post-#939: a mismatched/given tap while armed
            // is a silent no-op and keeps this bare `valueLabel`, which is
            // acceptable since nothing changes). Pencil mode is excluded:
            // there the same tap toggles a note (non-destructive), so
            // claiming "will clear" would be wrong — `pencilMode` is the only
            // reason this view needs that flag at all.
            guard !pencilMode, digit == armedDigit else { return valueLabel }
            return "\(valueLabel), \(String(localized: "will clear \(digit)", bundle: .main))"
        }
        let emptyLabel = "\(location), \(String(localized: "Empty", bundle: .main))"
        // #790 fix 2: while a digit is armed, this empty cell's tap semantics
        // change from select → place (BoardView+Highlighting.swift `tapCell`)
        // with no prior a11y signal. Append the pending-placement hint so
        // VoiceOver's name/role/value still matches actual behavior.
        guard let armedDigit else { return emptyLabel }
        return "\(emptyLabel), \(String(localized: "will place \(armedDigit)", bundle: .main))"
    }

    // bg priority: error > selected > sameDigit > highlighted (peer) > given > base
    @ViewBuilder
    private var background: some View {
        if isError {
            cell.error.resolved
        } else if isSelected {
            cell.selected.resolved
        } else if isSameDigit {
            cell.sameDigit.resolved
        } else if isHighlighted {
            cell.highlighted.resolved
        } else if isGiven {
            cell.prefilled.resolved
        } else {
            cell.base.resolved
        }
    }
    // design-system.md §Motion "Cell tap → selection" (100 ms ease-out).
    // Scoped to `isSelected` alone so the peer-highlight / same-digit /
    // given background swaps (not covered by this row) stay instant.
    private var backgroundAnimation: Animation? {
        MotionGate.animation(.easeOut(duration: 0.1), reduceMotion: reduceMotion)
    }

    // design-system.md §Motion "Cell digit place" (80 ms ease-out; the
    // 0.9→1.0 scale itself lives on the `.transition` at the Text above).
    private var digitAnimation: Animation? {
        MotionGate.animation(.easeOut(duration: 0.08), reduceMotion: reduceMotion)
    }

    @ViewBuilder
    private var content: some View {
        if let digit {
            Text("\(digit)")
                .font(.system(size: side * 0.6, weight: isGiven ? .semibold : .regular, design: .rounded))
                .foregroundStyle(digitColor)
                .monospacedDigit()
                // design-system.md §Motion "Cell digit place" (80 ms scale
                // 0.9→1.0 ease-out). `.transition` only fires on insertion/
                // removal, so `.id(digit)` forces every new digit (including
                // overwriting an existing one) to re-insert rather than
                // silently update the existing Text's content in place.
                .id(digit)
                .transition(.scale(scale: 0.9))
        } else if isPencilNotes, noteMask != 0 {
            PencilNotesGrid(mask: noteMask, side: side)
        } else {
            EmptyView()
        }
    }

    private var digitColor: Color {
        if isError {
            return theme.text.errorDigit.resolved
        }
        if isGiven {
            return theme.text.given.resolved
        }
        return theme.text.user.resolved
    }

    private var borderOverlay: some View {
        let thickRight = (column % 3 == 2) && column != 8
        let thickBottom = (row % 3 == 2) && row != 8
        return ZStack {
            Rectangle()
                .stroke(theme.text.tertiary.resolved.opacity(0.4), lineWidth: 0.5)
            if thickRight {
                HStack { Spacer(); Rectangle().fill(theme.text.primary.resolved).frame(width: 1.5) }
            }
            if thickBottom {
                VStack { Spacer(); Rectangle().fill(theme.text.primary.resolved).frame(height: 1.5) }
            }
        }
        .allowsHitTesting(false)
    }
}

private struct ErrorTriangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: rect.origin)
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

private struct PencilNotesGrid: View {
    let mask: UInt16
    let side: CGFloat
    @Environment(\.theme) private var theme

    var body: some View {
        // spacing-exempt: zero-gap — the pencil-notes 3×3 sub-grid's own
        // seams are cell geometry, not a spacing decision (#762 PR2).
        VStack(spacing: 0) {
            ForEach(0..<3, id: \.self) { row in
                HStack(spacing: 0) {
                    ForEach(0..<3, id: \.self) { col in
                        let digit = row * 3 + col + 1
                        let visible = (mask & (1 << digit)) != 0
                        Text(visible ? "\(digit)" : " ")
                            .font(.system(size: side * 0.22, design: .rounded))
                            .foregroundStyle(theme.text.tertiary.resolved)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
        }
        // spacing-exempt: 2pt — board-cell geometry (this grid renders
        // inside a single board cell, sized off `side`); structural per
        // design-system.md §Spacing scale and not on the 5-tier
        // `SpacingTokens` scale (#762 PR2).
        .padding(2)
    }
}
