// MinesweeperControlClusterView — Minesweeper's board control cluster ("G4"),
// extracted from MinesweeperBoardView by #1022.
//
// Mirrors Sudoku's `DigitPadView` in SHAPE, not in content: both build
// `GameShellUI.BoardControlCluster`, both take plain values plus closures
// rather than reaching into a view model, and both keep the same group
// ordering across platforms (design.md §4.6: "maintain consistent groupings
// and placement across platforms"). What differs is what goes in the groups,
// because the two games' controls genuinely differ — which is exactly why this
// is a mirrored shape and NOT a copy of `DigitPadView` (see CLAUDE.md's mirror
// principle: every cross-app drift so far lived in copy-paste-and-adapt
// wrappers).
//
// ## Why Minesweeper ships ONE group
//
// design.md §3.4 and #1022 both describe Minesweeper's cluster as "揭開/旗標
// 模式切換 + undo" — but **Minesweeper has no undo**, at any layer. There is no
// `canUndo`, no `undo()`, and the scope comments say so outright
// (`MinesweeperSession.swift`, `MinesweeperGameViewModel.swift`). The engine's
// `moves: [Move]` is a forward-only replay log used for determinism tests and
// is discarded on state restore, not an undo stack.
//
// So the edit group has nothing real to hold. It is OMITTED rather than
// rendered empty or filled with a disabled placeholder button: a dead control
// reads as a broken one, and this repo has already paid for that lesson once
// (the `try?`-hidden Game Center stubs that left a permanently failing Friends
// tab looking live). Adding undo is engine work, tracked as #1052; when it
// lands, this view gains the second group and `BoardControlCluster`'s two-group
// initializer already accepts it.
//
// ## Glass
//
// The mode toggle carries its own `.buttonStyle(.glass)` / `.glassProminent` —
// the container never gets `.glassEffect` applied to itself (design.md §12
// error #8; see `BoardControlCluster`'s header). The selected-mode tint is the
// ONE colored control this glass piece is allowed (§4.7: the glass surface
// itself is never tinted, and state indicators are exactly the case where
// color IS permitted).

internal import GameShellUI
import SwiftUI

struct MinesweeperControlClusterView: View {
    let interactionMode: InteractionMode
    let onToggleMode: () -> Void

    @Environment(\.theme) private var theme
    @ScaledSpacing(.small) private var toggleChipPadding

    var body: some View {
        BoardControlCluster {
            modeToggle
        }
    }

    // Discoverable primary control for reveal vs flag. #724: the segmented
    // Picker (two always-visible options) was replaced with a single icon
    // toggle button — same role (routes which action a cell tap fires), half
    // the footprint. #767 (audit N2): an icon-only button gave sighted users
    // no in-context hint of which mode was active or what a tap would do —
    // the mode name was VoiceOver-only. The label pairs the icon with the same
    // "Reveal"/"Flag" text already in the catalog (#742), so the active mode
    // reads without opening the a11y tree. Tapping flips to the other mode.
    // Long-press-to-flag (MinesweeperCellButton, unchanged) still works as the
    // accelerator in `.reveal` mode.
    @ViewBuilder
    private var modeToggle: some View {
        // `.glassProminent` and `.glass` are distinct concrete ButtonStyle
        // types, so the two branches need a `Group { if/else }` split rather
        // than a ternary passed to one `.buttonStyle(...)` call — the same
        // pattern Sudoku's armed-digit key uses.
        Group {
            if interactionMode == .flag {
                Button(action: onToggleMode) {
                    // #797/#786: the ink MUST sit on the label content — a
                    // prominent style resolves its own label ink internally and
                    // ignores an ambient `.foregroundStyle` set on the Button.
                    // `accent.muted` is a background-only token
                    // (design-system.md §Color), so content on top of it takes
                    // `text.primary` to hold contrast, exactly as the
                    // pre-#1022 `.borderedProminent` branch did.
                    toggleLabel.foregroundStyle(theme.text.primary.resolved)
                }
                    // Flag mode is the state indicator this glass piece is
                    // allowed to color (§4.7). #767: it uses `accent.muted`
                    // rather than `status.warning`, which read as "something is
                    // wrong" for a routine mode switch and isn't a status-signal
                    // use per design-system.md's token table.
                    .buttonStyle(.glassProminent)
                    // swiftui-interaction-footguns: theme tint doesn't
                    // auto-propagate to system controls — apply it explicitly.
                    .tint(theme.accent.muted.resolved)
            } else {
                Button(action: onToggleMode) { toggleLabel }
                    .buttonStyle(.glass)
            }
        }
        .accessibilityLabel(Text(String(format: Self.modeToggleLabelFormat, modeName)))
        .accessibilityValue(Text(modeName))
        .accessibilityHint(Text(Self.modeToggleHint))
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("minesweeper.board.tapModeToggle")
    }

    private var toggleLabel: some View {
        Label {
            Text(modeName)
                .font(.system(size: 13, weight: .semibold))
        } icon: {
            Image(systemName: interactionMode == .flag ? "flag.fill" : "hand.tap.fill")
                .font(.system(size: 18, weight: .semibold))
        }
        // #786 item 1 (#780 review): was a hard-coded `12` literal.
        // `SpacingTokens` names no 12 step (8/16/24/32), so this snaps to
        // `small` (8): closer to the chip's #724 "half the footprint" intent
        // than `medium` (16), which the design-system pairing table reserves
        // for card-level internal padding. The `.frame(minWidth:minHeight:)`
        // floor below guarantees the HIG tap target independent of it.
        .padding(.horizontal, toggleChipPadding)
        .frame(minWidth: 44, minHeight: 44)
    }

    // #731: the mode name and the a11y strings around the toggle were bare
    // English literals never extracted to the catalog. `modeName` mirrors
    // "Reveal"/"Flag" (also the label's %@ substitution and the standalone
    // accessibility value); `modeToggleLabelFormat` mirrors `ResumeTitle`'s
    // "Resume %@" pattern — a catalog format key resolved via `String(format:)`
    // rather than string interpolation, so both the prefix and the mode name
    // localize.
    private var modeName: String {
        interactionMode == .flag
            ? String(localized: "Flag", bundle: .main)
            : String(localized: "Reveal", bundle: .main)
    }

    private static var modeToggleLabelFormat: String {
        String(localized: "Tap mode: %@", bundle: .main)
    }

    private static var modeToggleHint: String {
        String(localized: "Double tap to switch tap mode", bundle: .main)
    }
}
