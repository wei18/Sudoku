// AppRouteTests — pure enum semantics for Minesweeper's navigation route.
// Separated from `NewGameViewTests` so that file stays focused on the view's
// behavior (route building) rather than enum payload mechanics.

import Testing
import MinesweeperUI
import MinesweeperEngine

@Suite struct AppRouteTests {

    @Test func boardCarriesDifficultyAndSeed() {
        let route = AppRoute.board(difficulty: .expert, seed: 1234, mode: .daily)
        guard case .board(let difficulty, let seed, let mode) = route else {
            Issue.record("expected .board case")
            return
        }
        #expect(difficulty == .expert)
        #expect(seed == 1234)
        #expect(mode == .daily)
    }

    @Test func settingsIsDistinctFromBoard() {
        let settings = AppRoute.settings
        let board = AppRoute.board(difficulty: .beginner, seed: 0, mode: .practice)
        #expect(settings != board)
    }

    @Test func boardEqualityUsesPayload() {
        let lhs = AppRoute.board(difficulty: .beginner, seed: 1, mode: .practice)
        let rhs = AppRoute.board(difficulty: .beginner, seed: 1, mode: .practice)
        let other = AppRoute.board(difficulty: .beginner, seed: 2, mode: .practice)
        #expect(lhs == rhs)
        #expect(lhs != other)
    }

    // #329: mode is part of the payload — same difficulty + seed but different
    // mode are distinct routes (a Practice board must not collide with a Daily
    // board in the navigation stack).
    @Test func boardEqualityDistinguishesMode() {
        let daily = AppRoute.board(difficulty: .beginner, seed: 1, mode: .daily)
        let practice = AppRoute.board(difficulty: .beginner, seed: 1, mode: .practice)
        #expect(daily != practice)
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
