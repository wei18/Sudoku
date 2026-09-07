// DigitPadView — Sudoku's board control cluster ("G4"): 1–9 + erase, plus
// undo / redo / pencil toggle.
//
// Per docs/designs/v3/design.md §3.4 / §4.6. #1022 rebuilt this as the
// two-group floating glass cluster described there; the shape itself lives in
// `GameShellUI.BoardControlCluster`, which Minesweeper mirrors. The grouping is
// binding and comes straight from the official guidance quoted in §4.6 —
// "don't mix text and icons across items that share a background":
//
//   • **edit group** (icons): Undo · Redo · Notes · Erase
//   • **input group** (text):  the 3×3 grid of digit keys 1–9
//
// Each BUTTON carries its own glass (`.buttonStyle(.glass)` /
// `.glassProminent`); the containers never get `.glassEffect` applied to
// themselves — see `BoardControlCluster`'s header for why (design.md §12
// error #8) and the #1029 B-7 spike verdict for the on-device confirmation
// that the system button styles merge inside a container exactly as explicit
// `.glassEffect()` children do.
//
// Two layouts, same two groups in the same order on both (design.md §4.6:
// "maintain consistent groupings and placement across platforms"):
//
//   • iPhone (compact size class): the edit row sits above the 3×3 digit grid,
//     the whole cluster floating below the full-bleed board.
//   • Mac (regular size class): the same two groups stacked in the right-hand
//     rail. The board itself is laid out by BoardView; this view just owns the
//     controls.
//
// Buttons are ≥ 44 pt tall for touch / pointer comfort. A single "pencil"
// icon carries the Notes-mode state via tint.
//
// #1022 coloring pass (design.md §4.7 — "Refrain from adding color to the
// background of multiple controls", at most ONE colored control per glass
// piece, and the glass surface itself is never tinted):
//   • the whole-grid pencil-mode border + sage wash is GONE. It tinted the
//     input group's entire background, which §4.7 forbids outright; Notes mode
//     is already signalled by the pencil button's own tint in the edit group.
//   • Erase and an enabled Undo / Redo lost their accent ink and are now
//     neutral, leaving exactly one colored control per group: the pencil in
//     the edit group (when Notes is on) and the armed digit in the input group
//     (at most one digit is armed at a time).
//   • the disabled Undo / Redo gray-out (#855 F-5) survives unchanged — the
//     ink is still conditioned on `canUndo` / `canRedo`, just between
//     `text.primary` and `text.tertiary` instead of accent and tertiary.
//
// Spacing is left at the system default throughout the cluster (design.md
// §4.6: "Prefer to use standard spacing metrics instead of overriding them"),
// so the stacks, the `Grid` and the glass containers pass no `spacing:`.

