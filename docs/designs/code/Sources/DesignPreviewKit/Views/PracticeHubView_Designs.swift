// DESIGN PREVIEW ONLY — docs/designs/code/Views/PracticeHubView_Designs.swift
//
// Extracted from docs/designs/04-practice-hub.md §c. Refinements:
// - Drawing-state card extracted to Components/ShimmerCard.swift.
// - Tokens via DesignTokens.

import SwiftUI

public struct PracticeHubView_Designs: View {
    public enum Difficulty: String, CaseIterable, Identifiable {
        case easy = "Easy", medium = "Medium", hard = "Hard", expert = "Expert"
        public var id: String { rawValue }
        public var shortKey: LocalizedStringKey { LocalizedStringKey(rawValue) }
    }

    public enum State: Equatable {
        case idle
        case drawn(puzzleId: String)
        case drawing
    }

    public var state: State
    @SwiftUI.State private var difficulty: Difficulty = .medium

    public init(state: State = .drawn(puzzleId: "24c8")) {
        self.state = state
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xl) {
            Text("Difficulty")
                .font(.title3.weight(.semibold))
                .foregroundStyle(DesignTokens.textPrimary)

            Picker("Difficulty", selection: $difficulty) {
                ForEach(Difficulty.allCases) { d in
                    Text(d.shortKey).tag(d)
                }
            }
            .pickerStyle(.segmented)
            .padding(DesignTokens.Spacing.sm)
            .glassEffect(.regular, in: .rect(cornerRadius: DesignTokens.Radius.chip))
            .tint(DesignTokens.accentPrimary)

            switch state {
            case .idle, .drawn:
                drawnCard
            case .drawing:
                ShimmerCard()
            }

            Spacer()
        }
        .padding(DesignTokens.Spacing.lg)
        .navigationTitle("Practice")
        .background(DesignTokens.surfaceBackground)
    }

    @ViewBuilder private var drawnCard: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            Text("Ready to play")
                .font(.headline)
                .foregroundStyle(DesignTokens.textPrimary)
            Text(idHint)
                .font(.caption)
                .foregroundStyle(DesignTokens.textSecondary)
            Button { } label: {
                Label("Draw new puzzle", systemImage: "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(DesignTokens.accentPrimary)
        }
        .padding(DesignTokens.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: DesignTokens.Radius.card))
    }

    private var idHint: String {
        switch state {
        case .drawn(let id): return "\(difficulty.rawValue) · puzzleId \(id)"
        default: return "\(difficulty.rawValue)"
        }
    }
}

#Preview("Practice — drawn") {
    NavigationStack { PracticeHubView_Designs(state: .drawn(puzzleId: "24c8")) }
        .preferredColorScheme(.light)
}
