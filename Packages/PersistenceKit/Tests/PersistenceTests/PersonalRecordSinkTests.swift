// PersonalRecordSinkTests — #578: PersonalRecordSink writes on completion.
//
// Uses a stateful spy PersistenceProtocol (not FakePersistence which is
// a no-op for personal records). The spy stores the last upserted record
// per (mode, difficulty) and returns it from fetchPersonalRecord so the
// sink's fetch→merge→upsert cycle is end-to-end exercised in-memory.

import Foundation
import Testing
import SudokuEngine
import SudokuGameState
import Telemetry
@testable import Persistence

// MARK: - Stateful spy

private actor SpyPersistence: PersistenceProtocol {

    // Stored records keyed by "mode-difficulty"
    private var records: [String: PersonalRecord] = [:]

    private func key(mode: Mode, difficulty: Difficulty) -> String {
        "\(mode.rawValue)-\(difficulty.rawValue)"
    }

    func fetchPersonalRecord(mode: Mode, difficulty: Difficulty) async throws -> PersonalRecord {
        let key = key(mode: mode, difficulty: difficulty)
        return records[key] ?? PersonalRecord.empty(
            mode: mode,
            difficulty: difficulty,
            at: Date(timeIntervalSince1970: 0)
        )
    }

    func upsertPersonalRecord(_ record: PersonalRecord) async throws {
        let key = key(mode: record.mode, difficulty: record.difficulty)
        records[key] = record
    }

    // Unused protocol requirements — no-op / minimal stubs

    func bootstrap() async throws {}
    func latestInProgress() async throws -> SavedGameSummary? { nil }
    func loadOrCreate(puzzleId: String, mode: Mode, difficulty: Difficulty) async throws -> GameSessionSnapshot {
        throw PersistenceError.zoneNotProvisioned
    }
    func save(_ snapshot: GameSessionSnapshot, puzzleId: String, mode: Mode, difficulty: Difficulty) async throws {}
    func markCompleted(_ summary: SavedGameSummary) async throws {}
    func deleteAbandoned(recordName: String) async throws {}
    func fetchCompletedDailyIds(for date: Date) async throws -> Set<String> { [] }
}

// MARK: - Tests

@Suite("PersonalRecordSink")
struct PersonalRecordSinkTests {

    private let fixedDate = Date(timeIntervalSince1970: 5_000)

    private func makeSink(persistence: any PersistenceProtocol) -> PersonalRecordSink {
        PersonalRecordSink(
            persistence: persistence,
            errorReporter: NoopErrorReporter(),
            clock: { [fixedDate] in fixedDate }
        )
    }

    @Test func puzzleCompletedWritesRecord() async throws {
        let persistence = SpyPersistence()
        let sink = makeSink(persistence: persistence)

        await sink.receive(.puzzleCompleted(
            puzzleId: "2026-06-20-easy",
            mode: .daily,
            difficulty: .easy,
            elapsedSeconds: 120,
            mistakeCount: 0
        ))

        let record = try await persistence.fetchPersonalRecord(mode: .daily, difficulty: .easy)
        #expect(record.completedCount == 1)
        #expect(record.bestTimeSeconds == 120)
        #expect(record.completedPuzzleIds == ["2026-06-20-easy"])
    }

    @Test func duplicateEventDoesNotDoubleCount() async throws {
        let persistence = SpyPersistence()
        let sink = makeSink(persistence: persistence)

        let event = TelemetryEvent.puzzleCompleted(
            puzzleId: "2026-06-20-easy",
            mode: .daily,
            difficulty: .easy,
            elapsedSeconds: 120,
            mistakeCount: 0
        )
        await sink.receive(event)
        await sink.receive(event)

        let record = try await persistence.fetchPersonalRecord(mode: .daily, difficulty: .easy)
        #expect(record.completedCount == 1)
    }

    @Test func nonCompletionEventIsNoOp() async throws {
        let persistence = SpyPersistence()
        let sink = makeSink(persistence: persistence)

        await sink.receive(.digitPlaced(row: 0, col: 0, digit: 5, previous: nil))

        let record = try await persistence.fetchPersonalRecord(mode: .daily, difficulty: .easy)
        #expect(record.completedCount == 0)
    }

    @Test func practiceCompletionRecordedUnderPractice() async throws {
        let persistence = SpyPersistence()
        let sink = makeSink(persistence: persistence)

        await sink.receive(.puzzleCompleted(
            puzzleId: "practice-uuid-1",
            mode: .practice,
            difficulty: .medium,
            elapsedSeconds: 300,
            mistakeCount: 2
        ))

        let practiceRecord = try await persistence.fetchPersonalRecord(mode: .practice, difficulty: .medium)
        let dailyRecord = try await persistence.fetchPersonalRecord(mode: .daily, difficulty: .medium)
        #expect(practiceRecord.completedCount == 1)
        #expect(practiceRecord.bestTimeSeconds == 300)
        #expect(dailyRecord.completedCount == 0)
    }
}
