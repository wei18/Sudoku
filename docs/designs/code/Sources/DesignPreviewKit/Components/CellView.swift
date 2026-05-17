// DESIGN PREVIEW ONLY — docs/designs/code/Components/CellView.swift
//
// A single Sudoku board cell, in all six documented states.
// Source: docs/designs/05-board.md §b.2 + §d.

import SwiftUI

public enum CellState: Equatable, Hashable {
    case empty
    case given(Int)
    case user(Int)
    case error(Int)
    case selected(Int?)
    case highlighted(Int?)
}

public struct CellView: View {
    public let state: CellState
    public let side: CGFloat

    public init(state: CellState, side: CGFloat) {
        self.state = state
        self.side = side
    }

    public var body: some View {
        ZStack {
            background
            content
        }
        .frame(width: side, height: side)
    }

    @ViewBuilder private var background: some View {
        switch state {
        case .empty:        DesignTokens.cellBase
        case .given:        DesignTokens.cellPrefilled
        case .user:         DesignTokens.cellBase
        case .error:        DesignTokens.cellError
        case .selected:     DesignTokens.cellSelected
        case .highlighted:  DesignTokens.cellHighlighted
        }
    }

    @ViewBuilder private var content: some View {
        let regular  = Font.system(size: side * 0.6, weight: .regular,  design: .rounded)
        let semibold = Font.system(size: side * 0.6, weight: .semibold, design: .rounded)
        switch state {
        case .empty, .highlighted(nil), .selected(nil):
            EmptyView()
        case .given(let d):
            Text("\(d)").font(semibold).foregroundStyle(DesignTokens.textGiven)
        case .user(let d), .selected(.some(let d)), .highlighted(.some(let d)):
            Text("\(d)").font(regular).foregroundStyle(DesignTokens.textUser)
        case .error(let d):
            ZStack(alignment: .topLeading) {
                Text("\(d)")
                    .font(regular)
                    .foregroundStyle(DesignTokens.textErrorDigit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                CornerTriangle()
                    .fill(DesignTokens.cellErrorBorder)
                    .frame(width: side * 0.18, height: side * 0.18)
                    .padding(2)
            }
        }
    }
}

public struct CornerTriangle: Shape {
    public init() {}
    public func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: r.origin)
        p.addLine(to: .init(x: r.maxX, y: r.minY))
        p.addLine(to: .init(x: r.minX, y: r.maxY))
        p.closeSubpath()
        return p
    }
}

#Preview("CellView — all states") {
    let side: CGFloat = 56
    return VStack(spacing: 8) {
        HStack(spacing: 8) {
            CellView(state: .empty, side: side)
            CellView(state: .given(5), side: side)
            CellView(state: .user(7), side: side)
        }
        HStack(spacing: 8) {
            CellView(state: .error(7), side: side)
            CellView(state: .selected(6), side: side)
            CellView(state: .highlighted(nil), side: side)
        }
    }
    .padding()
    .background(DesignTokens.surfaceBackground)
}
