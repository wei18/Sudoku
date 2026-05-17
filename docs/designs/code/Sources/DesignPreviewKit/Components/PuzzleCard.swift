// DESIGN PREVIEW ONLY — docs/designs/code/Components/PuzzleCard.swift
//
// DailyHubView puzzle card. Source: docs/designs/03-daily-hub.md §c + §d.

import SwiftUI

public struct PuzzleCard: View {
    public let difficultyLabel: LocalizedStringKey
    /// `nil` ⇒ not yet played; otherwise formatted completion time.
    public let completedTime: String?

    public init(difficultyLabel: LocalizedStringKey, completedTime: String?) {
        self.difficultyLabel = difficultyLabel
        self.completedTime = completedTime
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(difficultyLabel)
                    .font(.title3.weight(.medium))
                    .foregroundStyle(DesignTokens.textPrimary)
                Spacer()
                if let t = completedTime {
                    Label(t, systemImage: "checkmark.circle.fill")
                        .font(.callout)
                        .foregroundStyle(DesignTokens.statusSuccess)
                } else {
                    Text("—")
                        .font(.callout)
                        .foregroundStyle(DesignTokens.textTertiary)
                }
            }
            MiniBoardStrip()
                .accessibilityHidden(true)
        }
        .padding(DesignTokens.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: DesignTokens.Radius.card))
        .accessibilityElement(children: .combine)
    }
}

/// Decorative 9-cell density hint strip below the card title.
public struct MiniBoardStrip: View {
    public init() {}
    public var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<9, id: \.self) { i in
                RoundedRectangle(cornerRadius: 2)
                    .fill(DesignTokens.textTertiary.opacity(i.isMultiple(of: 2) ? 0.18 : 0.08))
                    .frame(height: 8)
            }
        }
    }
}

#Preview("PuzzleCard — done / pending") {
    VStack(spacing: 12) {
        PuzzleCard(difficultyLabel: "Easy", completedTime: "4:11")
        PuzzleCard(difficultyLabel: "Medium", completedTime: nil)
    }
    .padding()
    .background(DesignTokens.surfaceBackground)
}
