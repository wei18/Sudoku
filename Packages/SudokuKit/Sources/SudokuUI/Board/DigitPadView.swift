// DigitPadView — 1–9 + erase, plus undo / redo / pencil toggle.
//
// Per docs/designs/05-board.md. Two layouts:
//
//   • iPhone (compact size class): unified secondary-action row
//     (Undo / Redo / Notes / Erase, icon-only, 4 × 44pt) sits BETWEEN
//     the board and the 1×9 digit strip (#210, 2026-05-30).
//   • Mac (regular size class): vertical right rail — history row, Notes
//     toggle (button-styled), 3×3 digit `Grid`, Erase row. The board
//     itself is laid out by BoardView; this view just owns the controls.
//
// Buttons are ≥ 44 pt tall for touch / pointer comfort. A single "pencil"
// icon carries the Notes-mode state via tint, matching iPad / Mac
// keyboard-input conventions (board-mac-redesign, 2026-05-30).

import SwiftUI

struct DigitPadView: View {
    let pencilMode: Bool
    let canUndo: Bool
    let canRedo: Bool
    let sizeClass: UserInterfaceSizeClass?
    let onDigit: (Int) -> Void
    let onErase: () -> Void
    let onTogglePencil: () -> Void
    let onUndo: () -> Void
    let onRedo: () -> Void

    @Environment(\.theme) private var theme

    var body: some View {
        if sizeClass == .regular {
            macLayout
        } else {
            compactLayout
        }
    }

    // MARK: - iPhone (compact) layout

    private var compactLayout: some View {
        VStack(spacing: 12) {
            compactControlRow
            digitRow
        }
        .padding(.horizontal, 16)
    }

    // Unified secondary-action row (#210): Undo · Redo · Notes · Erase,
    // icon-only, distributed across the digit-strip width with 44pt minimum
    // tap targets per HIG. Erase rightmost = right-thumb resting zone.
    private var compactControlRow: some View {
        HStack(spacing: 0) {
            Button(action: onUndo) {
                Image(systemName: "arrow.uturn.backward")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .frame(minWidth: 44, minHeight: 44)
            .disabled(!canUndo)
            .accessibilityLabel("Undo")

            Button(action: onRedo) {
                Image(systemName: "arrow.uturn.forward")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .frame(minWidth: 44, minHeight: 44)
            .disabled(!canRedo)
            .accessibilityLabel("Redo")

            Button(action: onTogglePencil) {
                Image(systemName: "pencil")
                    .foregroundStyle(pencilMode
                        ? theme.accent.primary.resolved
                        : theme.text.primary.resolved)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .frame(minWidth: 44, minHeight: 44)
            .accessibilityLabel("Notes")
            .accessibilityValue(pencilMode ? "On" : "Off")
            .accessibilityAddTraits(.isToggle)

            Button(action: onErase) {
                Image(systemName: "delete.left")
                    // Palette sweep (#610 fix *5): erase icon matches digit-pad accent.
                    .foregroundStyle(theme.accent.primary.resolved)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .frame(minWidth: 44, minHeight: 44)
            .accessibilityLabel("Erase")
        }
        .font(.title2)
    }

    private var digitRow: some View {
        // Each digit shares the available horizontal width equally so the
        // 9-button row never exceeds the parent at iPhone compact widths.
        //
        // #540: at accessibility text sizes the digit glyph rendered BLANK —
        // empty pills. Root cause: a single digit overflows VERTICALLY (glyph
        // ~50–60 pt tall in a ~44 pt `.bordered` pill) and gets clipped to
        // nothing. `minimumScaleFactor` is WIDTH-driven and never engages for a
        // 1-char string, so it can't rescue a height overflow. Fix: cap the
        // pad's Dynamic Type at `.xLarge` so the digits stay legible inside the
        // 44 pt pill regardless of the system AX setting (compact numeric
        // control convention). The cap only clamps sizes ABOVE `.xLarge`, so
        // the default `.large` rendering — and every committed snapshot — is
        // byte-identical. The board CELLS are unaffected and keep scaling.
        HStack(spacing: 6) {
            ForEach(1...9, id: \.self) { digit in
                Button {
                    onDigit(digit)
                } label: {
                    Text("\(digit)")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
                // Palette sweep (#610 fix *5): user-entry digit buttons match
                // the board's user-digit colour (sage-green) so they read as the
                // same brand accent instead of defaulting to system blue.
                .tint(theme.accent.primary.resolved)
                .accessibilityLabel("Digit \(digit)")
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.xLarge)
    }

    // MARK: - Mac (regular) layout

    private var macLayout: some View {
        VStack(spacing: 12) {
            macHistoryRow
            macNotesToggle
            macDigitGrid
            macEraseRow
        }
        .frame(maxWidth: 260)
    }

    private var macHistoryRow: some View {
        HStack(spacing: 12) {
            Button(action: onUndo) {
                Label("Undo", systemImage: "arrow.uturn.backward")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.bordered)
            .disabled(!canUndo)
            .accessibilityLabel("Undo")

            Button(action: onRedo) {
                Label("Redo", systemImage: "arrow.uturn.forward")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.bordered)
            .disabled(!canRedo)
            .accessibilityLabel("Redo")
        }
        .labelStyle(.iconOnly)
    }

    @ViewBuilder
    private var macNotesToggle: some View {
        // CR fix: use native `.borderedProminent`/`.bordered` (system focus
        // rings, hover, accent semantics) rather than a custom
        // `ButtonStyle` that bypasses theme tokens. `Group { if/else }`
        // wraps the two distinct ButtonStyle concrete types into one
        // `some View` without the type-erasure cost.
        Group {
            if pencilMode {
                Button(action: onTogglePencil) {
                    Label("Notes", systemImage: "pencil")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .tint(theme.accent.primary.resolved)
            } else {
                Button(action: onTogglePencil) {
                    Label("Notes", systemImage: "pencil")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
            }
        }
        .accessibilityLabel("Notes")
        .accessibilityValue(pencilMode ? "On" : "Off")
        .accessibilityAddTraits(.isToggle)
    }

    private var macDigitGrid: some View {
        // 3×3 fixed grid — each cell ≥ 64 pt per docs/designs/05-board.md §b
        // Mac wireframe. `Grid` (not `LazyVGrid`) keeps a fixed cell template
        // so the rail width never reflows when the parent resizes.
        Grid(horizontalSpacing: 8, verticalSpacing: 8) {
            ForEach(0..<3, id: \.self) { row in
                GridRow {
                    ForEach(1...3, id: \.self) { col in
                        let digit = row * 3 + col
                        Button {
                            onDigit(digit)
                        } label: {
                            Text("\(digit)")
                                .font(.title2.weight(.medium))
                                .frame(minWidth: 64, minHeight: 64)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        // Palette sweep (#610 fix *5): match iPhone digit tint.
                        .tint(theme.accent.primary.resolved)
                        .accessibilityLabel("Digit \(digit)")
                    }
                }
            }
        }
    }

    private var macEraseRow: some View {
        Button(action: onErase) {
            Label("Erase", systemImage: "delete.left")
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.bordered)
        // Palette sweep (#610 fix *5): match digit-pad accent.
        .tint(theme.accent.primary.resolved)
        .accessibilityLabel("Erase")
    }
}
