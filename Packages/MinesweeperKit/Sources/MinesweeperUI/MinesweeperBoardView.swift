// MinesweeperBoardView — MVP SwiftUI board renderer.
//
// Renders an `MinesweeperGameViewModel` as a row-major grid of cell buttons:
//   - Tap = reveal OR flag, depending on the on-screen Reveal/Flag mode toggle
//     (#278 Tier-0 #3 — discoverable, works on iPhone tap + Mac click).
//   - Long-press (iOS) / secondary click via context menu (macOS) = toggle flag
//     (accelerators, available in either mode).
//
// The board grid is sized by a GeometryReader (#278 Tier-0 #1/#2): cell side is
// derived from the offered rect, fitting the NON-SQUARE board by its longer axis,
// and the board scrolls instead of shrinking below a tap-target floor.
//
// Win/lose overlay is plain Text on a translucent backdrop — no animation,
// no haptics, no localization (English inline per dispatch spec).

public import SwiftUI
public import MinesweeperEngine
public import MonetizationCore
internal import MinesweeperGameState

public struct MinesweeperBoardView: View {

    @State private var viewModel: MinesweeperGameViewModel
    // #278 Tier-0 #3: on-screen reveal/flag mode. View-local because it has no
    // engine semantics — it only routes which action a cell tap fires. Mirrors
    // Sudoku's pencil-mode toggle as a discoverable primary control.
    @State private var interactionMode: InteractionMode = .reveal
    // U15 (2026-06-03): banner slot wiring. Optional so the merged MVP `init`
    // shapes (used by `#Preview` + tests) keep compiling without monetization.
    // Production callsites wire both via `LiveRouteFactory`.
    private let adProvider: (any AdProvider)?
    private let adGate: AdGate?

    public init(
        viewModel: MinesweeperGameViewModel,
        adProvider: (any AdProvider)? = nil,
        adGate: AdGate? = nil
    ) {
        self._viewModel = State(initialValue: viewModel)
        self.adProvider = adProvider
        self.adGate = adGate
    }

    public init(
        difficulty: Difficulty = .beginner,
        seed: UInt64 = 0,
        adProvider: (any AdProvider)? = nil,
        adGate: AdGate? = nil
    ) {
        self._viewModel = State(initialValue: MinesweeperGameViewModel(difficulty: difficulty, seed: seed))
        self.adProvider = adProvider
        self.adGate = adGate
    }

    public var body: some View {
        VStack(spacing: 12) {
            statusBar
            modeToggle
            boardGrid
                .overlay(alignment: .center) {
                    if viewModel.isTerminal {
                        terminalOverlay
                    }
                }
            // Banner sits between the grid and the bottom edge. Mirrors
            // Sudoku's BoardView slot pattern. Suppressed during terminal
            // states (win / lose) — showing an ad on top of the "Boom" or
            // "You won" overlay contradicts the moment's tone, same way
            // Sudoku suppresses banners during pause.
            if !viewModel.isTerminal, let adProvider, let adGate {
                MinesweeperBannerSlotView(adProvider: adProvider, adGate: adGate)
            }
        }
        .padding()
        .task {
            await viewModel.refresh()
        }
    }

    // MARK: - Status bar

