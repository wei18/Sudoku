// MinesweeperCellButton + InteractionMode — the single-cell renderer for
// `MinesweeperBoardView`'s grid.
//
// Extracted from MinesweeperBoardView (#292) to keep that file under the
// 400-line lint ceiling once the Completion overlay wiring landed. No behavior
// change — verbatim move of the cell button + its tap-mode enum.

public import SwiftUI
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
    /// Side length in points, derived from the board GeometryReader.
    let side: CGFloat
    /// Current tap mode — drives the button's primary action.
    let mode: InteractionMode
    let onReveal: () -> Void
    let onToggleFlag: () -> Void

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
            Button(cell.state == .flagged ? "Unflag" : "Flag") {
                onToggleFlag()
            }
        }
        #endif
        .accessibilityLabel(accessibilityLabel)
    }

    @ViewBuilder
    private var background: some View {
        switch cell.state {
        case .hidden, .flagged:
            RoundedRectangle(cornerRadius: 4)
                .fill(tokens.covered.resolved)
        case .revealed:
            RoundedRectangle(cornerRadius: 4)
                // A revealed mine is the detonated cell in Tier-0 (no
                // separate "other mine" branch yet), so it gets the bold
                // mineHit red; revealed-safe cells get the revealed bg.
                .fill(cell.isMine ? tokens.mineHit.resolved : tokens.revealed.resolved)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch cell.state {
        case .hidden:
            EmptyView()
        case .flagged:
            Image(systemName: "flag.fill")
                .font(.system(size: glyphSize))
                .foregroundStyle(theme.status.warning.resolved)
        case .revealed:
            if cell.isMine {
                Image(systemName: "burst.fill")
                    .font(.system(size: glyphSize))
                    .foregroundStyle(.white)
            } else if cell.neighborMineCount > 0 {
                Text("\(cell.neighborMineCount)")
                    .font(.system(size: glyphSize, weight: .semibold, design: .rounded))
                    .foregroundStyle(numberColor(cell.neighborMineCount))
            } else {
                EmptyView()
            }
        }
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
        switch cell.state {
        case .hidden:   return "Hidden"
        case .flagged:  return "Flagged"
        case .revealed:
            if cell.isMine { return "Mine" }
            return cell.neighborMineCount == 0 ? "Empty" : "\(cell.neighborMineCount)"
        }
    }
}
