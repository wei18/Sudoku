import Foundation
import Testing
@testable import GameCenterClient

@Suite("GameCenterClient — submit score guards")
struct SubmitScoreTests {

    private func utcDate(_ string: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        // swiftlint:disable:next force_unwrapping
        return formatter.date(from: string)!
    }

    @Test func practiceModeNeverSubmits() async {
        let guards = SubmitGuards(clock: { Date(timeIntervalSince1970: 0) })
        let allow = await guards.shouldSubmit(puzzleId: "practice-ABC123-easy")
        #expect(allow == false)
    }

    @Test func dailyFirstTimeSubmits() async {
        let today = utcDate("2026-05-19T12:00:00Z")
        let guards = SubmitGuards(clock: { today })
        let allow = await guards.shouldSubmit(puzzleId: "2026-05-19-easy")
        #expect(allow == true)
    }

    @Test func dailySecondTimeSkipped() async {
        let today = utcDate("2026-05-19T12:00:00Z")
        let guards = SubmitGuards(clock: { today })
        let first = await guards.shouldSubmit(puzzleId: "2026-05-19-easy")
        #expect(first == true)
        await guards.markSubmitted(puzzleId: "2026-05-19-easy")
        let second = await guards.shouldSubmit(puzzleId: "2026-05-19-easy")
        #expect(second == false)
    }

    @Test func crossDayCompletionSkipped() async {
        // Player started yesterday's puzzle, finished after UTC rollover.
        let now = utcDate("2026-05-19T00:30:00Z")
        let guards = SubmitGuards(clock: { now })
        let allow = await guards.shouldSubmit(puzzleId: "2026-05-18-hard")
        #expect(allow == false)
    }

    @Test func seededCompletedIdsBlockResubmission() async {
        let today = utcDate("2026-05-19T12:00:00Z")
        let guards = SubmitGuards(
            seedCompletedIds: ["2026-05-19-medium"],
            clock: { today }
        )
        let allow = await guards.shouldSubmit(puzzleId: "2026-05-19-medium")
        #expect(allow == false)
    }

    @Test func leaderboardIDSuffixedV1() {
        #expect(LeaderboardIDs.id(for: .dailyEasy)
                == "com.wei18.sudoku.leaderboard.easy.daily.v1")
        #expect(LeaderboardIDs.id(for: .dailyMedium)
                == "com.wei18.sudoku.leaderboard.medium.daily.v1")
        #expect(LeaderboardIDs.id(for: .dailyHard)
                == "com.wei18.sudoku.leaderboard.hard.daily.v1")
    }

    @Test func malformedPuzzleIdNotSubmitted() async {
        let guards = SubmitGuards(clock: { Date() })
        let allow = await guards.shouldSubmit(puzzleId: "garbage")
        #expect(allow == false)
    }
}
