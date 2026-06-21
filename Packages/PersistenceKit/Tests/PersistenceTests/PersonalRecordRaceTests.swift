// PersonalRecordRaceTests — #552: multi-device best-time race does NOT clobber
// the faster record, and completedPuzzleIds is a union.
//
// Setup: two PersonalRecordStore instances share ONE FakePrivateCKGateway.
// A records fast (pA, 100 s). B fetched-stale (before A's write) then records
// slower (pB, 200 s). B's first .ifUnchanged save must conflict; B retries;
// final record must show bestTimeSeconds == 100 (A's faster best kept),
// completedCount == 2, completedPuzzleIds == {pA, pB} (union).

import Foundation
import Testing
import SudokuEngine
import PersistenceTesting
@testable import Persistence

@Suite("PersonalRecord — multi-device race (acceptance)")
struct PersonalRecordRaceTests {

    private let clock: @Sendable () -> Date = { Date(timeIntervalSince1970: 1_000) }

    // MARK: - THE acceptance test

    // NOTE: these first two are SEQUENTIAL-merge tests — each `recordCompletion`
    // fetches fresh, so no `.ifUnchanged` conflict is exercised here. They prove
    // the min(best) + union(ids) merge math across ordered writes through the
    // shared gateway. The genuine conflict→retry→succeed path is proven by
    // `staleFirstSaveConflictsThenRetrySucceedsKeepingFasterBest` below.

    @Test func sequentialThreeWriteMergeKeepsFasterBestAndUnionsIds() async throws {
        let gateway = FakePrivateCKGateway()
        let storeA = PersonalRecordStore(gateway: gateway, clock: clock)
        let storeB = PersonalRecordStore(gateway: gateway, clock: clock)

        // A: first completion (best=500), then a faster one (best=100); B then
        // records a slower one (200). Each fetches fresh → merges; final keeps
        // the fastest (100) and unions all three puzzleIds.
        let pFirst = "p-first"
        _ = try await storeA.recordCompletion(
            puzzleId: pFirst, mode: .daily, difficulty: .easy, elapsedSeconds: 500
        )
        let puzzleA = "p-A"
        _ = try await storeA.recordCompletion(
            puzzleId: puzzleA, mode: .daily, difficulty: .easy, elapsedSeconds: 100
        )
        let puzzleB = "p-B"
        _ = try await storeB.recordCompletion(
            puzzleId: puzzleB, mode: .daily, difficulty: .easy, elapsedSeconds: 200
        )

        let final = try await storeA.fetch(mode: .daily, difficulty: .easy)
        #expect(final.bestTimeSeconds == 100, "fastest time wins")
        #expect(final.completedCount == 3, "pFirst + puzzleA + puzzleB = 3 completions")
        #expect(final.completedPuzzleIds.contains(puzzleA))
        #expect(final.completedPuzzleIds.contains(puzzleB))
        #expect(final.completedPuzzleIds.contains(pFirst))
    }

    @Test func sequentialBSlowerDoesNotClobberAFasterBest() async throws {
        // Sequential (no conflict): A records fast, then B records slower; B's
        // fresh fetch sees A's best=100 and mins against it.
        let gateway = FakePrivateCKGateway()
        let storeA = PersonalRecordStore(gateway: gateway, clock: clock)
        let storeB = PersonalRecordStore(gateway: gateway, clock: clock)

        let puzzleA = "2026-06-21-easy"
        let puzzleB = "2026-06-22-easy"

        // A records fast
        _ = try await storeA.recordCompletion(
            puzzleId: puzzleA, mode: .daily, difficulty: .easy, elapsedSeconds: 100
        )

        // B records slow — the retry loop inside recordCompletion should
        // fetch the fresh record (with A's best=100) and merge correctly.
        _ = try await storeB.recordCompletion(
            puzzleId: puzzleB, mode: .daily, difficulty: .easy, elapsedSeconds: 200
        )

        let final = try await storeA.fetch(mode: .daily, difficulty: .easy)
        #expect(final.bestTimeSeconds == 100)
        #expect(final.completedCount == 2)
        #expect(final.completedPuzzleIds == [puzzleA, puzzleB])
    }

