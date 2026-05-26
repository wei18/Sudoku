import Foundation
import Testing
@testable import GameCenterClient
import Persistence
import GameState
import SudokuEngine
import Telemetry
import SudokuKitTesting

@Suite("GameCenterClient — sink")
struct GameCenterSinkTests {

    private func utcDate(_ string: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        // swiftlint:disable:next force_unwrapping
        return formatter.date(from: string)!
    }

    private func makeStack(
        authState: GameCenterAuthState
    ) -> (sink: GameCenterSink, client: FakeGameCenterClient, persistence: StubPersistence) {
        let client = FakeGameCenterClient()
        let persistence = StubPersistence()
        let today = utcDate("2026-05-19T12:00:00Z")
        let guards = SubmitGuards(clock: { today })
        let evaluator = AchievementEvaluator(persistence: persistence)
        let sink = GameCenterSink(
            client: client,
            guards: guards,
            achievements: evaluator,
            authStateProvider: { authState },
            clock: { today }
        )
        return (sink, client, persistence)
    }

    @Test func puzzleCompletedFanOutFiresSubmitAndAchievements() async throws {
        let player = PlayerSummary(teamPlayerId: "P1", displayName: "Wei")
        let stack = makeStack(authState: .authenticated(player))
        let event = TelemetryEvent.puzzleCompleted(
            puzzleId: "2026-05-19-easy",
            mode: .daily,
            difficulty: .easy,
            elapsedSeconds: 180
        )
        await stack.sink.receive(event)

        let ops = await stack.client.operations
        let submitCount = ops.filter {
            if case .submitScore = $0 { return true }; return false
        }.count
        let achievementCount = ops.filter {
            if case .reportAchievement = $0 { return true }; return false
        }.count
        #expect(submitCount == 1)
        #expect(achievementCount >= 2, "first_puzzle + daily.complete_one at minimum")
    }

    @Test func achievementIdsAreFullyPrefixed() async throws {
        let player = PlayerSummary(teamPlayerId: "P1", displayName: "Wei")
        let stack = makeStack(authState: .authenticated(player))
        await stack.sink.receive(.puzzleCompleted(
            puzzleId: "practice-AB-easy",
            mode: .practice,
            difficulty: .easy,
            elapsedSeconds: 200
        ))
        let ops = await stack.client.operations
        var sawPrefixed = false
        for case let .reportAchievement(id, _) in ops {
            #expect(id.hasPrefix("com.wei18.sudoku.achievement."), "got: \(id)")
            sawPrefixed = true
        }
        #expect(sawPrefixed)
    }

    @Test func unauthenticatedNoOp() async throws {
        let stack = makeStack(authState: .unauthenticated)
        await stack.sink.receive(.puzzleCompleted(
            puzzleId: "2026-05-19-easy",
            mode: .daily,
            difficulty: .easy,
            elapsedSeconds: 180
        ))
        let ops = await stack.client.operations
        #expect(ops.isEmpty, "no GC interactions when unauthenticated")
    }

    @Test func restrictedNoOp() async throws {
        let stack = makeStack(authState: .restricted)
        await stack.sink.receive(.puzzleCompleted(
            puzzleId: "2026-05-19-easy",
            mode: .daily,
            difficulty: .easy,
            elapsedSeconds: 180
        ))
        let ops = await stack.client.operations
        #expect(ops.isEmpty)
    }

    @Test func practiceEventTriggersAchievementsButNoSubmit() async throws {
        let player = PlayerSummary(teamPlayerId: "P1", displayName: "Wei")
        let stack = makeStack(authState: .authenticated(player))
        await stack.sink.receive(.puzzleCompleted(
            puzzleId: "practice-ZZ-medium",
            mode: .practice,
            difficulty: .medium,
            elapsedSeconds: 240
        ))
        let ops = await stack.client.operations
        let submitCount = ops.filter {
            if case .submitScore = $0 { return true }; return false
        }.count
        let achievementCount = ops.filter {
            if case .reportAchievement = $0 { return true }; return false
        }.count
        #expect(submitCount == 0)
        #expect(achievementCount >= 1, "first_puzzle still fires for practice")
    }

    @Test func nonCompletionEventIgnored() async throws {
        let player = PlayerSummary(teamPlayerId: "P1", displayName: "Wei")
        let stack = makeStack(authState: .authenticated(player))
        await stack.sink.receive(.sessionPaused)
        let ops = await stack.client.operations
        #expect(ops.isEmpty)
    }
}

// MARK: - Stub (duplicated from AchievementTests for module isolation;
// these test files are independent.)

private actor StubPersistence: PersistenceProtocol {
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
