// GatewayEtagUpdateTests — issue #544: a save against an EXISTING record must
// UPDATE it (re-using the server's etag), not re-insert an etag-less copy.
//
// Regression for the live bug found via Console on a signed-in account: every
// move-save after the initial seed threw `serverRecordChanged`/.syncConflict,
// so the saved record stayed frozen at the empty seed → ResumePill always 0:00,
// resume opened a blank board. Root cause: the gateway round-tripped records
// through an etag-less `RecordPayload`, so the conflict-resolution retry could
// never produce a matching-etag payload.
//
// The `FakePrivateCKGateway` here runs with `setEnforceOptimisticConcurrency`,
// modelling CloudKit's optimistic concurrency: a save to an existing record
// must carry the current etag (`encodedSystemFields`) or it's rejected. Without
// the #544 fix (gateway preserves the etag through fetch, merge carries the
// server etag forward) the second save's retry resubmits an etag-less payload
// and exhausts the budget → throws. With the fix it lands.

import Foundation
import Testing
import GameState
import SudokuEngine
import Telemetry
import PersistenceTesting
@testable import Persistence

@Suite("Persistence — gateway etag update (issue #544)")
struct GatewayEtagUpdateTests {

    @Test func updatingExistingRecordPreservesMovesUnderEtagEnforcement() async throws {
        let gateway = FakePrivateCKGateway()
        await gateway.setEnforceOptimisticConcurrency(true)
        let telemetry = Telemetry(sinks: [])
        let puzzle = PuzzleFixtures.latinSquarePuzzle()
        let recordName = SavedGameStore.recordName(for: "p1", mode: .practice)

        // 1) Seed the record with the initial (empty) snapshot at T1.
        let store1 = SavedGameStore(
            gateway: gateway,
            telemetry: telemetry,
            puzzleLoader: { _ in puzzle },
            clock: { Date(timeIntervalSince1970: 1_000) }
        )
        let initial = await GameSession(puzzle: puzzle).snapshot()
        try await store1.save(initial, puzzleId: "p1", mode: .practice, difficulty: .easy)

        let seeded = try #require(try await gateway.fetch(recordName: recordName))
        let seededBoard = seeded.fields[SavedGameStore.Field.boardState]

        // 2) The player makes a move; persist their progress at T2 (> T1, so the
        //    resolver's newer-wins keeps the local move). With the bug this save
        //    THROWS .syncConflict (etag-less resubmit never matches); the fix
        //    makes it land.
        let session = GameSession(puzzle: puzzle)
        try await session.start()
        try await session.placeDigit(row: 0, col: 0, digit: 1)
        let progress = await session.snapshot()

        let store2 = SavedGameStore(
            gateway: gateway,
            telemetry: telemetry,
            puzzleLoader: { _ in puzzle },
            clock: { Date(timeIntervalSince1970: 2_000) }
        )
        try await store2.save(progress, puzzleId: "p1", mode: .practice, difficulty: .easy)

        // 3) The player's move must have overwritten the seeded board — the
        //    record was UPDATED, not frozen at the empty seed.
        let updated = try #require(try await gateway.fetch(recordName: recordName))
        #expect(
            updated.fields[SavedGameStore.Field.boardState] != seededBoard,
            "the player's move must persist over the seeded empty board"
        )
    }
}
