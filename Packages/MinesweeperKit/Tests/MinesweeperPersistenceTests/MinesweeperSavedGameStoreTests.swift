// MinesweeperSavedGameStore — snapshot ↔ CloudKit record round-trip against
// the shared FakePrivateCKGateway (#455). No live CloudKit; the record-type
// schema this store writes is deployed separately (user-owned ck:schema).

import Foundation
import Testing
import MinesweeperEngine
import MinesweeperGameState
import Persistence
import PersistenceTesting
@testable import MinesweeperPersistence

@Suite("MinesweeperSavedGameStore — save / resume surface (#455)")
struct MinesweeperSavedGameStoreTests {

    private static let fixedDate = Date(timeIntervalSince1970: 1_750_000_000)

    private func makeStore(_ gateway: FakePrivateCKGateway) -> MinesweeperSavedGameStore {
        MinesweeperSavedGameStore(gateway: gateway, clock: { Self.fixedDate })
    }

    /// A mid-play snapshot with real revealed state — high-bit seed proves
    /// the UInt64 ↔ Int64 bit-pattern wire mapping is lossless.
    private func midPlaySnapshot(seed: UInt64 = UInt64.max - 1) async throws -> MinesweeperSessionSnapshot {
        let session = MinesweeperSession(difficulty: .beginner, seed: seed)
        _ = try await session.reveal(row: 4, col: 4)
        return await session.snapshot()
    }

    @Test
    func saveThenLatestInProgressReturnsCorrectSummary() async throws {
        let gateway = FakePrivateCKGateway()
        let store = makeStore(gateway)
        let snapshot = try await midPlaySnapshot()

        try await store.save(snapshot, modeRaw: "practice", recordName: "ms-practice-1")

        let summary = try await store.latestInProgress()
        let unwrapped = try #require(summary)
        #expect(unwrapped.recordName == "ms-practice-1")
        #expect(unwrapped.difficulty == .beginner)
        #expect(unwrapped.seed == UInt64.max - 1)   // bit-pattern round-trip
        #expect(unwrapped.modeRaw == "practice")
        #expect(unwrapped.elapsedSeconds == snapshot.elapsedSeconds)
        #expect(unwrapped.status == "inProgress")
        #expect(unwrapped.lastModifiedAt == Self.fixedDate)
    }

    @Test
    func saveThenLoadRoundTripsSnapshotAndRestoresBoard() async throws {
        let gateway = FakePrivateCKGateway()
        let store = makeStore(gateway)
        let snapshot = try await midPlaySnapshot(seed: 99)

        try await store.save(snapshot, modeRaw: "daily", recordName: "ms-daily-1")
        let loaded = try await store.loadInProgress(recordName: "ms-daily-1")
        let unwrapped = try #require(loaded)
        #expect(unwrapped == snapshot)

        // Step-1 determinism: the loaded snapshot rebuilds the exact board.
        let restored = await MinesweeperSession.restore(from: unwrapped)
        let restoredSnap = await restored.snapshot()
        #expect(restoredSnap.cells == snapshot.cells)
    }

    @Test
    func latestInProgressPicksMostRecentlyModified() async throws {
        let gateway = FakePrivateCKGateway()
        // Two stores over the SAME gateway, each with a fixed clock — avoids
        // a mutable capture in the @Sendable clock closure.
        let earlier = MinesweeperSavedGameStore(gateway: gateway, clock: { Self.fixedDate })
        let later = MinesweeperSavedGameStore(
            gateway: gateway,
            clock: { Self.fixedDate.addingTimeInterval(60) }
        )
        try await earlier.save(try await midPlaySnapshot(seed: 1), modeRaw: "practice", recordName: "older")
        try await later.save(try await midPlaySnapshot(seed: 2), modeRaw: "practice", recordName: "newer")

        let summary = try await later.latestInProgress()
        #expect(try #require(summary).recordName == "newer")
    }

    @Test
    func markCompletedExcludesFromLatestInProgress() async throws {
        let gateway = FakePrivateCKGateway()
        let store = makeStore(gateway)
        try await store.save(try await midPlaySnapshot(), modeRaw: "daily", recordName: "ms-daily-2")

        try await store.markCompleted(recordName: "ms-daily-2")

        #expect(try await store.latestInProgress() == nil)
        // The record itself survives with the flipped status.
        let payload = try await gateway.fetch(recordName: "ms-daily-2")
        #expect(try #require(payload).fields["status"] == .string("completed"))
    }

    @Test
    func markCompletedOnMissingRecordThrows() async throws {
        let store = makeStore(FakePrivateCKGateway())
        await #expect(throws: PersistenceError.self) {
            try await store.markCompleted(recordName: "nope")
        }
    }

    @Test
    func wireStatusMapsTerminalStatesToCompleted() async throws {
        let session = MinesweeperSession(difficulty: .beginner, seed: 7)
        _ = try await session.reveal(row: 4, col: 4)
        let snap = await session.snapshot()

        #expect(MinesweeperSavedGameStore.wireStatus(for: .won) == "completed")
        #expect(MinesweeperSavedGameStore.wireStatus(for: .lost) == "completed")
        #expect(MinesweeperSavedGameStore.wireStatus(for: snap.status) == "inProgress")
    }

    @Test
    func recordNameSchemesAreStable() {
        #expect(
            MinesweeperSavedGameStore.recordName(dailyDay: "2026-06-10", difficulty: .beginner)
                == "daily-2026-06-10-beginner"
        )
        #expect(
            MinesweeperSavedGameStore.recordName(practice: .expert) == "practice-expert"
        )
    }

    @Test
    func loadInProgressThrowsOnNewerSchemaVersion() async throws {
        let gateway = FakePrivateCKGateway()
        let store = makeStore(gateway)
        let snapshot = try await midPlaySnapshot()
        try await store.save(snapshot, modeRaw: "practice", recordName: "future")

        // Simulate a record written by a newer build.
        var payload = try #require(await gateway.fetch(recordName: "future"))
        payload.fields["schemaVersion"] = .int(MinesweeperSavedGameStore.currentSchemaVersion + 1)
        await gateway.seed(payload)

        await #expect(throws: PersistenceError.self) {
            _ = try await store.loadInProgress(recordName: "future")
        }
    }

    @Test
    func loadInProgressPropagatesCorruptBlobError() async throws {
        let gateway = FakePrivateCKGateway()
        let store = makeStore(gateway)
        let snapshot = try await midPlaySnapshot()
        try await store.save(snapshot, modeRaw: "practice", recordName: "corrupt")

        var payload = try #require(await gateway.fetch(recordName: "corrupt"))
        payload.fields["stateBlob"] = .data(Data("not json".utf8))
        await gateway.seed(payload)

        await #expect(throws: (any Error).self) {
            _ = try await store.loadInProgress(recordName: "corrupt")
        }
    }
}
