// RecordPuzzleCompletionTests — #552 §D.9: recordPuzzleCompletion facade method.
//
// The DEFAULT extension impl on PersistenceProtocol should go through
// fetchPersonalRecord → recordingCompletion → upsertPersonalRecord.
// LivePersistence OVERRIDES it to call personalRecordStore().recordCompletion(...)
// (the optimistic retry path). This test exercises the default impl path
// via a spy, and verifies the LivePersistence override wiring compiles.

import Foundation
import Testing
import SudokuEngine
import SudokuGameState
import Telemetry
@testable import Persistence

@Suite("recordPuzzleCompletion — facade default impl")
struct RecordPuzzleCompletionTests {

    @Test func defaultImplRecordsThroughFetchAndUpsert() async throws {
        let spy = SpyPersistenceForCompletion()

        // Call the default impl
        try await spy.recordPuzzleCompletion(
            puzzleId: "2026-06-21-easy",
            mode: .daily,
            difficulty: .easy,
            elapsedSeconds: 150
        )

        let record = try await spy.fetchPersonalRecord(mode: .daily, difficulty: .easy)
        #expect(record.completedCount == 1)
        #expect(record.bestTimeSeconds == 150)
        #expect(record.completedPuzzleIds == ["2026-06-21-easy"])
    }

    @Test func defaultImplDedupsSamePuzzleId() async throws {
        let spy = SpyPersistenceForCompletion()

        try await spy.recordPuzzleCompletion(
            puzzleId: "p1",
            mode: .daily,
            difficulty: .easy,
            elapsedSeconds: 100
        )
        try await spy.recordPuzzleCompletion(
            puzzleId: "p1",
            mode: .daily,
            difficulty: .easy,
            elapsedSeconds: 90
        )

        let record = try await spy.fetchPersonalRecord(mode: .daily, difficulty: .easy)
        #expect(record.completedCount == 1) // not double-counted
        #expect(record.bestTimeSeconds == 100)
    }
}

// MARK: - Spy

private actor SpyPersistenceForCompletion: PersistenceProtocol {
    private var records: [String: PersonalRecord] = [:]

    private func key(mode: Mode, difficulty: Difficulty) -> String {
        "\(mode.rawValue)-\(difficulty.rawValue)"
    }

    func fetchPersonalRecord(mode: Mode, difficulty: Difficulty) async throws -> PersonalRecord {
        let key = key(mode: mode, difficulty: difficulty)
        return records[key] ?? PersonalRecord.empty(mode: mode, difficulty: difficulty, at: Date(timeIntervalSince1970: 0))
    }

    func upsertPersonalRecord(_ record: PersonalRecord) async throws {
        records[key(mode: record.mode, difficulty: record.difficulty)] = record
    }

    // PersistenceProtocol stubs
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
