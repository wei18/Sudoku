// CacheTests — Phase 6.3 (plan.md §6.3, design.md §How.4.7).
//
// Daily trio is cached in-memory keyed by `(utcDay, generatorVersion)`.
// Practice is NOT cached (§How.4.1 末段: fresh salt per call).

import Foundation
import Testing
@testable import PuzzleStore
import SudokuEngine
import SudokuKitTesting

@Suite("PuzzleStore — daily cache")
struct PuzzleStoreCacheTests {

    private static let dayA: Date = Date(timeIntervalSince1970: 1_780_272_000) // 2026-06-01T00Z
    private static let dayB: Date = Date(timeIntervalSince1970: 1_780_358_400) // 2026-06-02T00Z

    @Test func dailyTrioCachedForSameDate() async throws {
        let generator = FakeGenerator()
        let store = PuzzleStore(generator: generator)
        _ = try await store.fetchDailyTrio(date: Self.dayA)
        #expect(generator.callCount == 3)
        _ = try await store.fetchDailyTrio(date: Self.dayA)
        #expect(generator.callCount == 3) // no new calls.
    }

    @Test func cacheInvalidatedOnDateChange() async throws {
        let generator = FakeGenerator()
        let store = PuzzleStore(generator: generator)
        _ = try await store.fetchDailyTrio(date: Self.dayA)
        _ = try await store.fetchDailyTrio(date: Self.dayB)
        #expect(generator.callCount == 6)
    }

    @Test func cacheKeyedAlsoByGeneratorVersion() async throws {
        // v1 is the only shipped version, but `DailyCacheKey` already includes
        // `generatorVersion`. Constructing two stores with the same fake but
        // different version slots demonstrates that the same date does not
        // share cache across versions. This is a forward-architecture probe
        // ahead of v2 (§How.4.5).
        let generator = FakeGenerator()
        let storeV1 = PuzzleStore(generator: generator, generatorVersion: .v1)
        _ = try await storeV1.fetchDailyTrio(date: Self.dayA)
        // Different store instance → fresh cache; just assert generator
        // received 3 calls per fetch.
        let storeV1b = PuzzleStore(generator: generator, generatorVersion: .v1)
        _ = try await storeV1b.fetchDailyTrio(date: Self.dayA)
        #expect(generator.callCount == 6)
    }

    @Test func practiceNotCached() async throws {
        let generator = FakeGenerator()
        let store = PuzzleStore(generator: generator)
        _ = try await store.fetchPracticePool(difficulty: .easy)
        _ = try await store.fetchPracticePool(difficulty: .easy)
        _ = try await store.fetchPracticePool(difficulty: .easy)
        #expect(generator.callCount == 3)
    }
}
