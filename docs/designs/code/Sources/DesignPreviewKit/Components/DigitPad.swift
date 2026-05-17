// DESIGN PREVIEW ONLY — docs/designs/code/Components/DigitPad.swift
//
// BoardView numeric input row. Source: docs/designs/05-board.md §c digitPad.

import SwiftUI

public struct DigitPad: View {
    public var onDigit: (Int) -> Void
    public var onDelete: () -> Void

    public init(onDigit: @escaping (Int) -> Void = { _ in }, onDelete: @escaping () -> Void = {}) {
        self.onDigit = onDigit
        self.onDelete = onDelete
    }

    public var body: some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            ForEach(1...9, id: \.self) { d in
                Button("\(d)") { onDigit(d) }
                    .frame(minWidth: 36, minHeight: 44)
                    .buttonStyle(.bordered)
                    .foregroundStyle(DesignTokens.textPrimary)
            }
            Button(action: onDelete) {
                Image(systemName: "delete.left")
            }
            .frame(minWidth: 36, minHeight: 44)
            .buttonStyle(.bordered)
            .foregroundStyle(DesignTokens.textPrimary)
            .accessibilityLabel("Delete")
        }
    }
}

#Preview("DigitPad") {
    DigitPad()
        .padding()
        .background(DesignTokens.surfaceBackground)
}
