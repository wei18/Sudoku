// LiveGameCenterClientSubmitTests — asserts the seconds → centiseconds
// conversion at the GameKit submit boundary (design.md §How.3.1,
// `ELAPSED_TIME_CENTISECOND` ASC formatter / `mm:ss.SS` display).
//
// The actual `GKLeaderboard.submitScore(...)` wiring is a Phase 10 manual
// integration task; the conversion is exercised via `submitScoreHook`
// (see impl-notes 2026-05-20_submit-score-centisecond).

import Foundation
import SudokuEngine
import Testing
@testable import GameCenterClient
import SudokuKitTesting

@Suite("LiveGameCenterClient — submitScore centisecond conversion")
struct LiveGameCenterClientSubmitTests {

    /// Capture box for the hook's two arguments. Actor-isolated so the
    /// `@Sendable` hook can mutate it without crossing isolation domains.
    private actor SubmitSpy {
        private(set) var calls: [(leaderboardId: String, centiseconds: Int64)] = []
        func record(_ leaderboardId: String, _ centiseconds: Int64) {
            calls.append((leaderboardId, centiseconds))
        }
    }

    private func makeClient(spy: SubmitSpy) -> LiveGameCenterClient {
        let player = PlayerSummary(teamPlayerId: "PG1", displayName: "Wei")
        let driver = FakeAuthDriver(nextOutcome: .signedIn(player))
        return LiveGameCenterClient(
            authDriver: driver,
            submitScoreHook: { leaderboardId, centiseconds in
                await spy.record(leaderboardId, centiseconds)
            }
        )
    }

    // §How.3.1 worked example: 251s game (= 04:11.00) → 25100 cs.
    @Test func elapsedSecondsConvertsToCentiseconds() async throws {
        let spy = SubmitSpy()
        let client = makeClient(spy: spy)
        try await client.submitScore(
            puzzleId: "2026-05-19-easy",
            elapsedSeconds: 251,
            difficulty: .easy,
            leaderboardKind: .dailyEasy
        )
        let calls = await spy.calls
        #expect(calls.count == 1)
        #expect(calls.first?.centiseconds == 25_100)
        #expect(calls.first?.leaderboardId
                == "com.wei18.sudoku.leaderboard.easy.daily.v1")
    }

    // Zero edge: 0 s → 0 cs. Guards against any "× 100 + offset" drift.
    @Test func zeroElapsedSecondsConvertsToZero() async throws {
        let spy = SubmitSpy()
        let client = makeClient(spy: spy)
        try await client.submitScore(
            puzzleId: "2026-05-19-medium",
            elapsedSeconds: 0,
            difficulty: .medium,
            leaderboardKind: .dailyMedium
        )
        let calls = await spy.calls
        #expect(calls.first?.centiseconds == 0)
        #expect(calls.first?.leaderboardId
                == "com.wei18.sudoku.leaderboard.medium.daily.v1")
    }

    // 2-hour ceiling per design.md §How.3.1 (`1 ~ 720_000` valid range).
    // 7200 s → 720_000 cs — confirms `Int64` widening covers the max.
    @Test func twoHourCapMatchesDesignRange() async throws {
        let spy = SubmitSpy()
        let client = makeClient(spy: spy)
        try await client.submitScore(
            puzzleId: "2026-05-19-hard",
            elapsedSeconds: 7_200,
            difficulty: .hard,
            leaderboardKind: .dailyHard
        )
        let calls = await spy.calls
        #expect(calls.first?.centiseconds == 720_000)
        #expect(calls.first?.leaderboardId
                == "com.wei18.sudoku.leaderboard.hard.daily.v1")
    }
}
