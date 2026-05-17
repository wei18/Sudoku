// DESIGN PREVIEW ONLY — docs/designs/code/Components/ShimmerCard.swift
//
// PracticeHubView "drawing" state card with SwiftUI `.redacted` shimmer.
// Source: docs/designs/04-practice-hub.md §b.2 + §c (state: .drawing).

import SwiftUI

public struct ShimmerCard: View {
    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            Text("Ready to play")
                .font(.headline)
                .foregroundStyle(DesignTokens.textPrimary)
            Text("placeholder placeholder placeholder")
                .font(.caption)
                .redacted(reason: .placeholder)
                .accessibilityLabel("Loading")
                .accessibilityAddTraits(.updatesFrequently)
            Button { } label: {
                Label("Draw new puzzle", systemImage: "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(DesignTokens.accentPrimary)
            .disabled(true)
        }
        .padding(DesignTokens.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: DesignTokens.Radius.card))
    }
}

#Preview("ShimmerCard") {
    ShimmerCard()
        .padding()
        .background(DesignTokens.surfaceBackground)
}
