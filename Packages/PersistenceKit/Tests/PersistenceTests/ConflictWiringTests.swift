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
import PersistenceTesting
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

    // MARK: - Merge correctness (issue #64 N-3)

    /// Issue #64 Code Reviewer follow-up: existing tests assert retry count
    /// but not that the RESUBMITTED payload actually contains
    /// `ConflictResolver.resolve(local:server:)` output. This test seeds a
    /// server payload that is "newer + completed + larger elapsed" so every
    /// resolver rule fires in the server's favour, then verifies the
    /// gateway's persisted payload (i.e. the resubmitted record) matches
    /// the resolver's expected output per §How.6.7.
    @Test func savedGameMergePicksResolverOutputOnResubmit() async throws {
        let gateway = FakePrivateCKGateway()
        let telemetry = Telemetry(sinks: [])
        let puzzle = PuzzleFixtures.latinSquarePuzzle()
        // Local clock fixed in the past so the seeded server payload's
        // `lastModifiedAt` (future) is unambiguously newer per LWW.
        let localClock = Date(timeIntervalSince1970: 1_000)
        let serverModifiedAt = Date(timeIntervalSince1970: 2_000)
        let store = SavedGameStore(
            gateway: gateway,
            telemetry: telemetry,
            puzzleLoader: { _ in puzzle },
            clock: { localClock }
        )
        let session = GameSession(puzzle: puzzle)
        try await session.start()
        try await session.placeDigit(row: 0, col: 0, digit: 1)
        let snapshot = await session.snapshot()

        let recordName = SavedGameStore.recordName(for: "p1", mode: .practice)

        // Seed the server-side payload with values that should WIN every
        // resolver rule: newer lastModifiedAt, "completed" status, larger
        // elapsedSeconds, and a distinctive board/notes/undo group.
        let serverBoard = "SERVER_BOARD_GROUP_MARKER"
        let serverNotes = Data([0xAA, 0xBB, 0xCC])
        let serverUndo = Data([0x11, 0x22, 0x33])
        let seeded = RecordPayload(
            recordType: PrivateCKConstants.savedGameRecordType,
            recordName: recordName,
            fields: [
                SavedGameStore.Field.puzzleId: .string("p1"),
                SavedGameStore.Field.mode: .string(Mode.practice.rawValue),
                SavedGameStore.Field.difficulty: .string(Difficulty.easy.rawValue),
                SavedGameStore.Field.boardState: .string(serverBoard),
                SavedGameStore.Field.notesState: .data(serverNotes),
                SavedGameStore.Field.undoStack: .data(serverUndo),
                SavedGameStore.Field.startedAt: .date(localClock),
                SavedGameStore.Field.lastModifiedAt: .date(serverModifiedAt),
                SavedGameStore.Field.elapsedSeconds: .int(999),
                SavedGameStore.Field.status: .string("completed"),
                SavedGameStore.Field.generatorVersion: .int(1),
                SavedGameStore.Field.schemaVersion: .int(SavedGameStore.currentSchemaVersion),
            ]
        )
        await gateway.seed(seeded)
        // Script exactly 1 conflict so the retry loop runs the merge path
        // once and the 2nd attempt succeeds with the resolved payload.
        await gateway.setConflictOnSaveTimes(1, recordName: recordName)

        try await store.save(
            snapshot,
            puzzleId: "p1",
            mode: .practice,
            difficulty: .easy
        )

        let persisted = try #require(try await gateway.fetch(recordName: recordName))

        // boardState / notesState / undoStack — server's group must win
        // (LWW: server.lastModifiedAt > local clock).
        #expect(persisted.fields[SavedGameStore.Field.boardState] == .string(serverBoard))
        #expect(persisted.fields[SavedGameStore.Field.notesState] == .data(serverNotes))
        #expect(persisted.fields[SavedGameStore.Field.undoStack] == .data(serverUndo))
        // elapsedSeconds — max(local=0, server=999) = 999.
        #expect(persisted.fields[SavedGameStore.Field.elapsedSeconds] == .int(999))
        // status — "completed" always wins over the local snapshot's
        // "inProgress" regardless of timestamps.
        #expect(persisted.fields[SavedGameStore.Field.status] == .string("completed"))
        // NOTE: `lastModifiedAt` is intentionally NOT asserted here. The
        // resolver picks `max(local, server)` (= server's serverModifiedAt
        // for this fixture), but the retry loop in SavedGameStore.save
        // re-stamps `lastModifiedAt = clockRef()` at the top of every
        // attempt — including the post-merge resubmit. The persisted value
        // is therefore the local clock at the moment of the successful
        // resubmit attempt, not the resolver's max. This is by design:
        // each retry must advance the local-side LWW position so a future
        // conflict's tie-break favours the resolved (locally-canonical)
        // payload over any stale server copy. See `SavedGameStore.swift`
        // line ~185 comment.
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
