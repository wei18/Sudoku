// MinesweeperPersonalRecordRaceTests — multi-device best-time race does NOT
// clobber the faster record, and completedPuzzleIds is a union. Structural
// mirror of PersistenceKit's `PersonalRecordRaceTests` (#552 precedent), MS
// types (#699).
//
// Setup: two MinesweeperPersonalRecordStore instances share ONE
// FakePrivateCKGateway. A records fast (pA, 100 s). B fetched-stale (before
// A's write) then records slower (pB, 200 s). B's first .ifUnchanged save
// must conflict; B retries; final record must show bestTimeSeconds == 100
// (A's faster best kept), completedCount == 2, completedPuzzleIds == {pA, pB}.

import Foundation
import Testing
import MinesweeperEngine
import Persistence
import PersistenceTesting
@testable import MinesweeperPersistence

@Suite("MinesweeperPersonalRecord — multi-device race (acceptance)")
struct MinesweeperPersonalRecordRaceTests {

    private let clock: @Sendable () -> Date = { Date(timeIntervalSince1970: 1_000) }

    // MARK: - THE acceptance test

    @Test func sequentialThreeWriteMergeKeepsFasterBestAndUnionsIds() async throws {
        let gateway = FakePrivateCKGateway()
        let storeA = MinesweeperPersonalRecordStore(gateway: gateway, clock: clock)
        let storeB = MinesweeperPersonalRecordStore(gateway: gateway, clock: clock)

        let pFirst = "p-first"
        _ = try await storeA.recordCompletion(
            puzzleId: pFirst, modeRaw: "daily", difficulty: .beginner, elapsedSeconds: 500
        )
        let puzzleA = "p-A"
        _ = try await storeA.recordCompletion(
            puzzleId: puzzleA, modeRaw: "daily", difficulty: .beginner, elapsedSeconds: 100
        )
        let puzzleB = "p-B"
        _ = try await storeB.recordCompletion(
            puzzleId: puzzleB, modeRaw: "daily", difficulty: .beginner, elapsedSeconds: 200
        )

        let final = try await storeA.fetch(modeRaw: "daily", difficulty: .beginner)
        #expect(final.bestTimeSeconds == 100, "fastest time wins")
        #expect(final.completedCount == 3, "pFirst + puzzleA + puzzleB = 3 completions")
        #expect(final.completedPuzzleIds.contains(puzzleA))
        #expect(final.completedPuzzleIds.contains(puzzleB))
        #expect(final.completedPuzzleIds.contains(pFirst))
    }

    @Test func sequentialSlowerSecondWriteMergesKeepingFasterBest() async throws {
        let gateway = FakePrivateCKGateway()
        let storeA = MinesweeperPersonalRecordStore(gateway: gateway, clock: clock)
        let storeB = MinesweeperPersonalRecordStore(gateway: gateway, clock: clock)

        let puzzleA = "daily-2026-06-21-beginner"
        let puzzleB = "daily-2026-06-22-beginner"

        _ = try await storeA.recordCompletion(
            puzzleId: puzzleA, modeRaw: "daily", difficulty: .beginner, elapsedSeconds: 100
        )
        _ = try await storeB.recordCompletion(
            puzzleId: puzzleB, modeRaw: "daily", difficulty: .beginner, elapsedSeconds: 200
        )

        let final = try await storeA.fetch(modeRaw: "daily", difficulty: .beginner)
        #expect(final.bestTimeSeconds == 100)
        #expect(final.completedCount == 2)
        #expect(final.completedPuzzleIds == [puzzleA, puzzleB])
    }

    // MARK: - maxAttempts exhaustion throws .syncConflict