    // MARK: - maxAttempts exhaustion throws .syncConflict

    @Test func maxAttemptsExhaustionThrowsSyncConflict() async throws {
        // A gateway that always conflicts on .ifUnchanged by never bumping
        // the version in the way the store expects.
        let gateway = AlwaysConflictGateway()
        let store = PersonalRecordStore(gateway: gateway, clock: clock)
        await #expect(throws: PersistenceError.syncConflict(recordName: "daily-easy")) {
            try await store.recordCompletion(
                puzzleId: "p1", mode: .daily, difficulty: .easy, elapsedSeconds: 100
            )
        }
    }

    // MARK: - conflict-ONCE then succeed (the real optimistic-concurrency path)

    /// Drives a genuine first-attempt conflict: device A writes a FASTER time
    /// concurrently AFTER device B has fetched (injected on B's first
    /// `.ifUnchanged` save), so B's etag is stale → `.syncConflict` → B's retry
    /// re-fetches the fresh record and re-mins. Proves the conflict→retry→
    /// succeed path keeps A's faster best (not just sequential fresh-fetch merge).
    @Test func staleFirstSaveConflictsThenRetrySucceedsKeepingFasterBest() async throws {
        let inner = FakePrivateCKGateway()
        // A's faster record that the decorator injects on B's first save.
        let deviceARecord = PersonalRecord(
            recordName: "daily-easy", mode: .daily, difficulty: .easy,
            bestTimeSeconds: 100, totalTimeSeconds: 100, completedCount: 1,
            lastUpdatedAt: Date(timeIntervalSince1970: 1_000),
            completedPuzzleIds: ["p-A"]
        )
        let gateway = ConflictOnceGateway(
            inner: inner,
            injectedAPayload: PersonalRecordMapper.payload(from: deviceARecord)
        )
        let storeB = PersonalRecordStore(gateway: gateway, clock: clock)

        // B records a SLOWER time (200s) for puzzle p-B. Its first save carries
        // a nil/stale etag, but the decorator has just landed A's record →
        // conflict → B retries against A's fresh record.
        _ = try await storeB.recordCompletion(
            puzzleId: "p-B", mode: .daily, difficulty: .easy, elapsedSeconds: 200
        )

        #expect(await gateway.sawConflict, "B's first .ifUnchanged save must have conflicted")
        let final = try await storeB.fetch(mode: .daily, difficulty: .easy)
        #expect(final.bestTimeSeconds == 100, "A's faster best must survive B's retry")
        #expect(final.completedCount == 2, "A's p-A + B's p-B")
        #expect(final.completedPuzzleIds == ["p-A", "p-B"], "union of both devices' puzzles")
    }
}

// MARK: - ConflictOnceGateway

/// Decorator over `FakePrivateCKGateway` that simulates a concurrent device-A
/// write landing AFTER the caller fetched but BEFORE its first save: on the
/// first `.ifUnchanged` save it injects `injectedAPayload` (last-write-wins,
/// bumping the server version) and then forwards the now-stale save — which the
/// Fake rejects with `.syncConflict`. Subsequent saves forward unchanged.
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

    /// Returns an existing record whose etag bumps (deterministically) on every
    /// fetch, so the store always sees an existing record and — combined with
    /// `save` always throwing — exhausts the retry loop.
    func fetch(recordName: String) async throws -> RecordPayload? {
        serverVersion += 1
        return RecordPayload(
            recordType: PrivateCKConstants.personalRecordRecordType,
            recordName: recordName,
            fields: [
                "mode": .string("daily"),
                "difficulty": .string("easy"),
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

    /// Always conflicts — simulates a server that keeps getting updated.
    func save(_ payload: RecordPayload, policy: RecordSavePolicy) async throws {
        throw PersistenceError.syncConflict(recordName: payload.recordName)
    }

    func delete(recordName: String) async throws {}
    func query(_ predicate: RecordPredicate) async throws -> [RecordPayload] { [] }
}
