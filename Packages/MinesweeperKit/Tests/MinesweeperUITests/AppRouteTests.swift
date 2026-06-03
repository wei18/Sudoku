// AppRouteTests — pure enum semantics for Minesweeper's navigation route.
// Separated from `NewGameViewTests` so that file stays focused on the view's
// behavior (route building) rather than enum payload mechanics.

import Testing
import MinesweeperUI
import MinesweeperEngine

@Suite struct AppRouteTests {

    @Test func boardCarriesDifficultyAndSeed() {
        let route = AppRoute.board(difficulty: .expert, seed: 1234)
        guard case .board(let difficulty, let seed) = route else {
            Issue.record("expected .board case")
            return
        }
        #expect(difficulty == .expert)
        #expect(seed == 1234)
    }

    @Test func settingsIsDistinctFromBoard() {
        let settings = AppRoute.settings
        let board = AppRoute.board(difficulty: .beginner, seed: 0)
        #expect(settings != board)
    }

    @Test func boardEqualityUsesPayload() {
        let lhs = AppRoute.board(difficulty: .beginner, seed: 1)
        let rhs = AppRoute.board(difficulty: .beginner, seed: 1)
        let other = AppRoute.board(difficulty: .beginner, seed: 2)
        #expect(lhs == rhs)
        #expect(lhs != other)
    }

    // #288 / #289: the payload-free Home routes are distinct from each other
    // and from `.settings`.
    @Test func homeRoutesAreDistinct() {
        let routes: [AppRoute] = [.newGame, .daily, .practice, .settings]
        for (lhsIndex, lhs) in routes.enumerated() {
            for (rhsIndex, rhs) in routes.enumerated() where lhsIndex != rhsIndex {
                #expect(lhs != rhs)
            }
        }
    }

    @Test func sameCaseRoutesAreEqual() {
        #expect(AppRoute.newGame == .newGame)
        #expect(AppRoute.daily == .daily)
        #expect(AppRoute.practice == .practice)
    }
}
