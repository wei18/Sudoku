// MinesweeperBoardView — MVP SwiftUI board renderer.
//
// Renders an `MinesweeperGameViewModel` as a row-major grid of cell buttons:
//   - Tap = reveal
//   - Long-press (iOS) / secondary click via context menu (macOS) = toggle flag
//
// Win/lose overlay is plain Text on a translucent backdrop — no animation,
// no haptics, no localization (English inline per dispatch spec).

public import SwiftUI
public import MinesweeperEngine
internal import MinesweeperGameState

public struct MinesweeperBoardView: View {

    @State private var viewModel: MinesweeperGameViewModel

    public init(viewModel: MinesweeperGameViewModel) {
        self._viewModel = State(initialValue: viewModel)
    }

    public init(difficulty: Difficulty = .beginner, seed: UInt64 = 0) {
        self._viewModel = State(initialValue: MinesweeperGameViewModel(difficulty: difficulty, seed: seed))
    }

    public var body: some View {
        VStack(spacing: 12) {
            statusBar
            boardGrid
                .overlay(alignment: .center) {
                    if viewModel.isTerminal {
                        terminalOverlay
                    }
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

    // MARK: - Grid

    private var boardGrid: some View {
        VStack(spacing: 2) {
            ForEach(0..<viewModel.rows, id: \.self) { row in
                HStack(spacing: 2) {
                    ForEach(0..<viewModel.columns, id: \.self) { col in
                        MinesweeperCellButton(
                            cell: viewModel.cell(row: row, col: col),
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

// MARK: - Cell button

struct MinesweeperCellButton: View {
    let cell: Cell
    let onReveal: () -> Void
    let onToggleFlag: () -> Void

    var body: some View {
        Button(action: onReveal) {
            ZStack {
                background
                content
            }
            .frame(width: 30, height: 30)
        }
        .buttonStyle(.plain)
        // Platform-gated flag gesture. On iOS we use long-press; on macOS
        // we use the context menu (right-click). Stacking both on iOS would
        // cause a single long-press to fire both handlers and double-toggle.
        #if os(iOS)
        .onLongPressGesture(minimumDuration: 0.35) {
            onToggleFlag()
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
                .foregroundStyle(.orange)
        case .revealed:
            if cell.isMine {
                Image(systemName: "burst.fill")
                    .foregroundStyle(.white)
            } else if cell.neighborMineCount > 0 {
                Text("\(cell.neighborMineCount)")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(numberColor(cell.neighborMineCount))
            } else {
                EmptyView()
            }
        }
    }

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
