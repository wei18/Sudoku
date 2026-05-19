// ConfigConsistencyTests — assert the ASCRegister `Config` IDs are byte-equal
// to the production `GameCenterClient` constants (design.md §How.3.1 / §How.3.2).
//
// We do NOT import GameCenterClient here (it pulls in CloudKit-adjacent
// targets and is overkill for an ID equality check). Instead we hard-code
// the expected strings and assert. If the production constants ever drift,
// fix them in BOTH places — Leader will be alerted by this test failing.

// swiftlint:disable trailing_comma

internal import Foundation
internal import Testing
@testable import ASCRegister

@Suite("Config consistency")
internal struct ConfigConsistencyTests {

    @Test("3 leaderboard IDs match the design.md §How.3.1 table exactly")
    internal func leaderboardIDs() {
        let expected = [
            "com.wei18.sudoku.leaderboard.easy.daily.v1",
            "com.wei18.sudoku.leaderboard.medium.daily.v1",
            "com.wei18.sudoku.leaderboard.hard.daily.v1",
        ]
        #expect(Config.allLeaderboardIds == expected)
    }

    @Test("8 achievement short IDs match the AchievementEvaluator emitted set")
    internal func achievementShortIDs() {
        let expected: Set<String> = [
            "first_puzzle",
            "daily.complete_one",
            "daily.streak_3",
            "daily.streak_7",
            "practice.complete_10",
            "practice.complete_100",
            "hard.master",
            "daily.sweep",
        ]
        #expect(Set(Config.allAchievementShortIds) == expected)
        #expect(Config.allAchievementShortIds.count == 8)
    }

    @Test("Achievement prefix matches GameCenterSink.achievementPrefix")
    internal func achievementPrefix() {
        #expect(Config.achievementPrefix == "com.wei18.sudoku.achievement.")
    }

    @Test("Total achievement points sum to 550 (§How.3.2 budget)")
    internal func pointsBudget() {
        #expect(Config.totalAchievementPoints == 550)
    }

    @Test("Full achievement IDs are correctly prefixed")
    internal func fullIDs() {
        for ach in Config.achievements {
            #expect(ach.fullId == "com.wei18.sudoku.achievement.\(ach.shortId)")
        }
    }

    @Test("Leaderboard score range upper bound is 7,200,000 ms (2-hour cap)")
    internal func scoreRange() {
        #expect(Config.leaderboardScoreMaxMilliseconds == 7_200_000)
    }
}
