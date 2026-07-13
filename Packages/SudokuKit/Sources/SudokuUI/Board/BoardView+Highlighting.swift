// BoardView+Highlighting — cell(row:column:side:) with peer + same-digit tinting.
// bg priority: error > selected > sameDigit > highlighted (peer) > given > base

import SwiftUI
import SudokuEngine

extension BoardView {
    @ViewBuilder
    func cell(row: Int, column: Int, side: CGFloat) -> some View {
        let index = Board.index(row: row, column: column)
        let digit = viewModel.board.digit(atIndex: index)
        let isGiven = viewModel.board.givenMask[index]
        let sel = viewModel.selection
        let isSelected = sel.map { $0.row == row && $0.column == column } ?? false
        let isError = viewModel.errorIndices.contains(index)
        let noteMask = viewModel.notes.masks[index]
        // Peer highlight: shares row, column, or 3×3 box with the selected cell.
        let isHighlighted = !isSelected && sel.map { sel2 in
            sel2.row == row || sel2.column == column
                || (sel2.row / 3 == row / 3 && sel2.column / 3 == column / 3)
        } ?? false
        // Same-digit: non-selected cell carrying the digit shown in the selected
        // cell, OR (#722) the digit armed for digit-first placement — the two
        // sources are mutually exclusive (armedDigit != nil ⟺ selection == nil),
        // so reading whichever is active reuses the existing token unchanged.
        let selDig = sel.flatMap { viewModel.board.digit(atIndex: Board.index(row: $0.row, column: $0.column)) }
        let targetDigit = selDig ?? viewModel.armedDigit
        let isSameDigit = !isSelected && targetDigit != nil && digit == targetDigit
        let cellView = BoardCellView(
            row: row,
            column: column,
            digit: digit,
            isGiven: isGiven,
            isSelected: isSelected,
            isError: isError,
            isHighlighted: isHighlighted,
            isSameDigit: isSameDigit,
            isPencilNotes: digit == nil,
            noteMask: noteMask,
            side: side,
            armedDigit: viewModel.armedDigit
        )
        if cellView.isInteractive {
            Button {
                // #722: routes through the digit-first dispatch — degrades to
                // plain select() when nothing is armed, so cell-first is unchanged.
                Task { await viewModel.tapCell(row: row, column: column) }
            } label: {
                cellView
            }
            .buttonStyle(.plain)
        } else {
            // #473: given (clue) cells are non-interactive — no Button wrapper,
            // so VoiceOver announces them as static text (a given's `select()` is
            // already a no-op, #472). Arrow-key navigation still highlights them.
            cellView
        }
    }
}
