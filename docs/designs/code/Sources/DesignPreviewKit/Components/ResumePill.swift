// DESIGN PREVIEW ONLY — docs/designs/code/Components/ResumePill.swift
//
// RootView "resume last game" affordance. Source: docs/designs/01-root.md §c.

import SwiftUI

public struct ResumePill: View {
    public let difficultyLabel: String
    public let elapsed: String

    public init(difficultyLabel: String, elapsed: String) {
        self.difficultyLabel = difficultyLabel
        self.elapsed = elapsed
    }

    public var body: some View {
        HStack {
            Image(systemName: "arrow.clockwise")
                .foregroundStyle(DesignTokens.accentPrimary)
            Text("Resume \(difficultyLabel) · \(elapsed)")
                .font(.body)
                .foregroundStyle(DesignTokens.textPrimary)
            Spacer()
            Image(systemName: "chevron.right")
                .foregroundStyle(DesignTokens.textTertiary)
        }
        .padding(DesignTokens.Spacing.md)
        .glassEffect(.regular, in: .rect(cornerRadius: DesignTokens.Radius.pill))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Resume \(difficultyLabel) puzzle, elapsed \(elapsed)")
        .accessibilityHint("Opens the board")
        .accessibilityAddTraits(.isButton)
    }
}

#Preview("ResumePill") {
    ResumePill(difficultyLabel: "Easy", elapsed: "3:21")
        .padding()
        .background(DesignTokens.surfaceBackground)
}
