// MinesweeperSavedGameStore.fetchCompletedDailyIds (#816). Split from
// MinesweeperSavedGameStoreTests.swift purely for the 400-line file_length
// ceiling; same fixtures and philosophy.
//
// #816: MS's daily hub used to read completed ids via the generic
// Sudoku-shaped `PersistenceProtocol.fetchCompletedDailyIds`, whose CK
// predicate requires a `puzzleId` field MS's `SavedGame` schema doesn't
// have — the query always threw and the green check never appeared.
// `fetchCompletedDailyIds` mirrors the already-working `fetchFailedDailyIds`:
// query the queryable `status` field only, then filter mode/day client-side.

import Foundation
import Testing
import MinesweeperEngine
import MinesweeperGameState
import Persistence
import PersistenceTesting
@testable import MinesweeperPersistence

@Suite("MinesweeperSavedGameStore — fetchCompletedDailyIds (#816)")
struct MinesweeperSavedGameStoreCompletedDailyIdsTests {

    private static let fixedDate = Date(timeIntervalSince1970: 1_750_000_000)

    private func makeStore(_ gateway: FakePrivateCKGateway) -> MinesweeperSavedGameStore {
        MinesweeperSavedGameStore(gateway: gateway, clock: { Self.fixedDate })
    }

    private func midPlaySnapshot() async throws -> MinesweeperSessionSnapshot {
        let session = MinesweeperSession(difficulty: .beginner, seed: 42)
        _ = try await session.reveal(row: 4, col: 4)
        return await session.snapshot()
    }

    @Test
    func fetchCompletedDailyIdsReturnsCompletedDailyForToday() async throws {
        let gateway = FakePrivateCKGateway()
        let store = makeStore(gateway)
        let today = UTCDay.string(from: Self.fixedDate)
        let recordName = "daily-\(today)-beginner"
        let snapshot = try await midPlaySnapshot()

        try await store.save(snapshot, modeRaw: "daily", recordName: recordName)
        try await store.markCompleted(recordName: recordName)

        let completed = try await store.fetchCompletedDailyIds(for: Self.fixedDate)
        #expect(completed == [recordName])
    }

    @Test
    func fetchCompletedDailyIdsExcludesOtherDays() async throws {
        let gateway = FakePrivateCKGateway()
        let store = makeStore(gateway)
        let snapshot = try await midPlaySnapshot()
        let blob = try JSONEncoder().encode(snapshot)

        // Yesterday's completed daily: should NOT appear in today's results.
        let yesterday = "daily-2000-01-01-beginner"
        let yesterdayPayload = RecordPayload(
            recordType: "SavedGame",
            recordName: yesterday,
            fields: [
                "difficulty": .string("beginner"),
                "seed": .int(0),
                "mode": .string("daily"),
                "elapsedSeconds": .int(10),
                "status": .string("completed"),
                "lastModifiedAt": .date(Self.fixedDate),
                "schemaVersion": .int(1),
                "stateBlob": .data(blob),
            ]
        )
        await gateway.seed(yesterdayPayload)

        let completed = try await store.fetchCompletedDailyIds(for: Self.fixedDate)
        #expect(completed.isEmpty)
    }

    @Test
    func fetchCompletedDailyIdsExcludesPracticeCompletions() async throws {
        let gateway = FakePrivateCKGateway()
        let store = makeStore(gateway)
        let snapshot = try await midPlaySnapshot()

        try await store.save(snapshot, modeRaw: "practice", recordName: "practice-beginner")
        try await store.markCompleted(recordName: "practice-beginner")

        let completed = try await store.fetchCompletedDailyIds(for: Self.fixedDate)
        #expect(completed.isEmpty)
    }
}
