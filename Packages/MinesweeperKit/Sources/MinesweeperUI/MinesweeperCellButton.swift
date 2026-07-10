// MinesweeperCellButton + InteractionMode — the single-cell renderer for
// `MinesweeperBoardView`'s grid.
//
// Extracted from MinesweeperBoardView (#292) to keep that file under the
// 400-line lint ceiling once the Completion overlay wiring landed. No behavior
// change — verbatim move of the cell button + its tap-mode enum.

internal import SwiftUI
internal import MinesweeperEngine

// MARK: - Interaction mode

/// Which action a cell *tap* performs. Long-press / right-click always flag,
/// regardless of mode (#278 Tier-0 #3).
enum InteractionMode: Hashable {
    case reveal
    case flag
}

// MARK: - Cell button

struct MinesweeperCellButton: View {
    // #278 Tier-1 Phase 2b: read the injected theme + MS cell tokens. The board
    // is mounted under the `\.theme` + `\.minesweeperCell` injection at
    // `MinesweeperAppComposition.rootView`; every cell resolves tokens here
    // rather than reaching for raw SwiftUI primitives.
    @Environment(\.theme) private var theme
    @Environment(\.minesweeperCell) private var tokens

    let cell: Cell
    /// #298 #10: zero-based grid coordinates, surfaced (1-based) in the
    /// VoiceOver label so VO users can locate the cell.
    let row: Int
    let column: Int
    /// Side length in points, derived from the board GeometryReader.
    let side: CGFloat
    /// Current tap mode — drives the button's primary action.
    let mode: InteractionMode
    /// #298 #7: when the game is lost, every mine is surfaced — a still-hidden
    /// mine cell renders the soft `mine` token + glyph (the detonated cell
    /// stays `.revealed` + bold `mineHit`). Off during play so hidden cells stay
    /// covered.
    let revealMines: Bool
    let onReveal: () -> Void
    let onToggleFlag: () -> Void

    /// True when this cell should be drawn as a surfaced (non-detonated) mine:
    /// the game is lost, the cell holds a mine, and it isn't already revealed
    /// (the revealed-mine path is the detonated cell, handled separately).
    private var showsLostMine: Bool {
        revealMines && cell.isMine && cell.state != .revealed
    }

    var body: some View {
        // Primary action follows the on-screen mode: tap reveals in .reveal,
        // flags in .flag. The long-press / right-click accelerators below flag
        // in either mode.
        Button(action: mode == .flag ? onToggleFlag : onReveal) {
            ZStack {
                background
                content
            }
            .frame(width: side, height: side)
            // Ensure the whole cell square is hit-testable under .plain, not
            // just the drawn glyph (swiftui-interaction-footguns: tap target).
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // Platform-gated flag accelerator. On iOS we use long-press; on macOS
        // we use the context menu (right-click). The long-press only acts in
        // `.reveal` mode: in `.flag` mode the tap already flags, and the
        // button's touch-up tap + the long-press would both fire onToggleFlag,
        // netting a no-op (#278 CR). In `.flag` mode the accelerator is
        // redundant, so we make it inert there.
        #if os(iOS)
        .onLongPressGesture(minimumDuration: 0.35) {
            if mode == .reveal { onToggleFlag() }
        }
        #elseif os(macOS)
        .contextMenu {
            Button(flagToggleTitle) {
                onToggleFlag()
            }
        }
        #endif
        // #298 #10: VoiceOver. Mirror Sudoku's BoardCellView AX — collapse the
        // ZStack into one element, a "Row R, Column C, <state>" label, the
        // button trait, and a named Flag/Unflag action so VO users can flag
        // without the long-press / right-click accelerators (which VO can't
        // reach). The flag action is omitted on revealed cells (nothing to
        // flag) and once the game is terminal (board is frozen).
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: flagActionName) {
            if cell.state != .revealed, !revealMines { onToggleFlag() }
        }
    }

    /// VoiceOver action title for the flag toggle (mirrors the macOS context
    /// menu wording).
    private var flagActionName: Text {
        Text(flagToggleTitle)
    }

    /// #741: the macOS context-menu button and the VoiceOver action name show
    /// the same Flag/Unflag word — computed once here via `String(localized:)`
    /// so both resolve through the catalog instead of the previous bare-ternary
    /// literal (which bypassed it: a `Text`/`Button` initializer fed a runtime
    /// `String` rather than a `LocalizedStringKey` literal). Reuses the "Flag"
    /// key already added by #731's mode toggle.
    private var flagToggleTitle: String {
        cell.state == .flagged
            ? String(localized: "Unflag", bundle: .main)
            : String(localized: "Flag", bundle: .main)
    }

