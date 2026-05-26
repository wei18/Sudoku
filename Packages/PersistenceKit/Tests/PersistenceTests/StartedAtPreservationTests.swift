// StartedAtPreservationTests — Wave-2 BLOCKER B4 regression.
//
// Pre-fix bug: `SavedGameMapper.payload(...)` hardcoded
// `startedAt = lastModifiedAt` on every save. Original session start
// time was destroyed on the first save and every subsequent one.
// Personal-record analytics + LWW conflict resolution depend on the
// authentic `startedAt`.
//
// Post-fix: `GameSessionSnapshot.startedAt` is the single source of
// truth (captured by `GameSession.start()` on first transition). The
// mapper writes that value through, and reads it back on snapshot().
//
// Per impl-notes meetings/2026-05-20_wave-2-blocker-fixes.impl-notes.md §B4.

import Foundation
import GameState
import SudokuEngine
import Telemetry
import Testing
import PersistenceTesting
import TelemetryTesting
import TelemetryTesting
@testable import Persistence

@Suite("Persistence — startedAt preservation (B4)")
struct StartedAtPreservationTests {

    @Test("snapshot startedAt round-trips through save → load")
    func startedAtRoundTrips() async throws {
        let gateway = FakePrivateCKGateway()
        let sink = RecordingSink()
        let telemetry = Telemetry(sinks: [sink])
        let puzzle = PuzzleFixtures.latinSquarePuzzle()

        // Anchor save's `clock` (lastModifiedAt) and the session's `now`
        // (startedAt) to DISTINCT timestamps so we can prove they're not
        // conflated by the mapper.
        let originalStart = Date(timeIntervalSince1970: 1_700_000_000)
        let firstSaveAt  = Date(timeIntervalSince1970: 1_700_001_000)
        let secondSaveAt = Date(timeIntervalSince1970: 1_700_002_000)

        // Mutable clock controlled via an actor wrapper so the
        // `@Sendable` clock closure stays Swift-6-clean.
        let clockBox = MutableClockBox(initial: firstSaveAt)
        let store = SavedGameStore(
            gateway: gateway,
            telemetry: telemetry,
            puzzleLoader: { _ in puzzle },
            clock: { clockBox.value }
        )

        // Fixture has 1 missing cell at (0,0); place INCORRECT digit so
        // the board doesn't auto-complete (we need status == .playing).
        let session = GameSession(puzzle: puzzle, now: { originalStart })
        try await session.start()
        try await session.placeDigit(row: 0, col: 0, digit: 5)
        let snap1 = await session.snapshot()
        #expect(snap1.startedAt == originalStart)

        let puzzleId = "p-started-at"
        let mode: Mode = .practice
        let difficulty: Difficulty = .easy
        try await store.save(snap1, puzzleId: puzzleId, mode: mode, difficulty: difficulty)

        // First load — startedAt must equal the session's start, NOT the
        // save clock.
        let loaded1 = try await store.loadOrCreate(
            puzzleId: puzzleId, mode: mode, difficulty: difficulty
        )
        #expect(loaded1.startedAt == originalStart, "first load must preserve original startedAt")

        // Second save — bump save clock; startedAt must STILL be the
        // original (mapper writes snapshot.startedAt, not its clock).
        // (No additional placeDigit — there is only one mutable cell on
        // this fixture, and we already placed our incorrect digit there.
        // Re-snapshotting and re-saving is enough to test that the second
        // save preserves startedAt.)
        clockBox.set(secondSaveAt)
        let snap2 = await session.snapshot()
        #expect(snap2.startedAt == originalStart)
        try await store.save(snap2, puzzleId: puzzleId, mode: mode, difficulty: difficulty)

        let loaded2 = try await store.loadOrCreate(
            puzzleId: puzzleId, mode: mode, difficulty: difficulty
        )
        #expect(loaded2.startedAt == originalStart, "second save must NOT overwrite startedAt")
    }

    @Test("Mapper writes the CK startedAt field with snapshot.startedAt (not clock)")
    func mapperUsesSnapshotStartedAtNotClock() async throws {
        let gateway = FakePrivateCKGateway()
        let sink = RecordingSink()
        let telemetry = Telemetry(sinks: [sink])
        let puzzle = PuzzleFixtures.latinSquarePuzzle()

        let originalStart = Date(timeIntervalSince1970: 1_700_000_000)
        let saveAt        = Date(timeIntervalSince1970: 1_700_999_999)
        let store = SavedGameStore(
            gateway: gateway,
            telemetry: telemetry,
            puzzleLoader: { _ in puzzle },
            clock: { saveAt }
        )

        let session = GameSession(puzzle: puzzle, now: { originalStart })
        try await session.start()
        try await session.placeDigit(row: 0, col: 0, digit: 5)
        let snapshot = await session.snapshot()

        let puzzleId = "p-mapper"
        let mode: Mode = .practice
        let difficulty: Difficulty = .easy
        try await store.save(snapshot, puzzleId: puzzleId, mode: mode, difficulty: difficulty)

        let recordName = SavedGameStore.recordName(for: puzzleId, mode: mode)
        let payload = try await gateway.fetch(recordName: recordName)
        guard case .date(let writtenStartedAt) = payload?.fields[SavedGameStore.Field.startedAt] else {
            Issue.record("startedAt field missing or wrong type")
            return
        }
        guard case .date(let writtenLastModifiedAt) = payload?.fields[SavedGameStore.Field.lastModifiedAt] else {
            Issue.record("lastModifiedAt field missing or wrong type")
            return
        }
        #expect(writtenStartedAt == originalStart)
        #expect(writtenLastModifiedAt == saveAt)
        #expect(writtenStartedAt != writtenLastModifiedAt, "two fields must be independent")
    }
}

/// Thread-safe mutable Date holder for `@Sendable` clock closures in tests.
/// `NSLock`-backed so `var.value` reads + `set(_:)` writes are race-free.
private final class MutableClockBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: Date
    init(initial: Date) { self._value = initial }
    var value: Date {
        lock.lock(); defer { lock.unlock() }
        return _value
    }
    func set(_ newValue: Date) {
        lock.lock(); defer { lock.unlock() }
        _value = newValue
    }
}
