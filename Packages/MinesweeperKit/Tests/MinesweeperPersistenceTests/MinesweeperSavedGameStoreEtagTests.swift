// MinesweeperSavedGameStoreEtagTests — issue #544: a save against an EXISTING
// record must UPDATE it (read-modify-write carrying the server etag), not
// re-insert an etag-less copy. Under CloudKit optimistic concurrency (modelled
// by the etag-enforcing fake) the old bare re-insert threw `.syncConflict` and
// the record froze at its first write → resume lost progress.
//
// Split from MinesweeperSavedGameStoreTests to keep both files under the
// SwiftLint file_length ceiling (repo convention: extract, don't disable).

import Foundation
import Testing
import MinesweeperEngine
import MinesweeperGameState
import Persistence
import PersistenceTesting
@testable import MinesweeperPersistence

@Suite("MinesweeperSavedGameStore — etag update (issue #544)")
struct MinesweeperSavedGameStoreEtagTests {

    private static let fixedDate = Date(timeIntervalSince1970: 1_750_000_000)

    @Test
    func updatingExistingRecordLandsUnderEtagEnforcement() async throws {
        let gateway = FakePrivateCKGateway()
        await gateway.setEnforceOptimisticConcurrency(true)
        let store = MinesweeperSavedGameStore(gateway: gateway, clock: { Self.fixedDate })
        let recordName = "ms-etag-update"

        // Seed the record with an initial mid-play snapshot.
        let first = MinesweeperSession(difficulty: .beginner, seed: 5)
        _ = try await first.reveal(row: 4, col: 4)
        try await store.save(await first.snapshot(), modeRaw: "practice", recordName: recordName)

        // More progress → must UPDATE the existing record (not throw
        // .syncConflict, which is what the etag-less re-insert did before #544).
        let second = MinesweeperSession(difficulty: .beginner, seed: 5)
        _ = try await second.reveal(row: 4, col: 4)
        _ = try await second.reveal(row: 0, col: 0)
        let updated = await second.snapshot()
        try await store.save(updated, modeRaw: "practice", recordName: recordName)

        // The latest progress is what resumes — the record was not frozen.
        let loaded = try #require(try await store.loadInProgress(recordName: recordName))
        #expect(loaded == updated)
    }
}