import GameShellUI
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
        BoardControlCluster {
            compactControlRow
        } input: {
            compactDigitGrid
        }
        // Structural (#762 PR2 two-tier spacing contract) — horizontal margin
        // of the floating cluster against the screen edge. The BOARD above is
        // full-bleed as of #1022; the cluster is not, because its buttons need
        // to read as a floating group over the background rather than as a
        // band welded to both edges.
        .padding(.horizontal, theme.spacing.medium)
    }

    // Edit group (#210, reshaped by #1022): Undo · Redo · Notes · Erase,
    // icon-only, distributed across the cluster width with 44pt minimum tap
    // targets per HIG. Erase rightmost = right-thumb resting zone.
    private var compactControlRow: some View {
        HStack {
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
                    .foregroundStyle(canUndo ? theme.text.primary.resolved : theme.text.tertiary.resolved)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.glass)
            .frame(minWidth: 44, minHeight: 44)
            .disabled(!canUndo)
            .accessibilityLabel("Undo")

            Button(action: onRedo) {
                // #855 F-5: same fix as Undo above.
                Image(systemName: "arrow.uturn.forward")
                    .foregroundStyle(canRedo ? theme.text.primary.resolved : theme.text.tertiary.resolved)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.glass)
            .frame(minWidth: 44, minHeight: 44)
            .disabled(!canRedo)
            .accessibilityLabel("Redo")

            // The ONE colored control this glass group is allowed (§4.7), and
            // only while Notes mode is on — off, it is neutral like its
            // neighbours.
            Button(action: onTogglePencil) {
                Image(systemName: "pencil")
                    .foregroundStyle(pencilMode
                        ? theme.accent.primary.resolved
                        : theme.text.primary.resolved)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.glass)
            .frame(minWidth: 44, minHeight: 44)
            .accessibilityLabel("Notes")
            .accessibilityValue(Self.pencilModeAccessibilityValue(pencilMode))
            .accessibilityAddTraits(.isToggle)

            Button(action: onErase) {
                Image(systemName: "delete.left")
                    .foregroundStyle(theme.text.primary.resolved)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.glass)
            .frame(minWidth: 44, minHeight: 44)
            .accessibilityLabel("Erase")
        }
        .font(.title2)
    }

    // Input group — iPhone 3×3 digit grid, mirroring `macDigitGrid` with
    // per-key remaining-count badges. #540: Dynamic Type capped at `.xLarge`.
    private var compactDigitGrid: some View {
        Grid {
            ForEach(0..<3, id: \.self) { row in
                GridRow {
                    ForEach(1...3, id: \.self) { col in
                        let digit = row * 3 + col
                        compactDigitButton(digit: digit, remaining: remainingCounts[digit - 1])
                    }
                }
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.xLarge)
    }

    // #722: `.buttonStyle(.glassProminent)` vs `.buttonStyle(.glass)` are
    // distinct concrete types, so the armed/unarmed branches need a
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
                    // a prominent style resolves its own white label ink
                    // internally and ignores an ambient `.foregroundStyle` set
                    // on the Button itself (sim-verified: chaining it outside
                    // rendered white, unchanged). The system default label ink
                    // hard-fails AA against Sudoku's dark-mode accent.primary
                    // (white on 0x9BB87E = 2.20:1). Same on-accent-ink pattern
                    // as #786's mode toggle: `surface.primary` (0xFFFFFF light
                    // / 0x1E2024 dark) resolves to 4.83:1 light / 7.42:1 dark
                    // against accent.primary — both AA. Light mode renders
                    // white either way. #855 F-1: the inner remaining-count
                    // badge now ALSO takes this ink when armed (passed through
                    // `isArmed`) — previously it kept its own explicit
                    // `foregroundStyle` (a more specific modifier wins over
                    // this ancestor one), which on the solid accent fill
                    // measured 1.45:1 light / 1.02:1 dark. Routing the badge
                    // through the same on-accent ink brings it to the same
                    // 4.83:1 / 7.42:1 as the digit glyph.
                    compactDigitLabel(digit: digit, remaining: remaining, isArmed: true)
                        .foregroundStyle(theme.surface.primary.resolved)
                }
                // The ONE colored control this glass group is allowed (§4.7):
                // at most one digit is armed at a time.
                .buttonStyle(.glassProminent)
                .tint(theme.accent.primary.resolved)
            } else {
                Button { onDigit(digit) } label: { compactDigitLabel(digit: digit, remaining: remaining, isArmed: false) }
                    .buttonStyle(.glass)
            }
        }
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
        BoardControlCluster {
            macEditGroup
        } input: {
            macDigitGrid
        }
        .frame(maxWidth: 260)
    }

    // Edit group on the rail: history row, Notes toggle, Erase — the same four
    // controls as the compact edit row, in the rail's vertical arrangement
    // (design.md §4.6 keeps the GROUPING consistent across platforms, not the
    // axis).
    private var macEditGroup: some View {
        VStack {
            macHistoryRow
            macNotesToggle
            macEraseRow
        }
    }

    private var macHistoryRow: some View {
        HStack {
            Button(action: onUndo) {
                Label("Undo", systemImage: "arrow.uturn.backward")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.glass)
            .disabled(!canUndo)
            .accessibilityLabel("Undo")

            Button(action: onRedo) {
                Label("Redo", systemImage: "arrow.uturn.forward")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.glass)
            .disabled(!canRedo)
            .accessibilityLabel("Redo")
        }
        .labelStyle(.iconOnly)
    }

    @ViewBuilder
    private var macNotesToggle: some View {
        // `Group { if/else }` wraps the two distinct ButtonStyle concrete
        // types into one `some View` without the type-erasure cost.
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
                // The ONE colored control the mac edit group is allowed (§4.7).
                .buttonStyle(.glassProminent)
                .tint(theme.accent.primary.resolved)
            } else {
                Button(action: onTogglePencil) {
                    Label("Notes", systemImage: "pencil")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.glass)
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
        Grid {
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
                // The ONE colored control the mac input group is allowed (§4.7).
                .buttonStyle(.glassProminent)
                .tint(theme.accent.primary.resolved)
            } else {
                Button { onDigit(digit) } label: { macDigitLabel(digit: digit) }
                    .buttonStyle(.glass)
            }
        }
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
        .buttonStyle(.glass)
        .accessibilityLabel("Erase")
    }
}