    @ViewBuilder
    private var background: some View {
        let shape = RoundedRectangle(cornerRadius: 4)
        if isRaisedCover {
            // #298 #8: covered cells get a subtle raised-tile treatment — a soft
            // top highlight + a thin lower edge — so covered-vs-revealed reads
            // as raised-vs-recessed (the classic Minesweeper tactile affordance)
            // rather than a flat colour swap. Derived from the covered token via
            // translucent white/black overlays, so it adapts to light + dark
            // without new theme tokens.
            shape.fill(tokens.covered.resolved)
                .overlay(
                    shape.fill(
                        LinearGradient(
                            colors: [.white.opacity(0.18), .clear],
                            startPoint: .top,
                            endPoint: .center
                        )
                    )
                )
                .overlay(shape.strokeBorder(.black.opacity(0.14), lineWidth: 0.5))
        } else if isRevealedSafe {
            // #649: revealed-safe cells (empty + numbered) need a hairline
            // recessed border so the grid footprint stays parseable after a
            // flood-fill clear. Without it the `revealed` token (#FFFFFF in
            // light mode) blends into the page background and the swept area
            // loses all structure. 10 % black opacity reads as a subtle inset
            // in light mode and adapts gracefully to dark (the dark `revealed`
            // token is already distinct from covered, so the border just
            // reinforces the boundary).
            shape.fill(tokens.revealed.resolved)
                .overlay(shape.strokeBorder(.black.opacity(0.10), lineWidth: 0.5))
        } else {
            shape.fill(backgroundFill)
        }
    }

    /// Covered (still-tappable) cells that should read as a raised tile — i.e.
    /// not a surfaced lost-mine and not yet revealed.
    private var isRaisedCover: Bool {
        !showsLostMine && (cell.state == .hidden || cell.state == .flagged)
    }

    /// True when the cell is revealed and safe (empty or numbered) — needs the
    /// recessed hairline border (#649) so the grid stays visible after a clear.
    /// Excludes the detonated-mine cell (`cell.isMine` on `.revealed`) and the
    /// surfaced-mine-on-loss path (`showsLostMine`), both of which have their
    /// own distinct fills.
    private var isRevealedSafe: Bool {
        !showsLostMine && cell.state == .revealed && !cell.isMine
    }

    private var backgroundFill: Color {
        // #298 #7: on loss, a still-hidden mine surfaces with the soft `mine`
        // fill (distinct from the detonated `mineHit` red below).
        if showsLostMine {
            return tokens.mine.resolved
        }
        switch cell.state {
        case .hidden, .flagged:
            return tokens.covered.resolved
        case .revealed:
            // A revealed mine is the detonated cell (the one the player hit),
            // so it gets the bold mineHit red; revealed-safe cells get the
            // revealed bg.
            return cell.isMine ? tokens.mineHit.resolved : tokens.revealed.resolved
        }
    }

    @ViewBuilder
    private var content: some View {
        // #298 #7: a still-hidden mine surfaced on loss draws the mine glyph
        // (a flagged mine keeps its flag below — it was correctly flagged).
        if showsLostMine, cell.state == .hidden {
            mineGlyph(detonated: false)
        } else {
            switch cell.state {
            case .hidden:
                EmptyView()
            case .flagged:
                Image(systemName: "flag.fill")
                    .font(.system(size: glyphSize))
                    .foregroundStyle(theme.status.warning.resolved)
            case .revealed:
                if cell.isMine {
                    mineGlyph(detonated: true)
                } else if cell.neighborMineCount > 0 {
                    Text("\(cell.neighborMineCount)")
                        .font(.system(size: glyphSize, weight: .semibold, design: .rounded))
                        .foregroundStyle(numberColor(cell.neighborMineCount))
                } else {
                    EmptyView()
                }
            }
        }
    }

    // #298 #8: the mine glyph. A filled `xmark.octagon` reads more clearly as a
    // mine/hazard than the previous `burst.fill` starburst (which looked like a
    // generic sparkle). The detonated cell sits on the bold `mineHit` red, so
    // its glyph is white for max contrast; a surfaced (non-detonated) mine sits
    // on the soft `mine` fill, so its glyph uses the error token for legibility.
    private func mineGlyph(detonated: Bool) -> some View {
        Image(systemName: "xmark.octagon.fill")
            .font(.system(size: glyphSize))
            .foregroundStyle(detonated ? .white : theme.status.error.resolved)
    }

    // Glyph size tracks the cell side so numbers/flags/mines stay proportional
    // as the board scales (spec: ≈ side * 0.55). Fixed-size font (not a Dynamic
    // Type text style) keeps the grid stable per swiftui-interaction-footguns.
    private var glyphSize: CGFloat { side * 0.55 }

    private func numberColor(_ count: Int) -> Color {
        // #278 Tier-1 Phase 2b: MS-flavoured 1–8 palette from the injected
        // cell tokens (was system .blue/.green/.red/...).
        tokens.number(count).resolved
    }

    private var accessibilityLabel: String {
        // #298 #10: "Row R, Column C, <state>" — mirrors Sudoku BoardCellView
        // §How.5.7. Coordinates are 1-based for VO; state defers to the
        // lost-mine surfacing first.
        let location = "Row \(row + 1), Column \(column + 1)"
        return "\(location), \(stateDescription)"
    }

    private var stateDescription: String {
        // #741: this switch fed bare English literals straight into
        // `accessibilityLabel` — same bug class as the context-menu Flag/Unflag
        // ternary above. Each branch now resolves through the catalog; the
        // neighbor-mine-count branch stays a raw numeral (no l10n needed).
        if showsLostMine { return String(localized: "Mine", bundle: .main) }
        switch cell.state {
        case .hidden:   return String(localized: "Hidden", bundle: .main)
        case .flagged:  return String(localized: "Flagged", bundle: .main)
        case .revealed:
            if cell.isMine { return String(localized: "Mine", bundle: .main) }
            return cell.neighborMineCount == 0
                ? String(localized: "Empty", bundle: .main)
                : "\(cell.neighborMineCount)"
        }
    }
}
