// MinesweeperPersonalRecordStoreTests — CRUD + dedup (#699).
// Structural mirror of PersistenceKit's `PersonalRecordTests`, against the
// shared `FakePrivateCKGateway` — no live CloudKit; the record-type schema
// this store writes is deployed separately (user-owned ck:schema).

import Foundation
import Testing
import MinesweeperEngine
import Persistence
import PersistenceTesting
@testable import MinesweeperPersistence

@Suite("MinesweeperPersonalRecordStore — CRUD + dedup (#699)")
struct MinesweeperPersonalRecordStoreTests {

    private let clock: @Sendable () -> Date = { Date(timeIntervalSince1970: 1_000) }

    private func makeStore() -> (MinesweeperPersonalRecordStore, FakePrivateCKGateway) {
        let gateway = FakePrivateCKGateway()
        let store = MinesweeperPersonalRecordStore(gateway: gateway, clock: clock)
        return (store, gateway)
    }

    @Test func recordNameIsModeDifficulty() {
        #expect(MinesweeperPersonalRecordStore.recordName(modeRaw: "daily", difficulty: .beginner) == "daily-beginner")
        #expect(MinesweeperPersonalRecordStore.recordName(modeRaw: "practice", difficulty: .expert) == "practice-expert")
    }

    @Test func reCompletingSamePuzzleIdDoesNotBump() async throws {
        let (store, _) = makeStore()
        let first = try await store.recordCompletion(
            puzzleId: "daily-2026-06-01-beginner", modeRaw: "daily", difficulty: .beginner, elapsedSeconds: 100
        )
        #expect(first.completedCount == 1)
        #expect(first.bestTimeSeconds == 100)
        let second = try await store.recordCompletion(
            puzzleId: "daily-2026-06-01-beginner", modeRaw: "daily", difficulty: .beginner, elapsedSeconds: 90
        )
        #expect(second.completedCount == 1) // unchanged
        #expect(second.bestTimeSeconds == 100) // unchanged
        #expect(second.totalTimeSeconds == 100)
    }

    @Test func differentPuzzleIdsBumpCount() async throws {
        let (store, _) = makeStore()
        _ = try await store.recordCompletion(
            puzzleId: "p1", modeRaw: "daily", difficulty: .beginner, elapsedSeconds: 100
        )
        let second = try await store.recordCompletion(
            puzzleId: "p2", modeRaw: "daily", difficulty: .beginner, elapsedSeconds: 200
        )
        #expect(second.completedCount == 2)
        #expect(second.totalTimeSeconds == 300)
    }

    @Test func fetchAllReturnsAtMostSix() async throws {
        let (store, _) = makeStore()
        let modes = ["daily", "practice"]
        for modeRaw in modes {
            for diff in Difficulty.allCases {
                _ = try await store.recordCompletion(
                    puzzleId: "p-\(modeRaw)-\(diff.rawValue)",
                    modeRaw: modeRaw, difficulty: diff, elapsedSeconds: 60
                )
            }
        }
        var records: [MinesweeperPersonalRecord] = []
        for modeRaw in modes {
            for diff in Difficulty.allCases {
                records.append(try await store.fetch(modeRaw: modeRaw, difficulty: diff))
            }
        }
        #expect(records.count == 6)
        // All deterministic record names unique:
        let names = Set(records.map(\.recordName))
        #expect(names.count == 6)
    }

    @Test func firstCompletionSetsBestTime() async throws {
        let (store, _) = makeStore()
        let result = try await store.recordCompletion(
            puzzleId: "p1", modeRaw: "practice", difficulty: .intermediate, elapsedSeconds: 250
        )
        #expect(result.bestTimeSeconds == 250)
    }

    @Test func betterCompletionLowersBestTime() async throws {
        let (store, _) = makeStore()
        _ = try await store.recordCompletion(
            puzzleId: "p1", modeRaw: "practice", difficulty: .intermediate, elapsedSeconds: 300
        )
        let updated = try await store.recordCompletion(
            puzzleId: "p2", modeRaw: "practice", difficulty: .intermediate, elapsedSeconds: 200
        )
        #expect(updated.bestTimeSeconds == 200)
    }

    @Test func worseCompletionPreservesBestTime() async throws {
        let (store, _) = makeStore()
        _ = try await store.recordCompletion(
            puzzleId: "p1", modeRaw: "practice", difficulty: .intermediate, elapsedSeconds: 200
        )
        let updated = try await store.recordCompletion(
            puzzleId: "p2", modeRaw: "practice", difficulty: .intermediate, elapsedSeconds: 300
        )
        #expect(updated.bestTimeSeconds == 200)
    }

    @Test func emptyFetchReturnsEmptyRecord() async throws {
        let (store, _) = makeStore()
        let record = try await store.fetch(modeRaw: "daily", difficulty: .expert)
        #expect(record.bestTimeSeconds == nil)
        #expect(record.completedCount == 0)
        #expect(record.totalTimeSeconds == 0)
        #expect(record.completedPuzzleIds.isEmpty)
        #expect(record.recordName == "daily-expert")
    }

    @Test func unknownDifficultyRawValueDropsTheRow() async throws {
        // Forward-compat guard: a record written by a future schema with an
        // unrecognized difficulty must decode to nil (mirrors Sudoku's
        // PersonalRecordMapper guard), so `fetch` falls back to `.empty`.
        let (store, gateway) = makeStore()
        let recordName = MinesweeperPersonalRecordStore.recordName(modeRaw: "daily", difficulty: .beginner)
        let payload = RecordPayload(
            recordType: PrivateCKConstants.personalRecordRecordType,
            recordName: recordName,
            fields: [
                "mode": .string("daily"),
                "difficulty": .string("nightmare"),
                "bestTimeSeconds": .int(10),
                "totalTimeSeconds": .int(10),
                "completedCount": .int(1),
                "lastUpdatedAt": .date(Date(timeIntervalSince1970: 0)),
                "completedPuzzleIds": .stringSet(["p"]),
                "schemaVersion": .int(1)
            ]
        )
        await gateway.seed(payload)

        let record = try await store.fetch(modeRaw: "daily", difficulty: .beginner)
        #expect(record.completedCount == 0)
        #expect(record.bestTimeSeconds == nil)
    }
}
