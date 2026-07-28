import Foundation
import Testing
@testable import SudokuAppComposition

// #955: moved from GameCenterKit/Tests/GameCenterClientTests/SubmitScoreTests.swift
// (SubmitGuards moved to SudokuAppComposition alongside GameCenterSink /
// AchievementEvaluator). Assertions are unchanged — only the import moved
// from `@testable import GameCenterClient` to `@testable import SudokuAppComposition`.
// The lone LeaderboardIDs test from that file stays in GameCenterKit as
// `LeaderboardIDsTests.swift` (LeaderboardIDs did not move).
@Suite("SudokuAppComposition — submit guards")
struct SubmitGuardsTests {

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

    @Test func malformedPuzzleIdNotSubmitted() async {
        let guards = SubmitGuards(clock: { Date() })
        let allow = await guards.shouldSubmit(puzzleId: "garbage")
        #expect(allow == false)
    }
}
