// DeferredSinkIntegrationTests — verifies that GameCenterSink reachable through
// a DeferredSink in a Telemetry fan-out fires both submitScore and
// reportAchievement when a .puzzleCompleted event flows through.
//
// Reproduces the live composition shape from MakeGameApp (phase 2):
//   Telemetry(sinks: [DeferredSink]) → setDownstream([GameCenterSink(...)])

import Foundation
import Testing
@testable import GameCenterClient
import Persistence
import SudokuGameState
import SudokuEngine
import Telemetry
import GameCenterTesting

@Suite("DeferredSink — Telemetry integration with GameCenterSink")
struct DeferredSinkIntegrationTests {

    private func utcDate(_ string: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        // swiftlint:disable:next force_unwrapping
        return formatter.date(from: string)!
    }

    @Test func puzzleCompletedThroughDeferredSinkFiresSubmitAndAchievements() async throws {
        let client = FakeGameCenterClient()
        let persistence = StubPersistenceForDeferred()
        let today = utcDate("2026-05-19T12:00:00Z")
        let player = PlayerSummary(teamPlayerId: "P1", displayName: "Wei")
        let guards = SubmitGuards(clock: { today })
        let evaluator = AchievementEvaluator(persistence: persistence)
        let gcSink = GameCenterSink(
            client: client,
            guards: guards,
            achievements: evaluator,
            authStateProvider: { .authenticated(player) },
            clock: { today }
        )

        // Build Telemetry with a DeferredSink, then late-bind GameCenterSink.
        let deferred = DeferredSink()
        let telemetry = Telemetry(sinks: [deferred])
        deferred.setDownstream([gcSink])

        // Fire completion event through the full Telemetry → DeferredSink → GCSink chain.
        await telemetry.observe(.puzzleCompleted(
            puzzleId: "2026-05-19-easy",
            mode: .daily,
            difficulty: .easy,
            elapsedSeconds: 180,
            mistakeCount: 0
        ))

        let ops = await client.operations
        let submitCount = ops.filter {
            if case .submitScore = $0 { return true }; return false
        }.count
        let achievementCount = ops.filter {
            if case .reportAchievement = $0 { return true }; return false
        }.count
        #expect(submitCount == 1, "daily completion should submit score once")
        #expect(achievementCount >= 2, "first_puzzle + daily.complete_one at minimum")
    }

    @Test func noDownstreamIsNoOp() async {
        let deferred = DeferredSink()
        let telemetry = Telemetry(sinks: [deferred])
        // No setDownstream — event flows through safely without crash.
        await telemetry.observe(.puzzleCompleted(
            puzzleId: "2026-05-19-easy",
            mode: .daily,
            difficulty: .easy,
            elapsedSeconds: 120,
            mistakeCount: 1
        ))
        // No assertions needed beyond "did not crash / deadlock".
    }
}

// MARK: - Stub (isolated to this file; mirrors the SinkTests pattern)

private actor StubPersistenceForDeferred: PersistenceProtocol {
    private var dailyIds: [String: Set<String>] = [:]

    func fetchCompletedDailyIds(for date: Date) async throws -> Set<String> {
        let key = UTCDay.string(from: date)
        return dailyIds[key] ?? []
    }

    func fetchPersonalRecord(mode: Mode, difficulty: Difficulty) async throws -> PersonalRecord {
        PersonalRecord(
            recordName: "\(mode.rawValue)-\(difficulty.rawValue)",
            mode: mode, difficulty: difficulty,
            bestTimeSeconds: nil, totalTimeSeconds: 0,
            completedCount: 0,
            lastUpdatedAt: Date(timeIntervalSince1970: 0),
            completedPuzzleIds: []
        )
    }

    func bootstrap() async throws {}
    func latestInProgress() async throws -> SavedGameSummary? { nil }
    func loadOrCreate(puzzleId: String, mode: Mode, difficulty: Difficulty) async throws -> GameSessionSnapshot {
        throw PersistenceError.zoneNotProvisioned
    }
    func save(
        _ snapshot: GameSessionSnapshot,
        puzzleId: String,
        mode: Mode,
        difficulty: Difficulty
    ) async throws {}
    func markCompleted(_ summary: SavedGameSummary) async throws {}
    func deleteAbandoned(recordName: String) async throws {}
    func upsertPersonalRecord(_ record: PersonalRecord) async throws {}
}
