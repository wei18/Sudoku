// DESIGN PREVIEW ONLY — docs/designs/code/Views/DailyHubView_Designs.swift
//
// Extracted from docs/designs/03-daily-hub.md §c. Refinements:
// - PuzzleCard + MiniBoardStrip extracted to Components/PuzzleCard.swift.
// - Tokens via DesignTokens.

import SwiftUI

public struct DailyHubView_Designs: View {
    public struct CardModel: Identifiable, Equatable {
        public let id: String
        public let difficultyLabel: String
        public let completedTime: String?
        public init(id: String, difficultyLabel: String, completedTime: String?) {
            self.id = id; self.difficultyLabel = difficultyLabel; self.completedTime = completedTime
        }
    }

    public enum State: Equatable {
        case loaded([CardModel])
        case loading
    }

    public static let demoNoneDone: [CardModel] = [
        .init(id: "easy", difficultyLabel: "Easy", completedTime: nil),
        .init(id: "medium", difficultyLabel: "Medium", completedTime: nil),
        .init(id: "hard", difficultyLabel: "Hard", completedTime: nil),
    ]
    public static let demoEasyDone: [CardModel] = [
        .init(id: "easy", difficultyLabel: "Easy", completedTime: "4:11"),
        .init(id: "medium", difficultyLabel: "Medium", completedTime: nil),
        .init(id: "hard", difficultyLabel: "Hard", completedTime: nil),
    ]
    public static let demoAllDone: [CardModel] = [
        .init(id: "easy", difficultyLabel: "Easy", completedTime: "4:11"),
        .init(id: "medium", difficultyLabel: "Medium", completedTime: "9:22"),
        .init(id: "hard", difficultyLabel: "Hard", completedTime: "17:05"),
    ]

    public var state: State
    @Environment(\.horizontalSizeClass) private var hSize

    public init(state: State = .loaded(DailyHubView_Designs.demoEasyDone)) {
        self.state = state
    }

    public var body: some View {
        Group {
            switch state {
            case .loaded(let cards): cardList(cards)
            case .loading: ProgressView().controlSize(.large)
            }
        }
        .navigationTitle(Text("Daily"))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DesignTokens.surfaceBackground)
    }

    @ViewBuilder
    private func cardList(_ cards: [CardModel]) -> some View {
        let cols: [GridItem] = (hSize == .regular)
            ? [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]
            : [GridItem(.flexible())]
        ScrollView {
            LazyVGrid(columns: cols, spacing: DesignTokens.Spacing.md) {
                ForEach(cards) { card in
                    PuzzleCard(
                        difficultyLabel: LocalizedStringKey(card.difficultyLabel),
                        completedTime: card.completedTime
                    )
                }
            }
            .padding(DesignTokens.Spacing.lg)
        }
    }
}

#Preview("DailyHub — iPhone, light, en (easy done)") {
    NavigationStack { DailyHubView_Designs() }
        .environment(\.locale, .init(identifier: "en"))
        .preferredColorScheme(.light)
}
