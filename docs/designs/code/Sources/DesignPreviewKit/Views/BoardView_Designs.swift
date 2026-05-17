// DESIGN PREVIEW ONLY — docs/designs/code/Views/BoardView_Designs.swift
//
// Extracted from docs/designs/05-board.md §c. Refinements:
// - CellView extracted to Components/CellView.swift; uses DesignTokens.
// - DigitPad extracted to Components/DigitPad.swift.
// - Board background uses DesignTokens.surfaceBackground (board is flat per §How.5.1).
// - Public seed accepts a 9x9 [[CellState]] so the snapshot target can supply
//   the 3 documented variants (empty / in-progress-with-errors / about-to-complete).

import SwiftUI

public struct BoardView_Designs: View {
    public typealias Board = [[CellState]]

    public let board: Board
    public let difficultyLabel: LocalizedStringKey
    public let timer: String
    public let isPaused: Bool

    @State private var pencil = false
    @FocusState private var focused: Bool
    @Environment(\.horizontalSizeClass) private var hSize

    public init(
        board: Board = BoardView_Designs.demoInProgressWithErrors,
        difficultyLabel: LocalizedStringKey = "Medium",
        timer: String = "3:21",
        isPaused: Bool = false
    ) {
        self.board = board
        self.difficultyLabel = difficultyLabel
        self.timer = timer
        self.isPaused = isPaused
    }

    public var body: some View {
        VStack(spacing: DesignTokens.Spacing.lg) {
            header
            boardView
            controls
            DigitPad()
        }
        .padding(DesignTokens.Spacing.lg)
        .background(DesignTokens.surfaceBackground)
        .overlay { if isPaused { pauseOverlay } }
        .focusable(hSize == .regular)
        .focused($focused)
        .onKeyPress(phases: .down) { _ in .handled }
    }

    private var header: some View {
        HStack {
            Text(difficultyLabel)
                .font(.headline)
                .foregroundStyle(DesignTokens.textPrimary)
            Spacer()
            Label(timer, systemImage: "timer")
                .monospacedDigit()
                .foregroundStyle(DesignTokens.textSecondary)
            Button { } label: {
                Image(systemName: "pause.fill")
                    .foregroundStyle(DesignTokens.accentPrimary)
            }
            if hSize == .regular {
                Menu {
                    Button("Undo") { }.keyboardShortcut("z", modifiers: .command)
                    Button("Redo") { }.keyboardShortcut("z", modifiers: [.command, .shift])
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
    }

    private var boardView: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let cell = side / 9
            VStack(spacing: 0) {
                ForEach(0..<9, id: \.self) { r in
                    HStack(spacing: 0) {
                        ForEach(0..<9, id: \.self) { c in
                            CellView(state: board[r][c], side: cell)
                                .overlay(borderOverlay(row: r, col: c))
                        }
                    }
                }
            }
            .frame(width: side, height: side)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private func borderOverlay(row: Int, col: Int) -> some View {
        let thickRight = (col % 3 == 2) && col != 8
        let thickBottom = (row % 3 == 2) && row != 8
        return ZStack {
            Rectangle()
                .stroke(DesignTokens.textSecondary.opacity(0.3), lineWidth: 0.5)
            if thickRight {
                HStack {
                    Spacer()
                    Rectangle().fill(DesignTokens.textPrimary).frame(width: 1.5)
                }
            }
            if thickBottom {
                VStack {
                    Spacer()
                    Rectangle().fill(DesignTokens.textPrimary).frame(height: 1.5)
                }
            }
        }
    }

    private var controls: some View {
        HStack(spacing: DesignTokens.Spacing.xl) {
            Button { } label: { Image(systemName: "arrow.uturn.backward") }
            Button { } label: { Image(systemName: "arrow.uturn.forward") }
            Toggle(isOn: $pencil) {
                Image(systemName: pencil ? "pencil" : "pencil.slash")
            }
            .toggleStyle(.button)
            .tint(DesignTokens.accentPrimary)
        }
        .font(.title2)
        .foregroundStyle(DesignTokens.textPrimary)
    }

    private var pauseOverlay: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial)
            VStack(spacing: DesignTokens.Spacing.md) {
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(DesignTokens.accentPrimary)
                Text("Tap to resume")
                    .font(.title3.weight(.medium))
                    .foregroundStyle(DesignTokens.textPrimary)
            }
        }
    }

    // MARK: - Demo boards (replace BoardStub from the source .md).

    public static let demoEmpty: Board = Array(
        repeating: Array(repeating: CellState.empty, count: 9),
        count: 9
    )

    public static let demoInProgressWithErrors: Board = {
        var rows: Board = Array(repeating: Array(repeating: .empty, count: 9), count: 9)
        rows[0][0] = .given(5); rows[0][4] = .given(8); rows[0][8] = .given(2)
        rows[1][1] = .given(3); rows[1][5] = .user(9)
        rows[2][2] = .given(6); rows[2][6] = .user(4)
        rows[3][3] = .given(1)
        rows[4][0] = .highlighted(nil); rows[4][1] = .highlighted(nil)
        rows[4][2] = .error(6)
        rows[4][3] = .highlighted(nil); rows[4][4] = .selected(6)
        rows[4][5] = .highlighted(nil); rows[4][6] = .highlighted(nil)
        rows[4][7] = .highlighted(nil); rows[4][8] = .highlighted(nil)
        rows[5][5] = .given(7)
        rows[6][2] = .given(4); rows[6][6] = .user(2)
        rows[7][7] = .given(5)
        rows[8][0] = .user(8); rows[8][4] = .given(3); rows[8][8] = .given(9)
        return rows
    }()

    public static let demoAboutToComplete: Board = {
        var rows: Board = Array(repeating: Array(repeating: .empty, count: 9), count: 9)
        // Fill almost everything as `.given` / `.user`; one empty cell remains.
        for r in 0..<9 {
            for c in 0..<9 {
                let v = ((r * 3 + r / 3 + c) % 9) + 1
                rows[r][c] = (r + c).isMultiple(of: 2) ? .given(v) : .user(v)
            }
        }
        rows[4][4] = .selected(nil) // The last empty cell, currently selected.
        return rows
    }()
}

#Preview("Board — in progress, light, en") {
    BoardView_Designs()
        .environment(\.locale, .init(identifier: "en"))
        .preferredColorScheme(.light)
}
