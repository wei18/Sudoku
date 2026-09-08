// DigitPadView+Mac — the Mac (regular size class) arrangement of Sudoku's
// board control cluster.
//
// Extracted from DigitPadView.swift to keep that file under SwiftLint's
// file_length ceiling (repo convention: extract a `+Feature.swift` sibling
// rather than disabling the rule).
//
// Same two groups as the compact layout and in the same order — design.md
// §4.6 requires the GROUPING to stay consistent across platforms, not the
// axis — arranged as the right-hand rail the Mac wireframe locked in
// (docs/designs/05-board.md §b): history row, Notes toggle and Erase in the
// edit group, the 3×3 digit grid in the input group.

import GameShellUI
import SwiftUI

extension DigitPadView {
    // MARK: - Mac (regular) layout

    var macLayout: some View {
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
