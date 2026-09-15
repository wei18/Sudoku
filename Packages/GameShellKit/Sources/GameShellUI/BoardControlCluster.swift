// BoardControlCluster — the shared SHAPE of the board's bottom control
// cluster ("G4" in docs/designs/v3/design.md §4.1), mirrored by both games.
//
// Why a shared shape rather than two hand-written clusters: every cross-app
// drift this repo has paid for (#448's phantom button, dead banner, missing
// resume) lived in per-app wrappers that started as a copy-paste and then
// diverged. The two games' CONTROLS genuinely differ — Sudoku has nine digit
// keys plus undo/redo/notes/erase, Minesweeper has a single reveal/flag mode
// toggle — so what is shared here is the container shape, the grouping rule
// and the glass mechanics, not the buttons. Each app supplies its own group
// contents.
//
// ## The two-group rule (design.md §4.6, binding)
//
// **【官方】** "Group items that perform similar actions or affect the same
// part of the interface, and maintain consistent groupings and placement
// across platforms" — and, in the same passage, "don't mix text and icons
// across items that share a background".
//
// Sudoku's digit keys are TEXT and its tool keys are ICONS, so they cannot
// share one glass background. G4 is therefore two groups:
//
//   - the **input** group — what the player is entering (Sudoku: 1–9;
//     Minesweeper: the reveal/flag mode toggle);
//   - the **edit** group — what the player does to what they already
//     entered (Sudoku: undo / redo / notes / erase).
//
// Minesweeper has no edit-group controls today (it has no undo — see #1052),
// so it uses the single-group initializer and ships one populated group. The
// group is OMITTED, never rendered empty and never filled with a disabled
// placeholder: a dead control is worse than an absent one.
//
// ## Glass mechanics (design.md §4.6, resolved by the #1029 B-7 spike)
//
// Each BUTTON carries its own `.glassEffect` / `.buttonStyle(.glass)`; the
// container does NOT get glass applied to itself. This is design.md §12's
// error #8, corrected: per the SwiftUI documentation, "Each view with a Liquid
// Glass effect contributes a shape rendered with the effect to a set of
// shapes" — the container merges its children's shapes, so a container with no
// glassy children is simply an empty container.
//
// The #1029 B-7 spike (verdict PASS, 2026-09-01) confirmed on-device that
// `GlassEffectContainer` merges `.buttonStyle(.glass)` children exactly as it
// merges explicit `.glassEffect()` children, that the merge is proximity
// driven, and — via a no-container control row — that the merging is genuinely
// the container's shape-union rather than the button style's own styling.
//
// Each group gets its OWN `GlassEffectContainer` so the two groups can never
// blend into one background no matter how close they are laid out. Sharing one
// container and relying on distance would make the "text and icons never share
// a background" rule a function of the gap between them.
//
// Container spacing is left at the system default (design.md §4.6: "Prefer to
// use standard spacing metrics instead of overriding them"), so neither the
// container nor the stacks below pass a `spacing:` argument.

public import SwiftUI

/// The board's bottom control cluster: one or two glass groups.
///
/// Groups render top-down in the order the game reads them: the edit group
/// (what you do to what you already entered) sits above the input group (what
/// you are entering), matching both games' pre-existing control order.
public struct BoardControlCluster<Edit: View, Input: View>: View {
    private let edit: Edit?
    private let input: Input

    /// Two-group cluster — the full shape (Sudoku).
    public init(
        @ViewBuilder edit: () -> Edit,
        @ViewBuilder input: () -> Input
    ) {
        self.edit = edit()
        self.input = input()
    }

    public var body: some View {
        VStack {
            if let edit {
                // Group 1 — edit controls (icons).
                GlassEffectContainer {
                    edit
                }
            }
            // Group 2 — input controls (text, or a game's primary mode control).
            GlassEffectContainer {
                input
            }
        }
    }
}

extension BoardControlCluster where Edit == EmptyView {
    /// Single-group cluster, for a game with no edit-group controls yet
    /// (Minesweeper — see #1052). The edit group is omitted entirely rather
    /// than rendered empty, so no glass shape is drawn for a group that has
    /// nothing in it.
    public init(@ViewBuilder input: () -> Input) {
        self.edit = nil
        self.input = input()
    }
}
