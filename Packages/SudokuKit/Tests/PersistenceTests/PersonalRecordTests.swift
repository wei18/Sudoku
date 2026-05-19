// PersonalRecordTests — Phase 5.5: PR CRUD + dedup (§How.2 末段).

import Foundation
import Testing
import SudokuKitTesting
@testable import Persistence

@Suite("Persistence — PersonalRecord")
struct PersonalRecordTests {

    private let clock: @Sendable () -> Date = { Date(timeIntervalSince1970: 1_000) }

    private func makeStore() -> (PersonalRecordStore, FakePrivateCKGateway) {
        let gateway = FakePrivateCKGateway()
        let store = PersonalRecordStore(gateway: gateway, clock: clock)
        return (store, gateway)
    }

    @Test func recordNameIsModeDifficulty() {
        #expect(PersonalRecordStore.recordName(mode: "daily", difficulty: "easy") == "daily-easy")
        #expect(PersonalRecordStore.recordName(mode: "practice", difficulty: "hard") == "practice-hard")
    }

    @Test func reCompletingSamePuzzleIdDoesNotBump() async throws {
        let (store, _) = makeStore()
        let first = try await store.recordCompletion(
            puzzleId: "2026-06-01-easy", mode: "daily", difficulty: "easy", elapsedSeconds: 100
        )
        #expect(first.completedCount == 1)
        #expect(first.bestTimeSeconds == 100)
        let second = try await store.recordCompletion(
            puzzleId: "2026-06-01-easy", mode: "daily", difficulty: "easy", elapsedSeconds: 90
        )
        #expect(second.completedCount == 1) // unchanged
        #expect(second.bestTimeSeconds == 100) // unchanged
        #expect(second.totalTimeSeconds == 100)
    }

    @Test func differentPuzzleIdsBumpCount() async throws {
        let (store, _) = makeStore()
        _ = try await store.recordCompletion(
            puzzleId: "p1", mode: "daily", difficulty: "easy", elapsedSeconds: 100
        )
        let second = try await store.recordCompletion(
            puzzleId: "p2", mode: "daily", difficulty: "easy", elapsedSeconds: 200
        )
        #expect(second.completedCount == 2)
        #expect(second.totalTimeSeconds == 300)
    }

    @Test func fetchAllReturnsAtMostSix() async throws {
        let (store, _) = makeStore()
        let modes = ["daily", "practice"]
        let difficulties = ["easy", "medium", "hard"]
        for mode in modes {
            for diff in difficulties {
                _ = try await store.recordCompletion(
                    puzzleId: "p-\(mode)-\(diff)", mode: mode, difficulty: diff, elapsedSeconds: 60
                )
            }
        }
        var records: [PersonalRecord] = []
        for mode in modes {
            for diff in difficulties {
                records.append(try await store.fetch(mode: mode, difficulty: diff))
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
            puzzleId: "p1", mode: "practice", difficulty: "medium", elapsedSeconds: 250
        )
        #expect(result.bestTimeSeconds == 250)
    }

    @Test func betterCompletionLowersBestTime() async throws {
        let (store, _) = makeStore()
        _ = try await store.recordCompletion(
            puzzleId: "p1", mode: "practice", difficulty: "medium", elapsedSeconds: 300
        )
        let updated = try await store.recordCompletion(
            puzzleId: "p2", mode: "practice", difficulty: "medium", elapsedSeconds: 200
        )
        #expect(updated.bestTimeSeconds == 200)
    }

    @Test func worseCompletionPreservesBestTime() async throws {
        let (store, _) = makeStore()
        _ = try await store.recordCompletion(
            puzzleId: "p1", mode: "practice", difficulty: "medium", elapsedSeconds: 200
        )
        let updated = try await store.recordCompletion(
            puzzleId: "p2", mode: "practice", difficulty: "medium", elapsedSeconds: 300
        )
        #expect(updated.bestTimeSeconds == 200)
    }

    @Test func emptyFetchReturnsEmptyRecord() async throws {
        let (store, _) = makeStore()
        let record = try await store.fetch(mode: "daily", difficulty: "hard")
        #expect(record.bestTimeSeconds == nil)
        #expect(record.completedCount == 0)
        #expect(record.totalTimeSeconds == 0)
        #expect(record.completedPuzzleIds.isEmpty)
        #expect(record.recordName == "daily-hard")
    }
}