    private var statusBar: some View {
        // TimelineView ticks at 1 Hz so the elapsed-seconds counter visibly
        // ticks during `.playing`. The `.task` inside re-fires on each tick
        // because the timeline context changes, pulling a fresh snapshot
        // from the actor (which also refreshes flag/status displays).
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            HStack {
                Label("\(viewModel.remainingMineCount)", systemImage: "flag.fill")
                    .monospacedDigit()
                Spacer()
                Text(statusText)
                    .font(.headline)
                Spacer()
                Label("\(viewModel.elapsedSeconds)", systemImage: "clock")
                    .monospacedDigit()
            }
            .font(.subheadline)
            .task { await viewModel.refresh() }
        }
    }

    private var statusText: String {
        switch viewModel.status {
        case .idle:    return "Ready"
        case .playing: return "Playing"
        case .won:     return "You won"
        case .lost:    return "Boom"
        }
    }

    // MARK: - Mode toggle (#278 Tier-0 #3)

    // Discoverable primary control for reveal vs flag. Modeled on Sudoku's
    // pencil-mode toggle (DigitPadView): a segmented control that routes which
    // action a cell tap fires. Works identically on iPhone (tap) and Mac
    // (click) — the previously invisible right-click/long-press are now just
    // accelerators on top of this.
    private var modeToggle: some View {
        Picker("Tap mode", selection: $interactionMode) {
            Label("Reveal", systemImage: "hand.tap").tag(InteractionMode.reveal)
            Label("Flag", systemImage: "flag.fill").tag(InteractionMode.flag)
        }
        .pickerStyle(.segmented)
        .accessibilityLabel("Tap action mode")
        .accessibilityValue(interactionMode == .flag ? "Flag" : "Reveal")
    }

    // MARK: - Grid

    // Cell-side floor (pt). Below this the board scrolls rather than shrinking
    // cells into an un-tappable size (#278 Tier-0 #2). 32pt keeps a deliberate
    // reveal tap comfortable; flag taps are now mode-driven so no precision
    // long-press is required on small cells.
    private static let minCellSide: CGFloat = 32
    private static let cellSpacing: CGFloat = 2

    private var boardGrid: some View {
        // GeometryReader reports the offered rectangle; we derive a single
        // square cell side that fits the NON-SQUARE board by its longer axis
        // (Expert is 16×30), then floor it for crisp glyphs. If that would drop
        // below the tap-target floor we clamp to the floor and let the board
        // scroll in both axes instead of shrinking.
        GeometryReader { geo in
            let rows = viewModel.rows
            let cols = viewModel.columns
            let spacing = Self.cellSpacing
            // Subtract the inter-cell gaps before dividing so the cells (not
            // the gaps) fill the offered box exactly.
            let availW = geo.size.width - spacing * CGFloat(cols - 1)
            let availH = geo.size.height - spacing * CGFloat(rows - 1)
            let fitted = floor(min(availW / CGFloat(cols), availH / CGFloat(rows)))
            let cellSide = max(Self.minCellSide, fitted)
            // Fits (side at/above floor): center the floored grid in the
            // offered rect — mirrors Sudoku BoardView's centered frame and
            // avoids the top-leading drift a ScrollView would impose (#278 CR).
            // Clamped (below floor, e.g. Expert on iPhone): the board exceeds
            // the rect, so scroll both axes instead of shrinking.
            if fitted >= Self.minCellSide {
                gridStack(rows: rows, cols: cols, cellSide: cellSide, spacing: spacing)
                    .frame(width: geo.size.width, height: geo.size.height, alignment: .center)
            } else {
                ScrollView([.horizontal, .vertical]) {
                    gridStack(rows: rows, cols: cols, cellSide: cellSide, spacing: spacing)
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
        }
        // Reserve a square-ish slot; the GR fills whatever it is offered.
        .aspectRatio(boardAspectRatio, contentMode: .fit)
    }

    private var boardAspectRatio: CGFloat {
        CGFloat(viewModel.columns) / CGFloat(viewModel.rows)
    }

    private func gridStack(rows: Int, cols: Int, cellSide: CGFloat, spacing: CGFloat) -> some View {
        VStack(spacing: spacing) {
            ForEach(0..<rows, id: \.self) { row in
                HStack(spacing: spacing) {
                    ForEach(0..<cols, id: \.self) { col in
                        MinesweeperCellButton(
                            cell: viewModel.cell(row: row, col: col),
                            side: cellSide,
                            mode: interactionMode,
                            onReveal: {
                                Task { await viewModel.reveal(row: row, col: col) }
                            },
                            onToggleFlag: {
                                Task { await viewModel.toggleFlag(row: row, col: col) }
                            }
                        )
                    }
                }
            }
        }
    }

    // MARK: - Overlay

    private var terminalOverlay: some View {
        VStack(spacing: 8) {
            Text(viewModel.status == .won ? "You won" : "Boom — you hit a mine")
                .font(.title2.weight(.semibold))
            Text("Elapsed: \(viewModel.elapsedSeconds)s")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - Interaction mode

/// Which action a cell *tap* performs. Long-press / right-click always flag,
/// regardless of mode (#278 Tier-0 #3).
enum InteractionMode: Hashable {
    case reveal
    case flag
}

// MARK: - Cell button

struct MinesweeperCellButton: View {
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
                .fill(Color.secondary.opacity(0.25))
        case .revealed:
            RoundedRectangle(cornerRadius: 4)
                .fill(cell.isMine ? Color.red.opacity(0.6) : Color.secondary.opacity(0.08))
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
                .foregroundStyle(.orange)
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
        switch count {
        case 1: return .blue
        case 2: return .green
        case 3: return .red
        case 4: return .purple
        case 5: return .brown
        case 6: return .teal
        case 7: return .black
        default: return .gray
        }
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

// MARK: - Preview

#Preview("Beginner 9x9") {
    MinesweeperBoardView(difficulty: .beginner, seed: 42)
        .frame(minWidth: 360, minHeight: 480)
}
