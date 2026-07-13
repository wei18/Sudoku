// BoardCellView — single 9×9 board cell.
//
// Per docs/designs/05-board.md. Five visual variants:
//   - empty / given / userFilled / error / selected
// Color-blind dual encoding for errors: bg tint + corner triangle.

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

    @Environment(\.theme) private var theme
    @Environment(\.sudokuCell) private var cell
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
                ErrorTriangle()
                    .fill(cell.errorBorder.resolved)
                    .frame(width: side * 0.18, height: side * 0.18)
                    .padding(2)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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

    private var accessibilityLabel: String {
        // §How.5.7 format: "Row R, Column C, <state>". #755 routed the location
        // prefix through the catalog; #771 routes the state suffix too (was
        // bare interpolation bypassing l10n).
        let location = String(localized: "Row \(row + 1), Column \(column + 1)", bundle: .main)
        if isError, let digit {
            return "\(location), \(String(localized: "conflict \(digit)", bundle: .main))"
        }
        if let digit {
            if isGiven {
                return "\(location), \(String(localized: "given \(digit)", bundle: .main))"
            }
            return "\(location), \(String(localized: "value \(digit)", bundle: .main))"
        }
        return "\(location), \(String(localized: "Empty", bundle: .main))"
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
        .padding(2)
    }
}
