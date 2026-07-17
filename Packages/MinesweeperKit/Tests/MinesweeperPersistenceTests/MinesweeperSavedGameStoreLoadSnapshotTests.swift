// MinesweeperSavedGameStore — status-agnostic snapshot recovery (#841).
// Split from MinesweeperSavedGameStoreTests.swift purely for the 400-line
// file_length ceiling — same fixtures and philosophy.
//
// `loadSnapshot(recordName:)` exists specifically so the daily-replay loader
// can recover a "failed" daily's persisted mine layout — a status
// `loadInProgress` deliberately treats as "not resumable" and hides.

import Foundation
import Testing
import MinesweeperEngine
import MinesweeperGameState
import Persistence
import PersistenceTesting
@testable import MinesweeperPersistence

@Suite("MinesweeperSavedGameStore — loadSnapshot ignores status (#841)")
struct MinesweeperSavedGameStoreLoadSnapshotTests {

    private static let fixedDate = Date(timeIntervalSince1970: 1_750_000_000)

    private func makeStore(_ gateway: FakePrivateCKGateway) -> MinesweeperSavedGameStore {
        MinesweeperSavedGameStore(gateway: gateway, clock: { Self.fixedDate })
    }

    private func snapshot(status: MinesweeperSessionStatus, seed: UInt64 = 42) async throws -> MinesweeperSessionSnapshot {
        let session = MinesweeperSession(difficulty: .beginner, seed: seed)
        let live = try await session.reveal(row: 4, col: 4)
        return MinesweeperSessionSnapshot(
            difficulty: live.difficulty,
            seed: live.seed,
            cells: live.cells,
            status: status,
            elapsedSeconds: live.elapsedSeconds,
            mineCount: live.mineCount,
            flagCount: live.flagCount
        )
    }

    /// The #841 contract `loadInProgress` cannot serve: a "failed" record
    /// (the daily's own terminal-loss save) IS readable via `loadSnapshot`,
    /// carrying the full mine layout the replay loader needs.
    @Test
    func loadsAFailedRecordThatLoadInProgressWouldHide() async throws {
        let gateway = FakePrivateCKGateway()
        let store = makeStore(gateway)
        let lost = try await snapshot(status: .lost)

        try await store.save(lost, modeRaw: "daily", recordName: "daily-2026-07-17-beginner")

        #expect(try await store.loadInProgress(recordName: "daily-2026-07-17-beginner") == nil)
        let loaded = try await store.loadSnapshot(recordName: "daily-2026-07-17-beginner")
        #expect(loaded == lost)
        #expect(loaded?.mineIndices == lost.mineIndices)
    }

    /// A genuinely resumable in-progress record is ALSO readable through the
    /// status-agnostic path (loadSnapshot is a superset, not an alternate).
    @Test
    func loadsAnInProgressRecordToo() async throws {
        let gateway = FakePrivateCKGateway()
        let store = makeStore(gateway)
        let inProgress = try await snapshot(status: .playing)
        try await store.save(inProgress, modeRaw: "practice", recordName: "practice-beginner")

        let loaded = try await store.loadSnapshot(recordName: "practice-beginner")
        #expect(loaded == inProgress)
    }

    @Test
    func returnsNilForAMissingRecord() async throws {
        let store = makeStore(FakePrivateCKGateway())
        #expect(try await store.loadSnapshot(recordName: "does-not-exist") == nil)
    }

    @Test
    func throwsOnNewerSchemaVersionSameAsLoadInProgress() async throws {
        let gateway = FakePrivateCKGateway()
        let store = makeStore(gateway)
        let lost = try await snapshot(status: .lost)
        try await store.save(lost, modeRaw: "daily", recordName: "future-failed")

        var payload = try #require(await gateway.fetch(recordName: "future-failed"))
        payload.fields["schemaVersion"] = .int(MinesweeperSavedGameStore.currentSchemaVersion + 1)
        await gateway.seed(payload)

        await #expect(throws: PersistenceError.self) {
            _ = try await store.loadSnapshot(recordName: "future-failed")
        }
    }

    /// #515 parity: a signed-out iCloud fetch degrades to `nil`, not a throw.
    @Test
    func returnsNilOnICloudSignedOutError() async throws {
        let gateway = ThrowingSnapshotGateway(
            fetchError: NSError(domain: "CKErrorDomain", code: 9) // .notAuthenticated
        )
        let store = MinesweeperSavedGameStore(gateway: gateway, clock: { Self.fixedDate })
        #expect(try await store.loadSnapshot(recordName: "any-record") == nil)
    }
}

/// Minimal fetch-throwing fake — mirrors `ThrowingQueryGateway` in
/// MinesweeperSavedGameStoreTests.swift (kept local: that fake is `private`
/// / file-scoped).
private actor ThrowingSnapshotGateway: PrivateCKGateway {
    private let fetchError: (any Error & Sendable)?

    init(fetchError: (any Error & Sendable)? = nil) {
        self.fetchError = fetchError
    }

    func provisionZone() async throws {}
    func installSubscriptionIfNeeded() async throws {}

    func fetch(recordName: String) async throws -> RecordPayload? {
        if let error = fetchError { throw error }
        return nil
    }

    func save(_ payload: RecordPayload, policy: RecordSavePolicy) async throws {}
    func delete(recordName: String) async throws {}

    func query(_ predicate: RecordPredicate) async throws -> [RecordPayload] {
        []
    }
}
