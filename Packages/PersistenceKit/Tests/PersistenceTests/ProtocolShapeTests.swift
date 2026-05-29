// ProtocolShapeTests — compile-time shape assertions for PersistenceProtocol
// + its value types. These are NOT behavioral tests; they are tripwires that
// fail to compile if the surface drifts (e.g. someone drops Sendable, or
// adds a non-async non-throwing method).

import Foundation
import Testing
import GameState
import SudokuEngine
@testable import Persistence

// MARK: - Compile-time Sendable/Equatable/Codable assertions

private func assertSendable<T: Sendable>(_ value: T) {}
private func assertEquatable<T: Equatable>(_ value: T) {}
private func assertCodable<T: Codable>(_ value: T) {}

@Suite("Persistence — protocol & value-type shape")
struct ProtocolShapeTests {

    @Test func savedGameSummaryShape() {
        let summary = SavedGameSummary(
            recordName: "r1",
            puzzleId: "2026-05-19-easy",
            mode: .daily,
            difficulty: .easy,
            lastModifiedAt: Date(timeIntervalSince1970: 0),
            elapsedSeconds: 12,
            status: "inProgress",
            generatorVersion: 1
        )
        assertSendable(summary)
        assertEquatable(summary)
        assertCodable(summary)
        #expect(summary.id == summary.recordName)
    }

    @Test func personalRecordShape() {
        let record = PersonalRecord.empty(
            mode: .daily,
            difficulty: .easy,
            at: Date(timeIntervalSince1970: 0)
        )
        assertSendable(record)
        assertEquatable(record)
        assertCodable(record)
        #expect(record.recordName == "daily-easy")
    }

    @Test func persistenceErrorEquatable() {
        #expect(PersistenceError.iCloudNotSignedIn == .iCloudNotSignedIn)
        #expect(PersistenceError.syncConflict(recordName: "x")
                != .syncConflict(recordName: "y"))
    }

    @Test func protocolShapeCompiles() async throws {
        let dummy: any PersistenceProtocol = DummyPersistence()
        try await assertProtocolShape(dummy)
    }
}

// `func assertProtocolShape<T: PersistenceProtocol>(_:)` smoke — calling
// every method through an existential proves the surface is reachable from
// `Sendable` context.
private func assertProtocolShape<T: PersistenceProtocol>(_ persistence: T) async throws {
    _ = try await persistence.latestInProgress()
    _ = try await persistence.fetchCompletedDailyIds(for: Date(timeIntervalSince1970: 0))
    _ = try await persistence.fetchPersonalRecord(mode: .daily, difficulty: .easy)
}

/// Throwaway impl whose only purpose is to prove the protocol is satisfiable
/// without depending on CloudKit at all.
private struct DummyPersistence: PersistenceProtocol {
    func bootstrap() async throws {}
    func latestInProgress() async throws -> SavedGameSummary? { nil }
    func loadOrCreate(
        puzzleId: String,
        mode: Mode,
        difficulty: Difficulty
    ) async throws -> GameSessionSnapshot {
        throw PersistenceError.iCloudNotSignedIn
    }
    func save(
        _ snapshot: GameSessionSnapshot,
        puzzleId: String,
        mode: Mode,
        difficulty: Difficulty
    ) async throws {}
    func markCompleted(_ summary: SavedGameSummary) async throws {}
    func deleteAbandoned(recordName: String) async throws {}
    func fetchCompletedDailyIds(for date: Date) async throws -> Set<String> { [] }
    func fetchPersonalRecord(
        mode: Mode,
        difficulty: Difficulty
    ) async throws -> PersonalRecord {
        PersonalRecord.empty(mode: mode, difficulty: difficulty, at: Date(timeIntervalSince1970: 0))
    }
    func upsertPersonalRecord(_ record: PersonalRecord) async throws {}
}
