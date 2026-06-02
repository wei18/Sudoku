// MinesweeperDailyHubViewTests — compile + smoke coverage for the U12
// Daily hub stub. Verifies the view instantiates with a binding and that
// the placeholder `MinesweeperDailyCard` shape exposes the difficulty +
// seed the shell needs for routing. Pure-data tests; no snapshot infra
// (deferred per X1-X4 precedent for MS UI).

import Foundation
import SwiftUI
import Testing
@testable import MinesweeperUI
import MinesweeperEngine

@MainActor
@Suite struct MinesweeperDailyHubViewTests {

    @Test func instantiatesWithBinding() {
        var path: [AppRoute] = []
        let binding = Binding<[AppRoute]>(
            get: { path },
            set: { path = $0 }
        )
        let view = MinesweeperDailyHubView(path: binding)
        _ = view
    }

    @Test func dailyCardCarriesDifficultyAndSeed() {
        let card = MinesweeperDailyCard(difficulty: .expert, seed: 42)
        #expect(card.difficulty == .expert)
        #expect(card.seed == 42)
        #expect(card.id == "expert-42")
    }

    @Test func instantiatesWithFixedDateForDeterministicPreview() {
        // Same calendar day always produces the same stub cards (the seed
        // map is a pure function of `ordinality(of: .day, in: .year, for:)`).
        // Compile-only check — proves the date-injection seam exists.
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let view = MinesweeperDailyHubView(path: .constant([]), date: date)
        _ = view
    }
}
