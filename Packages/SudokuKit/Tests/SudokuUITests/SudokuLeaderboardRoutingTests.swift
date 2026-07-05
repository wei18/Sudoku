// SudokuLeaderboardRoutingTests — issue #381.
//
// The Completion screen previously hard-coded the daily-easy leaderboard for
// every solve (RouteFactory built every `CompletionViewModel` with
// `LeaderboardIDs.id(for: .dailyEasy)`). These tests pin the puzzleId →
// leaderboard mapping: each daily difficulty posts to its own board, and
// practice solves submit to no leaderboard (nil id).
//
// #698: renamed from `CompletionLeaderboardMappingTests` (was also
// exercising `CompletionViewModel.bootstrap()`/`.state`, the dead
// leaderboard-fetch machinery deleted in #698) — this file is now purely the
// `SudokuLeaderboardRouting.leaderboardId(forPuzzleId:)` mapping tests, which
// are unrelated to that deletion.

import Foundation
import Testing
import SudokuEngine
@testable import SudokuUI

@Suite("Completion — leaderboard id by puzzle difficulty (#381)")
struct SudokuLeaderboardRoutingTests {

    // MARK: - puzzleId → leaderboard id mapping

    @Test func dailyEasyMapsToEasyLeaderboard() {
        let id = SudokuLeaderboardRouting.leaderboardId(forPuzzleId: "2026-05-19-easy")
        #expect(id == LeaderboardID.dailyEasy)
    }

    @Test func dailyMediumMapsToMediumLeaderboard() {
        let id = SudokuLeaderboardRouting.leaderboardId(forPuzzleId: "2026-05-19-medium")
        #expect(id == LeaderboardID.dailyMedium)
    }

    @Test func dailyHardMapsToHardLeaderboard() {
        let id = SudokuLeaderboardRouting.leaderboardId(forPuzzleId: "2026-05-19-hard")
        #expect(id == LeaderboardID.dailyHard)
    }

    @Test func practicePuzzleMapsToNoLeaderboard() {
        let id = SudokuLeaderboardRouting.leaderboardId(forPuzzleId: "practice-7Z9K-medium")
        #expect(id == nil)
    }
}
