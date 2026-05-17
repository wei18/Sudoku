// DESIGN PREVIEW ONLY — docs/designs/code/Views/HomeView_Designs.swift
//
// Extracted from docs/designs/02-home.md §c. Refinements:
// - ModeCard extracted to Components/ModeCard.swift.
// - Background uses DesignTokens.surfaceBackground (not `.systemBackground`).

import SwiftUI

public struct HomeView_Designs: View {
    public enum Mode: String, CaseIterable, Identifiable {
        case daily, practice, leaderboard, settings
        public var id: String { rawValue }
        public var titleKey: LocalizedStringKey {
            switch self {
            case .daily: "Daily"
            case .practice: "Practice"
            case .leaderboard: "Leaderboard"
            case .settings: "Settings"
            }
        }
        public var subtitleKey: LocalizedStringKey {
            switch self {
            case .daily: "3 puzzles today"
            case .practice: "Mixed difficulty pool"
            case .leaderboard: "Global · friends"
            case .settings: "Account · language"
            }
        }
        public var symbol: String {
            switch self {
            case .daily: "calendar"
            case .practice: "dice"
            case .leaderboard: "trophy.fill"
            case .settings: "gear"
            }
        }
    }

    @Environment(\.horizontalSizeClass) private var hSize

    public init() {}

    public var body: some View {
        ScrollView {
            let columns = (hSize == .regular)
                ? [GridItem(.flexible()), GridItem(.flexible())]
                : [GridItem(.flexible())]
            LazyVGrid(columns: columns, spacing: DesignTokens.Spacing.md) {
                ForEach(Mode.allCases) { mode in
                    ModeCard(title: mode.titleKey, subtitle: mode.subtitleKey, symbol: mode.symbol)
                }
            }
            .padding(DesignTokens.Spacing.lg)
        }
        .navigationTitle("Sudoku")
        .background(DesignTokens.surfaceBackground)
    }
}

#Preview("Home — iPhone, light, en") {
    NavigationStack { HomeView_Designs() }
        .environment(\.locale, .init(identifier: "en"))
        .preferredColorScheme(.light)
}
