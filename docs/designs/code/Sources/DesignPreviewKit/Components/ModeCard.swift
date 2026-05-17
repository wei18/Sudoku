// DESIGN PREVIEW ONLY — docs/designs/code/Components/ModeCard.swift
//
// HomeView mode card. Source: docs/designs/02-home.md §c + §d.

import SwiftUI

public struct ModeCard: View {
    public let title: LocalizedStringKey
    public let subtitle: LocalizedStringKey
    public let symbol: String

    public init(title: LocalizedStringKey, subtitle: LocalizedStringKey, symbol: String) {
        self.title = title
        self.subtitle = subtitle
        self.symbol = symbol
    }

    public var body: some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(DesignTokens.accentPrimary)
                .frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.title3.weight(.medium))
                    .foregroundStyle(DesignTokens.textPrimary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(DesignTokens.textSecondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .foregroundStyle(DesignTokens.textTertiary)
        }
        .padding(DesignTokens.Spacing.lg)
        .frame(minHeight: 72)
        .glassEffect(.regular, in: .rect(cornerRadius: DesignTokens.Radius.card))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

#Preview("ModeCard — light") {
    VStack(spacing: 12) {
        ModeCard(title: "Daily", subtitle: "3 puzzles today", symbol: "calendar")
        ModeCard(title: "Practice", subtitle: "Mixed difficulty pool", symbol: "dice")
    }
    .padding()
    .background(DesignTokens.surfaceBackground)
}
