// StoreLiveTests — Phase 6.2 (plan.md §6.2, design.md §How.4.1 / §How.7.3).
//
// Use the live `PuzzleStore` actor with an injected `FakeGenerator` so the
// tests run in milliseconds (vs. multi-second real generator) and so we can
// assert on call ordering / error propagation. The real `PuzzleGenerator` is
// already covered by SudokuEngineTests phase 2.7.

import Foundation
import Testing
@testable import PuzzleStore
import SudokuEngine
import TelemetryTesting

@Suite("PuzzleStore live")
struct PuzzleStoreLiveTests {

    private static let referenceDate: Date = Date(timeIntervalSince1970: 1_780_327_800) // 2026-06-01T15:30:00Z

    @Test func dailyTrioDeterministicAcrossCalls() async throws {
        let generator = FakeGenerator()
        let store = PuzzleStore(generator: generator)
        let first = try await store.fetchDailyTrio(date: Self.referenceDate)
        let second = try await store.fetchDailyTrio(date: Self.referenceDate)
        #expect(first == second)
        #expect(first.count == 3)
    }

    @Test func dailyTrioCoversAllThreeDifficulties() async throws {
        let store = PuzzleStore(generator: FakeGenerator())
        let trio = try await store.fetchDailyTrio(date: Self.referenceDate)
        #expect(trio.map(\.puzzle.difficulty) == [.easy, .medium, .hard])
        #expect(trio.map(\.identity.kind) == [.daily, .daily, .daily])
    }

    @Test func dailyIdentityFormatMatchesUTCDate() async throws {
        let store = PuzzleStore(generator: FakeGenerator())
        let trio = try await store.fetchDailyTrio(date: Self.referenceDate)
        #expect(trio[0].identity.puzzleId == "2026-06-01-easy")
        #expect(trio[1].identity.puzzleId == "2026-06-01-medium")
        #expect(trio[2].identity.puzzleId == "2026-06-01-hard")
    }

    @Test func practiceDrawsDistinctPuzzles() async throws {
        let store = PuzzleStore(generator: FakeGenerator())
        let first = try await store.fetchPracticePool(difficulty: .easy)
        let second = try await store.fetchPracticePool(difficulty: .easy)
        // Distinct salts overwhelmingly likely → distinct ids.
        #expect(first.identity.puzzleId != second.identity.puzzleId)
        #expect(first.identity.kind == .practice)
        #expect(first.identity.difficulty == .easy)
    }

    @Test func generatorExhaustionPropagates() async throws {
        let generator = FakeGenerator()
        generator.enqueueNext(.failure(.exhausted))
        let store = PuzzleStore(generator: generator)
        await #expect(throws: PuzzleStoreError.self) {
            _ = try await store.fetchPracticePool(difficulty: .hard)
        }
    }

    @Test func puzzleForPuzzleIdDailyShape() async throws {
        let store = PuzzleStore(generator: FakeGenerator())
        let trio = try await store.fetchDailyTrio(date: Self.referenceDate)
        let reloaded = try await store.puzzle(for: "2026-06-01-easy")
        // Same seed derivation → fake returns the same canned puzzle.
        #expect(reloaded == trio[0].puzzle)
    }

    @Test func puzzleForPuzzleIdPracticeShape() async throws {
        let store = PuzzleStore(generator: FakeGenerator())
        let drawn = try await store.fetchPracticePool(difficulty: .medium)
        let reloaded = try await store.puzzle(for: drawn.identity.puzzleId)
        #expect(reloaded == drawn.puzzle)
    }

    @Test func puzzleForPuzzleIdMalformedThrows() async throws {
        let store = PuzzleStore(generator: FakeGenerator())
        await #expect(throws: PuzzleStoreError.malformedPuzzleId("not-a-puzzle-id")) {
            _ = try await store.puzzle(for: "not-a-puzzle-id")
        }
    }

    @Test func puzzleForPuzzleIdUnknownDifficultyThrows() async throws {
        let store = PuzzleStore(generator: FakeGenerator())
        await #expect(throws: PuzzleStoreError.unknownDifficulty("evil")) {
            _ = try await store.puzzle(for: "2026-06-01-evil")
        }
    }
}
