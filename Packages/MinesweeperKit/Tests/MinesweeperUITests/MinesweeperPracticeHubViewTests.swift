// MinesweeperPracticeHubViewTests — compile + smoke coverage for the
// U12 Practice hub stub. Verifies the view instantiates with a binding +
// initial difficulty. Snapshot rendering deferred per X1-X4 precedent for
// MS UI; the wrapped `PracticeHubShellView` is independently pinned by
// `PracticeHubShellViewGenericityTests` in GameShellUITests.

import SwiftUI
import Testing
@testable import MinesweeperUI
import MinesweeperEngine

@MainActor
@Suite struct MinesweeperPracticeHubViewTests {

    @Test func instantiatesWithBinding() {
        var path: [AppRoute] = []
        let binding = Binding<[AppRoute]>(
            get: { path },
            set: { path = $0 }
        )
        let view = MinesweeperPracticeHubView(path: binding)
        _ = view
    }

    @Test func instantiatesWithEachDifficulty() {
        for difficulty in Difficulty.allCases {
            let view = MinesweeperPracticeHubView(
                path: .constant([]),
                initialDifficulty: difficulty
            )
            _ = view
        }
    }
}
