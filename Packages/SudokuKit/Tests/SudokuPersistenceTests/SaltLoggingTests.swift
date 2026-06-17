// SaltLoggingTests — Phase 6.4 (plan.md §6.4, design.md §How.4.1 末段).
//
// Practice salt is logged with `.publicValue` privacy (deterministic content,
// no PII) so player bug reports of "I got that hard puzzle" can be reproduced.
// Daily fetches must NOT emit a salt log (no salt involved).

import Foundation
import Testing
 import SudokuPersistence
import SudokuEngine
import Telemetry
import SudokuKitTesting
import TelemetryTesting

@Suite("PuzzleStore — salt logging")
struct PuzzleStoreSaltLoggingTests {

    @Test func practiceSaltLoggedPublic() async throws {
        let logger = FakeLogger()
        // Fixed salt source so the assertion is deterministic.
        let salt: UInt64 = 0xDEAD_BEEF_CAFE_BABE
        let store = PuzzleStore(
            generator: FakeGenerator(),
            saltSource: PracticeSalt(source: { salt }),
            logger: logger
        )
        _ = try await store.fetchPracticePool(difficulty: .easy)
        await logger.settle()
        let entries = await logger.entries
        let saltEntries = entries.filter { $0.message.contains("PracticeSalt") }
        try #require(saltEntries.count == 1)
        let entry = saltEntries[0]
        #expect(entry.privacy == .publicValue)
        #expect(entry.level == .info)
        #expect(entry.message.contains("DEADBEEFCAFEBABE"))
        #expect(entry.message.contains("difficulty=easy"))
    }

    @Test func dailyDoesNotLogSalt() async throws {
        let logger = FakeLogger()
        let store = PuzzleStore(
            generator: FakeGenerator(),
            logger: logger
        )
        _ = try await store.fetchDailyTrio(date: Date(timeIntervalSince1970: 1_780_272_000))
        await logger.settle()
        let entries = await logger.entries
        let saltEntries = entries.filter { $0.message.contains("PracticeSalt") }
        #expect(saltEntries.isEmpty)
    }

    @Test func practiceSaltSourceIsInjectable() async throws {
        // Deterministic increasing source proves injection wins over default.
        let counter = Counter()
        let store = PuzzleStore(
            generator: FakeGenerator(),
            saltSource: PracticeSalt(source: { counter.next() })
        )
        let first = try await store.fetchPracticePool(difficulty: .medium)
        let second = try await store.fetchPracticePool(difficulty: .medium)
        // Salt 1 then 2 → ids must end in distinct base32 bodies.
        #expect(first.identity.puzzleId != second.identity.puzzleId)
    }

    private final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var value: UInt64 = 0
        func next() -> UInt64 {
            lock.lock(); defer { lock.unlock() }
            value += 1
            return value
        }
    }
}
