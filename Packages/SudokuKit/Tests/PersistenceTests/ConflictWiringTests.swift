// ConflictWiringTests — issue #64: integration of ConflictResolver +
// RetryHarness into SavedGameStore / PersonalRecordStore save paths.
//
// The Fake gateway is scripted with `setConflictOnSaveTimes(_:recordName:)`
// to throw `.syncConflict` for the first N saves against a recordName;
// thereafter the save proceeds normally. This models CloudKit's
// `serverRecordChanged` for §How.6.7 wiring without coupling to a separate
// spy gateway.
//
// Budget per §How.6.7: 2 retries; the 3rd conflict throws
// `PersistenceError.syncConflict`.

import Foundation
import Testing
import GameState
import SudokuEngine
import Telemetry
import SudokuKitTesting
@testable import Persistence

@Suite("Persistence — conflict wiring (issue #64)")
struct ConflictWiringTests {

    // MARK: - SavedGameStore

    @Test func savedGameRetryHarnessRecoversWithinBudget() async throws {
        let gateway = FakePrivateCKGateway()
        let telemetry = Telemetry(sinks: [])
        let puzzle = PuzzleFixtures.latinSquarePuzzle()
        let store = SavedGameStore(
            gateway: gateway,
            telemetry: telemetry,
            puzzleLoader: { _ in puzzle },
            clock: { Date(timeIntervalSince1970: 1_000) }
        )
        let session = GameSession(puzzle: puzzle)
        try await session.start()
        try await session.placeDigit(row: 0, col: 0, digit: 1)
        let snapshot = await session.snapshot()

        let recordName = SavedGameStore.recordName(for: "p1", mode: .practice)
        // Script 2 conflicts; the 3rd save lands.
        await gateway.setConflictOnSaveTimes(2, recordName: recordName)

        try await store.save(
            snapshot,
            puzzleId: "p1",
            mode: .practice,
            difficulty: .easy
        )

        // Record is now persisted server-side.
        let stored = try await gateway.fetch(recordName: recordName)
        #expect(stored != nil, "save must succeed within the 2-retry budget")
    }

    @Test func savedGameExceedingRetryBudgetThrowsSyncConflict() async throws {
        let gateway = FakePrivateCKGateway()
        let telemetry = Telemetry(sinks: [])
        let puzzle = PuzzleFixtures.latinSquarePuzzle()
        let store = SavedGameStore(
            gateway: gateway,
            telemetry: telemetry,
            puzzleLoader: { _ in puzzle },
            clock: { Date(timeIntervalSince1970: 1_000) }
        )
        let snapshot = await GameSession(puzzle: puzzle).snapshot()

        let recordName = SavedGameStore.recordName(for: "p1", mode: .daily)
        // Script 3 conflicts → exhausts the 2-retry budget on the 3rd attempt.
        await gateway.setConflictOnSaveTimes(3, recordName: recordName)

        await #expect(throws: PersistenceError.syncConflict(recordName: recordName)) {
            try await store.save(
                snapshot,
                puzzleId: "p1",
                mode: .daily,
                difficulty: .easy
            )
        }
    }

    // MARK: - PersonalRecordStore

    @Test func personalRecordUpsertRetriesAfterConflict() async throws {
        let gateway = FakePrivateCKGateway()
        let store = PersonalRecordStore(
            gateway: gateway,
            clock: { Date(timeIntervalSince1970: 2_000) }
        )
        let recordName = PersonalRecordStore.recordName(mode: .daily, difficulty: .easy)
        let local = PersonalRecord(
            recordName: recordName,
            mode: .daily,
            difficulty: .easy,
            bestTimeSeconds: 60,
            totalTimeSeconds: 60,
            completedCount: 1,
            lastUpdatedAt: Date(timeIntervalSince1970: 2_000),
            completedPuzzleIds: ["p-local"]
        )
        await gateway.setConflictOnSaveTimes(2, recordName: recordName)

        try await store.upsert(local)

        let stored = try await gateway.fetch(recordName: recordName)
        #expect(stored != nil, "upsert must succeed within the 2-retry budget")
    }

    @Test func personalRecordUpsertExceedingBudgetThrows() async throws {
        let gateway = FakePrivateCKGateway()
        let store = PersonalRecordStore(
            gateway: gateway,
            clock: { Date(timeIntervalSince1970: 2_000) }
        )
        let recordName = PersonalRecordStore.recordName(mode: .practice, difficulty: .hard)
        let record = PersonalRecord(
            recordName: recordName,
            mode: .practice,
            difficulty: .hard,
            bestTimeSeconds: 100,
            totalTimeSeconds: 100,
            completedCount: 1,
            lastUpdatedAt: Date(timeIntervalSince1970: 2_000),
            completedPuzzleIds: ["p-1"]
        )
        await gateway.setConflictOnSaveTimes(3, recordName: recordName)

        await #expect(throws: PersistenceError.syncConflict(recordName: recordName)) {
            try await store.upsert(record)
        }
    }
}
