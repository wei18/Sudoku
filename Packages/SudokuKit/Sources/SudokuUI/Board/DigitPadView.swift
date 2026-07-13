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
    /// Remaining count for each digit 1–9 (index 0 = digit 1 … index 8 = digit 9).
    let remainingCounts: [Int]
    /// #722 digit-first input: the digit currently armed (no cell selected,
    /// keypad-tapped), or `nil`. Drives the keypad's own highlight — same
    /// visual affordance as the Notes-mode toggle's active state.
    let armedDigit: Int?
    /// #722: whether a board cell is currently selected. When `true`, tapping
    /// a digit places/toggles-note directly (today's flow) so the existing
    /// `remaining == 0` disable gate still applies. When `false`, a tap only
    /// ARMS the digit (no immediate placement) — arming an exhausted digit is
    /// still valid for notes use, so the gate is relaxed.
    let hasSelection: Bool
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
            compactDigitGrid
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
                    .foregroundStyle(theme.accent.primary.resolved)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .frame(minWidth: 44, minHeight: 44)
            .disabled(!canUndo)
            .accessibilityLabel("Undo")

            Button(action: onRedo) {
                Image(systemName: "arrow.uturn.forward")
                    .foregroundStyle(theme.accent.primary.resolved)
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

    // iPhone 3×3 digit grid — mirrors `macDigitGrid` with per-key remaining-count
    // badges and a notes-mode visual signal (1 pt sage border + ~6 % sage wash).
    // #540: Dynamic Type capped at `.xLarge` (same rationale as old `digitRow`).
    private var compactDigitGrid: some View {
        Grid(horizontalSpacing: 8, verticalSpacing: 8) {
            ForEach(0..<3, id: \.self) { row in
                GridRow {
                    ForEach(1...3, id: \.self) { col in
                        let digit = row * 3 + col
                        compactDigitButton(digit: digit, remaining: remainingCounts[digit - 1])
                    }
                }
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(theme.accent.primary.resolved, lineWidth: pencilMode ? 1 : 0)
        )
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(theme.accent.primary.resolved.opacity(pencilMode ? 0.06 : 0))
        )
        .dynamicTypeSize(...DynamicTypeSize.xLarge)
    }

    // #722: `.buttonStyle(.borderedProminent)` vs `.buttonStyle(.bordered)`
    // are distinct concrete types, so the armed/unarmed branches need a
    // `Group { if/else }` split (same pattern as `macNotesToggle` below)
    // rather than a ternary passed to a single `.buttonStyle(...)` call.
    @ViewBuilder
    private func compactDigitButton(digit: Int, remaining: Int) -> some View {
        let isArmed = digit == armedDigit
        Group {
            if isArmed {
                Button { onDigit(digit) } label: { compactDigitLabel(digit: digit, remaining: remaining) }
                    .buttonStyle(.borderedProminent)
            } else {
                Button { onDigit(digit) } label: { compactDigitLabel(digit: digit, remaining: remaining) }
                    .buttonStyle(.bordered)
            }
        }
        .tint(theme.accent.primary.resolved)
        // #722: only the direct-placement path (a cell is selected) gates on
        // remaining count — with no selection, a tap only arms, and arming an
        // already-fully-placed digit is still valid for notes use.
        .disabled(hasSelection && remaining == 0)
        .opacity(Self.digitButtonOpacity(remaining: remaining, isArmed: isArmed))
        .accessibilityLabel("Digit \(digit)")
        .accessibilityValue(remaining > 0 ? "\(remaining) remaining" : "fully placed")
        .accessibilityAddTraits(isArmed ? .isSelected : [])
    }

    /// #790 fix 3: an exhausted-but-armed digit (remaining == 0, armed for
    /// notes use per `hasSelection`'s doc above) must stay full-opacity —
    /// dimming it to 0.35 while it renders `.borderedProminent` accent fill
    /// mixes "disabled" and "active" visual language. Extracted as a pure
    /// `static func` (not inlined in `.opacity(...)`) so this decision is
    /// unit-testable without rendering the view.
    static func digitButtonOpacity(remaining: Int, isArmed: Bool) -> Double {
        remaining == 0 && !isArmed ? 0.35 : 1.0
    }

    private func compactDigitLabel(digit: Int, remaining: Int) -> some View {
        VStack(spacing: 2) {
            Text("\(digit)")
                .font(.title2.weight(.medium))
            if remaining > 0 {
                Text("\(remaining)")
                    .font(.caption2)
                    .foregroundStyle(remaining == 1
                        ? theme.accent.primary.resolved
                        : theme.text.secondary.resolved)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 56)
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
                        macDigitButton(digit: row * 3 + col)
                    }
                }
            }
        }
    }

    // #722: same armed-highlight treatment as `compactDigitButton`, minus
    // the remaining-count badge/gate (Mac never disabled on remaining count).
    @ViewBuilder
    private func macDigitButton(digit: Int) -> some View {
        let isArmed = digit == armedDigit
        Group {
            if isArmed {
                Button { onDigit(digit) } label: { macDigitLabel(digit: digit) }
                    .buttonStyle(.borderedProminent)
            } else {
                Button { onDigit(digit) } label: { macDigitLabel(digit: digit) }
                    .buttonStyle(.bordered)
            }
        }
        // Palette sweep (#610 fix *5): match iPhone digit tint.
        .tint(theme.accent.primary.resolved)
        .accessibilityLabel("Digit \(digit)")
        .accessibilityAddTraits(isArmed ? .isSelected : [])
    }

    private func macDigitLabel(digit: Int) -> some View {
        Text("\(digit)")
            .font(.title2.weight(.medium))
            .frame(minWidth: 64, minHeight: 64)
            .frame(maxWidth: .infinity)
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
