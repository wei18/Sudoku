// BoardCellView — single 9×9 board cell.
//
// Per docs/designs/05-board.md. Five visual variants:
//   - empty / given / userFilled / error / selected
// Color-blind dual encoding for errors: bg tint + corner triangle.

import SwiftUI
import SudokuEngine

struct BoardCellView: View {
    let row: Int
    let column: Int
    let digit: Int?
    let isGiven: Bool
    let isSelected: Bool
    let isError: Bool
    let isPencilNotes: Bool
    let noteMask: UInt16
    let side: CGFloat

    @Environment(\.theme) private var theme
    @Environment(\.sudokuCell) private var cell

    var body: some View {
        ZStack {
            background
            content
            if isError {
                ErrorTriangle()
                    .fill(cell.errorBorder.resolved)
                    .frame(width: side * 0.18, height: side * 0.18)
                    .padding(2)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .accessibilityHidden(true)
            }
        }
        .frame(width: side, height: side)
        .overlay(borderOverlay)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }

    private var accessibilityLabel: String {
        // §How.5.7 format: "Row R, Column C, <state>"
        let location = "Row \(row + 1), Column \(column + 1)"
        if isError, let digit {
            return "\(location), conflict \(digit)"
        }
        if let digit {
            if isGiven {
                return "\(location), given \(digit)"
            }
            return "\(location), value \(digit)"
        }
        return "\(location), Empty"
    }

    @ViewBuilder
    private var background: some View {
        if isError {
            cell.error.resolved
        } else if isSelected {
            cell.selected.resolved
        } else if isGiven {
            cell.prefilled.resolved
        } else {
            cell.base.resolved
        }
    }

    @ViewBuilder
    private var content: some View {
        if let digit {
            Text("\(digit)")
                .font(.system(size: side * 0.6, weight: isGiven ? .semibold : .regular, design: .rounded))
                .foregroundStyle(digitColor)
                .monospacedDigit()
        } else if isPencilNotes, noteMask != 0 {
            PencilNotesGrid(mask: noteMask, side: side)
        } else {
            EmptyView()
        }
    }

    private var digitColor: Color {
        if isError {
            return theme.text.errorDigit.resolved
        }
        if isGiven {
            return theme.text.given.resolved
        }
        return theme.text.user.resolved
    }

    private var borderOverlay: some View {
        let thickRight = (column % 3 == 2) && column != 8
        let thickBottom = (row % 3 == 2) && row != 8
        return ZStack {
            Rectangle()
                .stroke(theme.text.tertiary.resolved.opacity(0.4), lineWidth: 0.5)
            if thickRight {
                HStack { Spacer(); Rectangle().fill(theme.text.primary.resolved).frame(width: 1.5) }
            }
            if thickBottom {
                VStack { Spacer(); Rectangle().fill(theme.text.primary.resolved).frame(height: 1.5) }
            }
        }
        .allowsHitTesting(false)
    }
}

private struct ErrorTriangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: rect.origin)
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

private struct PencilNotesGrid: View {
    let mask: UInt16
    let side: CGFloat
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<3, id: \.self) { row in
                HStack(spacing: 0) {
                    ForEach(0..<3, id: \.self) { col in
                        let digit = row * 3 + col + 1
                        let visible = (mask & (1 << digit)) != 0
                        Text(visible ? "\(digit)" : " ")
                            .font(.system(size: side * 0.22, design: .rounded))
                            .foregroundStyle(theme.text.tertiary.resolved)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
        }
        .padding(2)
    }
}