    @Test func maxAttemptsExhaustionThrowsSyncConflict() async throws {
        let gateway = AlwaysConflictGateway()
        let store = MinesweeperPersonalRecordStore(gateway: gateway, clock: clock)
        await #expect(throws: PersistenceError.syncConflict(recordName: "daily-beginner")) {
            try await store.recordCompletion(
                puzzleId: "p1", modeRaw: "daily", difficulty: .beginner, elapsedSeconds: 100
            )
        }
    }

    // MARK: - conflict-ONCE then succeed (the real optimistic-concurrency path)

    @Test func staleFirstSaveConflictsThenRetrySucceedsKeepingFasterBest() async throws {
        let inner = FakePrivateCKGateway()
        let deviceARecord = MinesweeperPersonalRecord(
            recordName: "daily-beginner", modeRaw: "daily", difficulty: .beginner,
            bestTimeSeconds: 100, totalTimeSeconds: 100, completedCount: 1,
            lastUpdatedAt: Date(timeIntervalSince1970: 1_000),
            completedPuzzleIds: ["p-A"]
        )
        let gateway = ConflictOnceGateway(
            inner: inner,
            injectedAPayload: MinesweeperPersonalRecordMapper.payload(from: deviceARecord)
        )
        let storeB = MinesweeperPersonalRecordStore(gateway: gateway, clock: clock)

        _ = try await storeB.recordCompletion(
            puzzleId: "p-B", modeRaw: "daily", difficulty: .beginner, elapsedSeconds: 200
        )

        #expect(await gateway.sawConflict, "B's first .ifUnchanged save must have conflicted")
        let final = try await storeB.fetch(modeRaw: "daily", difficulty: .beginner)
        #expect(final.bestTimeSeconds == 100, "A's faster best must survive B's retry")
        #expect(final.completedCount == 2, "A's p-A + B's p-B")
        #expect(final.completedPuzzleIds == ["p-A", "p-B"], "union of both devices' puzzles")
    }
}

// MARK: - ConflictOnceGateway

/// Decorator over `FakePrivateCKGateway` that simulates a concurrent device-A
/// write landing AFTER the caller fetched but BEFORE its first save: on the
/// first `.ifUnchanged` save it injects `injectedAPayload` (last-write-wins,
/// bumping the server version) and then forwards the now-stale save — which
/// the Fake rejects with `.syncConflict`. Subsequent saves forward unchanged.
private actor ConflictOnceGateway: PrivateCKGateway {
    private let inner: FakePrivateCKGateway
    private let injectedAPayload: RecordPayload
    private var injected = false
    private(set) var sawConflict = false

    init(inner: FakePrivateCKGateway, injectedAPayload: RecordPayload) {
        self.inner = inner
        self.injectedAPayload = injectedAPayload
    }

    func provisionZone() async throws { try await inner.provisionZone() }
    func installSubscriptionIfNeeded() async throws { try await inner.installSubscriptionIfNeeded() }
    func fetch(recordName: String) async throws -> RecordPayload? {
        try await inner.fetch(recordName: recordName)
    }
    func delete(recordName: String) async throws { try await inner.delete(recordName: recordName) }
    func query(_ predicate: RecordPredicate) async throws -> [RecordPayload] {
        try await inner.query(predicate)
    }

    func save(_ payload: RecordPayload, policy: RecordSavePolicy) async throws {
        if !injected, case .ifUnchanged = policy {
            injected = true
            // Device A's concurrent write lands first (bumps server version).
            try await inner.save(injectedAPayload, policy: .lastWriteWins)
        }
        do {
            try await inner.save(payload, policy: policy)
        } catch PersistenceError.syncConflict {
            sawConflict = true
            throw PersistenceError.syncConflict(recordName: payload.recordName)
        }
    }
}

// MARK: - AlwaysConflictGateway

/// A gateway that always has an existing record (so .ifUnchanged is always
/// checked) and always rejects saves with .syncConflict — forcing maxAttempts
/// exhaustion in recordCompletion.
private actor AlwaysConflictGateway: PrivateCKGateway {
    private var serverVersion = 0

    func provisionZone() async throws {}
    func installSubscriptionIfNeeded() async throws {}

    func fetch(recordName: String) async throws -> RecordPayload? {
        serverVersion += 1
        return RecordPayload(
            recordType: PrivateCKConstants.personalRecordRecordType,
            recordName: recordName,
            fields: [
                "mode": .string("daily"),
                "difficulty": .string("beginner"),
                "bestTimeSeconds": .int(50),
                "totalTimeSeconds": .int(50),
                "completedCount": .int(1),
                "lastUpdatedAt": .date(Date(timeIntervalSince1970: 0)),
                "completedPuzzleIds": .stringSet(["other"]),
                "schemaVersion": .int(1)
            ],
            encodedSystemFields: Data("etag-v\(serverVersion)".utf8)
        )
    }

    func save(_ payload: RecordPayload, policy: RecordSavePolicy) async throws {
        throw PersistenceError.syncConflict(recordName: payload.recordName)
    }

    func delete(recordName: String) async throws {}
    func query(_ predicate: RecordPredicate) async throws -> [RecordPayload] { [] }
}
