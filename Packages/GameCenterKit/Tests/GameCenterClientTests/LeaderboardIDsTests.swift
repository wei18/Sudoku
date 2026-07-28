import Foundation
import Testing
@testable import GameCenterClient

// #955: this file used to be SubmitScoreTests.swift, mixing SubmitGuards
// coverage with a single LeaderboardIDs assertion. SubmitGuards moved to
// SudokuAppComposition alongside GameCenterSink / AchievementEvaluator (see
// SudokuKit/Tests/SudokuAppCompositionTests/GameCenter/SubmitGuardsTests.swift);
// LeaderboardIDs stays in GameCenterKit (reachable from the protocol
// requirement — SudokuEngine.Difficulty → LeaderboardKind stays a
// GameCenterClient-level mapping), so its lone test stays here too.
@Suite("GameCenterClient — leaderboard IDs")
struct LeaderboardIDsTests {

    @Test func leaderboardIDSuffixedV1() {
        #expect(LeaderboardIDs.id(for: .dailyEasy)
                == "com.wei18.sudoku.leaderboard.easy.daily.v1")
        #expect(LeaderboardIDs.id(for: .dailyMedium)
                == "com.wei18.sudoku.leaderboard.medium.daily.v1")
        #expect(LeaderboardIDs.id(for: .dailyHard)
                == "com.wei18.sudoku.leaderboard.hard.daily.v1")
    }
}
