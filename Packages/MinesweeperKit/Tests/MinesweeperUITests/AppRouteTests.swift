// AppRouteTests — pure enum semantics for Minesweeper's navigation route
// (payload mechanics: distinctness + equality of route cases).

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
        let routes: [AppRoute] = [.daily, .practice, .settings]
        for (lhsIndex, lhs) in routes.enumerated() {
            for (rhsIndex, rhs) in routes.enumerated() where lhsIndex != rhsIndex {
                #expect(lhs != rhs)
            }
        }
    }

    @Test func sameCaseRoutesAreEqual() {
        #expect(AppRoute.daily == .daily)
        #expect(AppRoute.practice == .practice)
    }

    // #386: the solved-daily re-view route carries difficulty + mode (no seed /
    // elapsed — MS has no stored snapshot). Payload drives equality, and it is
    // distinct from a `.board` with the same difficulty.
    @Test func completionCarriesDifficultyAndMode() {
        let route = AppRoute.completion(difficulty: .intermediate, mode: .daily)
        guard case .completion(let difficulty, let mode) = route else {
            Issue.record("expected .completion case")
            return
        }
        #expect(difficulty == .intermediate)
        #expect(mode == .daily)
    }

    @Test func completionIsDistinctFromBoard() {
        let completion = AppRoute.completion(difficulty: .beginner, mode: .daily)
        let board = AppRoute.board(difficulty: .beginner, seed: 0, mode: .daily)
        #expect(completion != board)
    }

    @Test func completionEqualityUsesPayload() {
        let lhs = AppRoute.completion(difficulty: .expert, mode: .daily)
        let rhs = AppRoute.completion(difficulty: .expert, mode: .daily)
        let other = AppRoute.completion(difficulty: .beginner, mode: .daily)
        #expect(lhs == rhs)
        #expect(lhs != other)
    }

    // Epic 8 (SDD-003): .replayDailyBoard carries difficulty + seed and is
    // distinct from a scored .board with the same payload.
    @Test func replayDailyBoardCarriesDifficultyAndSeed() {
        let route = AppRoute.replayDailyBoard(difficulty: .beginner, seed: 42)
        guard case .replayDailyBoard(let difficulty, let seed) = route else {
            Issue.record("expected .replayDailyBoard case")
            return
        }
        #expect(difficulty == .beginner)
        #expect(seed == 42)
    }

    @Test func replayDailyBoardIsDistinctFromScoredBoard() {
        let replay = AppRoute.replayDailyBoard(difficulty: .beginner, seed: 42)
        let scored = AppRoute.board(difficulty: .beginner, seed: 42, mode: .daily)
        #expect(replay != scored)
    }
}
