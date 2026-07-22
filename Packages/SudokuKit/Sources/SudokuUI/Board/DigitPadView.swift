// DigitPadView — 1–9 + erase, plus undo / redo / pencil toggle.
//
// Per docs/designs/05-board.md. Two layouts:
//
//   • iPhone (compact size class): unified secondary-action row
//     (Undo / Redo / Notes / Erase, icon-only, 4 × 44pt) sits BETWEEN
//     the board and the 3×3 digit `Grid` (56pt keys) (#210, 2026-05-30).
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
    /// visual affordance as the Notes-mode toggle's active state. #939:
    /// sticky armed — a board-cell tap (even a mis-tap on a filled cell)
    /// never clears this; re-tapping the SAME digit here (`onDigit`, wired to
    /// `GameViewModel.keypadDigit`'s `armDigit` toggle) is the only disarm.
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
        // spacing-exempt: 12pt predates the 5-tier `SpacingTokens` scale —
        // no matching tier without snapping and changing this pad's
        // existing layout/snapshot (#762 PR2).
        VStack(spacing: 12) {
            compactControlRow
            compactDigitGrid
        }
        // Structural (#762 PR2 two-tier spacing contract) — horizontal
        // margin of the digit pad's control row + grid; fixed because it
        // bounds the available width for the fixed 44pt-minimum touch
        // targets laid out inside.
        .padding(.horizontal, theme.spacing.medium)
    }

    // Unified secondary-action row (#210): Undo · Redo · Notes · Erase,
    // icon-only, distributed across the digit-strip width with 44pt minimum
    // tap targets per HIG. Erase rightmost = right-thumb resting zone.
    private var compactControlRow: some View {
        // spacing-exempt: zero-gap — icon buttons distributed edge-to-edge
        // across the digit-strip width, not a spacing decision (#762 PR2).
        HStack(spacing: 0) {
            Button(action: onUndo) {
                // #855 F-5 (sim-confirmed): an unconditional `.foregroundStyle`
                // here made a `.disabled` Undo render IDENTICAL to the always-
                // enabled Erase icon — same footgun class as #797 (explicit
                // ink on the label content wins over the environment's
                // automatic disabled-dimming). Conditioning the ink on
                // `canUndo` restores the gray-out; `text.tertiary` matches
                // the documented disabled convention (docs/designs/05-board.md
                // §d "Undo/Redo … disabled = text.tertiary").
                Image(systemName: "arrow.uturn.backward")
                    .foregroundStyle(canUndo ? theme.accent.primary.resolved : theme.text.tertiary.resolved)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .frame(minWidth: 44, minHeight: 44)
            .disabled(!canUndo)
            .accessibilityLabel("Undo")

            Button(action: onRedo) {
                // #855 F-5: same fix as Undo above.
                Image(systemName: "arrow.uturn.forward")
                    .foregroundStyle(canRedo ? theme.accent.primary.resolved : theme.text.tertiary.resolved)
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
            .accessibilityValue(Self.pencilModeAccessibilityValue(pencilMode))
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
        // #855 adjudicated extra: the selected-cell gate only blocks DIRECT
        // PLACEMENT of an exhausted digit — pencil notes are annotations and
        // don't care about remaining count, so an exhausted digit stays
        // tappable while `pencilMode` is on (matches the digit-first/no-
        // selection path, which never gated on remaining count either).
        let isDisabled = Self.isDigitDisabled(hasSelection: hasSelection, remaining: remaining, pencilMode: pencilMode)
        Group {
            if isArmed {
                Button {
                    onDigit(digit)
                } label: {
                    // #797: `.foregroundStyle` MUST be applied to the label
                    // content here (not chained after `.buttonStyle` below) —
                    // `.borderedProminent` resolves its own white label ink
                    // internally and ignores an ambient `.foregroundStyle` set
                    // on the Button itself (sim-verified: chaining it outside
                    // rendered white, unchanged). `.borderedProminent`'s system
                    // default label ink hard-fails AA against Sudoku's dark-mode
                    // accent.primary (white on 0x9BB87E = 2.20:1). Same
                    // on-accent-ink pattern as #786's mode toggle: `surface.primary`
                    // (0xFFFFFF light / 0x1E2024 dark) resolves to 4.83:1 light /
                    // 7.42:1 dark against accent.primary — both AA. Light mode
                    // renders byte-identically (still white). #855 F-1: the
                    // inner remaining-count badge now ALSO takes this ink when
                    // armed (passed through `isArmed`) — previously it kept its
                    // own explicit `foregroundStyle` (a more specific modifier
                    // wins over this ancestor one), which on the solid accent
                    // fill measured 1.45:1 light / 1.02:1 dark. Routing the
                    // badge through the same on-accent ink brings it to the
                    // same 4.83:1 / 7.42:1 as the digit glyph.
                    compactDigitLabel(digit: digit, remaining: remaining, isArmed: true)
                        .foregroundStyle(theme.surface.primary.resolved)
                }
                .buttonStyle(.borderedProminent)
            } else {
                Button { onDigit(digit) } label: { compactDigitLabel(digit: digit, remaining: remaining, isArmed: false) }
                    .buttonStyle(.bordered)
            }
        }
        .tint(theme.accent.primary.resolved)
        .disabled(isDisabled)
        .opacity(Self.digitButtonOpacity(remaining: remaining, isArmed: isArmed, isDisabled: isDisabled))
        .accessibilityLabel("Digit \(digit)")
        .accessibilityValue(Self.digitAccessibilityValue(remaining: remaining))
        .accessibilityHint(Self.digitAccessibilityHint(hasSelection: hasSelection))
        .accessibilityAddTraits(isArmed ? .isSelected : [])
    }

    private func compactDigitLabel(digit: Int, remaining: Int, isArmed: Bool) -> some View {
        // spacing-exempt: 2pt — digit-key face geometry (this VStack sits
        // inside a fixed `minHeight: 56` key); board/digit-pad cell/key
        // geometry stays structural and must not scale with Dynamic Type
        // (design-system.md §Spacing scale), and 2pt isn't on the 5-tier
        // `SpacingTokens` scale (#762 PR2).
        VStack(spacing: 2) {
            Text("\(digit)")
                .font(.title2.weight(.medium))
            if remaining > 0 {
                Text("\(remaining)")
                    .font(.caption2)
                    .foregroundStyle(isArmed
                        ? theme.surface.primary.resolved
                        : (remaining == 1
                            ? theme.accent.primary.resolved
                            : theme.text.secondary.resolved))
            } else {
                // #855 F-2: "fully placed" is now a positive signal (a small
                // checkmark) rather than pure whole-key dimming — dimming
                // alone reads as "disabled" even on the still-tappable
                // exhausted-but-enabled key. `text.secondary` ink at full
                // opacity measures ≥6.6:1 against the pad background in
                // both themes.
                Image(systemName: "checkmark")
                    .font(.caption2)
                    .foregroundStyle(isArmed ? theme.surface.primary.resolved : theme.text.secondary.resolved)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 56)
    }

    // MARK: - Mac (regular) layout

    private var macLayout: some View {
        // spacing-exempt: 12pt predates the 5-tier `SpacingTokens` scale —
        // no matching tier without snapping and changing this rail's
        // existing layout/snapshot (#762 PR2).
        VStack(spacing: 12) {
            macHistoryRow
            macNotesToggle
            macDigitGrid
            macEraseRow
        }
        .frame(maxWidth: 260)
    }

    private var macHistoryRow: some View {
        // spacing-exempt: 12pt predates the 5-tier `SpacingTokens` scale —
        // same rationale as `macLayout` above (#762 PR2).
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
                    // #797 (CR round 2): same on-accent-ink fix + label-content
                    // placement as `compactDigitButton` / `macDigitButton` —
                    // this prominent branch is the same construct and had the
                    // same dark-mode failure (white on 0x9BB87E = 2.20:1;
                    // surface.primary = 4.83:1 light / 7.42:1 dark).
                    Label("Notes", systemImage: "pencil")
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .foregroundStyle(theme.surface.primary.resolved)
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
        .accessibilityValue(Self.pencilModeAccessibilityValue(pencilMode))
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
                Button {
                    onDigit(digit)
                } label: {
                    // #797: same on-accent-ink fix as `compactDigitButton`
                    // above, same placement requirement (label content, not
                    // chained after `.buttonStyle`).
                    macDigitLabel(digit: digit)
                        .foregroundStyle(theme.surface.primary.resolved)
                }
                .buttonStyle(.borderedProminent)
            } else {
                Button { onDigit(digit) } label: { macDigitLabel(digit: digit) }
                    .buttonStyle(.bordered)
            }
        }
        // Palette sweep (#610 fix *5): match iPhone digit tint.
        .tint(theme.accent.primary.resolved)
        .accessibilityLabel("Digit \(digit)")
        // #855 F-8: same digit-first arm-vs-place disambiguation as
        // `compactDigitButton` — Mac shares the same `onDigit` semantics.
        .accessibilityHint(Self.digitAccessibilityHint(hasSelection: hasSelection))
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
