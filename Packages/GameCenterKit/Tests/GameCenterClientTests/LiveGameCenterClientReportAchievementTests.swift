// LiveGameCenterClientReportAchievementTests — asserts `reportAchievement`
// forwards the (identifier, percentComplete) pair to its injectable hook.
//
// The actual `GKAchievement.report(...)` wiring (#580) is a device-gated
// GameKit call exercised via `GKAchievementReporter.live`; this suite verifies
// the seam mapping without standing up GameKit (mirrors the submitScore
// centisecond-conversion suite).

import Foundation
import SudokuEngine
import Testing
@testable import GameCenterClient
import GameCenterTesting

@Suite("LiveGameCenterClient — reportAchievement hook forwarding")
struct LiveGameCenterClientReportAchievementTests {

    private actor ReportSpy {
        private(set) var calls: [(identifier: String, percent: Double)] = []
        func record(_ identifier: String, _ percent: Double) {
            calls.append((identifier, percent))
        }
    }

    private func makeClient(spy: ReportSpy) -> LiveGameCenterClient {
        let player = PlayerSummary(teamPlayerId: "PG1", displayName: "Wei")
        let driver = FakeAuthDriver(nextOutcome: .signedIn(player))
        return LiveGameCenterClient(
            authDriver: driver,
            reportAchievementHook: { identifier, percent in
                await spy.record(identifier, percent)
            }
        )
    }

    @Test func reportAchievementForwardsIdentifierAndPercentToHook() async throws {
        let spy = ReportSpy()
        let client = makeClient(spy: spy)
        try await client.reportAchievement(
            AchievementProgress(
                achievementId: "com.wei18.sudoku.achievement.first_puzzle",
                percentComplete: 100
            )
        )
        let calls = await spy.calls
        #expect(calls.count == 1)
        #expect(calls.first?.identifier == "com.wei18.sudoku.achievement.first_puzzle")
        #expect(calls.first?.percent == 100)
    }

    @Test func reportAchievementForwardsPartialProgress() async throws {
        let spy = ReportSpy()
        let client = makeClient(spy: spy)
        try await client.reportAchievement(
            AchievementProgress(
                achievementId: "com.wei18.sudoku.achievement.practice_complete_100",
                percentComplete: 42
            )
        )
        let calls = await spy.calls
        #expect(calls.first?.percent == 42)
    }
}
