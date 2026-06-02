// NewGameViewTests — behavior coverage for the Standard navigation wire
// (2026-06-02 Track c.1).
//
// SwiftUI's NewGameView is not unit-testable as a rendered tree without
// snapshot infra (deferred per X1-X4 precedent). The route-building decision
// is extracted to `NewGameView.makeBoardRoute(difficulty:)` so it can be
// exercised directly. Pure `AppRoute` enum semantics moved to
// `AppRouteTests.swift`.

import SwiftUI
import Testing
@testable import MinesweeperUI
import MinesweeperEngine

@MainActor
@Suite struct NewGameViewTests {

    @Test func instantiatesWithBinding() {
        var path: [AppRoute] = []
        let binding = Binding<[AppRoute]>(
            get: { path },
            set: { path = $0 }
        )
        let view = NewGameView(path: binding, initialDifficulty: .intermediate)
        _ = view
    }

    @Test func makeBoardRouteCarriesSelectedDifficulty() {
        for difficulty in Difficulty.allCases {
            let route = NewGameView.makeBoardRoute(difficulty: difficulty)
            guard case .board(let routeDifficulty, _) = route else {
                Issue.record("expected .board case for \(difficulty)")
                continue
            }
            #expect(routeDifficulty == difficulty)
        }
    }

    @Test func makeBoardRouteGeneratesDifferentSeedsPerCall() {
        // Each call samples a fresh UInt64; collision probability per pair is
        // 1 / 2^64, so this is deterministic for any practical CI run.
        let first = NewGameView.makeBoardRoute(difficulty: .beginner)
        let second = NewGameView.makeBoardRoute(difficulty: .beginner)
        guard case .board(_, let seedA) = first, case .board(_, let seedB) = second else {
            Issue.record("expected .board cases")
            return
        }
        #expect(seedA != seedB)
    }
}
