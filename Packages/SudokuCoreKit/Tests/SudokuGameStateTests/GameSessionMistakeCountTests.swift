// GameSessionMistakeCountTests — Epic 3 (SDD-003) mistake-count tracking.
//
// A "mistake" is a digit placement that creates a conflict (the placed cell
// immediately appears in errorIndices). The cumulative count must survive
// snapshot → restore so the Resume path sees the same value the player had
// when they left. Correcting a mistake later does NOT decrement the counter
// (the count represents "how many wrong placements did the player make",
// not "how many wrong cells are currently visible").

import Foundation
import SudokuEngine
import Testing
 import SudokuGameState

@Suite("GameSession mistakeCount (#SDD-003 Epic 3)")
struct GameSessionMistakeCountTests {

    // TestPuzzles.simple has clue '1' at (0,0); all other cells are empty.
    // Any digit placed in a non-clue cell that does NOT conflict = correct.
    // Two cells in the same row share row 0; placing the same digit in both
    // creates a conflict on the second placement.

    @Test("mistakeCount starts at zero on a fresh session")
    func freshSessionHasZeroMistakes() async {
        let session = GameSession(puzzle: TestPuzzles.simple)
        let count = await session.mistakeCount
        #expect(count == 0)
    }

    @Test("a non-conflicting placement does not increment mistakeCount")
    func nonConflictingPlacementLeavesCountUnchanged() async throws {
        let session = GameSession(puzzle: TestPuzzles.simple)
        try await session.start()
        // Row 0: clue '1' at col 0. Placing '2' at col 1 conflicts with
        // nothing → not a mistake.
        try await session.placeDigit(row: 0, col: 1, digit: 2)
        let count = await session.mistakeCount
        #expect(count == 0)
    }

    @Test("a conflicting placement increments mistakeCount by 1")
    func conflictingPlacementIncrementsMistakeCount() async throws {
        let session = GameSession(puzzle: TestPuzzles.simple)
        try await session.start()
        // Place '2' at (0,1), then place '2' again at (0,2) → row conflict.
        try await session.placeDigit(row: 0, col: 1, digit: 2)
        try await session.placeDigit(row: 0, col: 2, digit: 2)
        let count = await session.mistakeCount
        #expect(count == 1, "second '2' in the same row is a conflict")
    }

    @Test("multiple distinct conflicting placements accumulate")
    func multipleMistakesAccumulate() async throws {
        let session = GameSession(puzzle: TestPuzzles.simple)
        try await session.start()
        // Row 0: clue '1' at col 0. Place '3' at (0,1), then '3' at (0,2) → conflict (1).
        try await session.placeDigit(row: 0, col: 1, digit: 3)
        try await session.placeDigit(row: 0, col: 2, digit: 3)
        // Then place '4' at (0,3), '4' at (0,4) → another conflict (2).
        try await session.placeDigit(row: 0, col: 3, digit: 4)
        try await session.placeDigit(row: 0, col: 4, digit: 4)
        let count = await session.mistakeCount
        #expect(count == 2)
    }

    @Test("correcting a mistake does NOT decrement mistakeCount")
    func correctingMistakeDoesNotDecrement() async throws {
        let session = GameSession(puzzle: TestPuzzles.simple)
        try await session.start()
        // Create a conflict.
        try await session.placeDigit(row: 0, col: 1, digit: 5)
        try await session.placeDigit(row: 0, col: 2, digit: 5)
        #expect(await session.mistakeCount == 1)
        // Clear the conflicting cell — the row no longer has two '5's.
        try await session.clearDigit(row: 0, col: 2)
        // Counter stays at 1 — past mistakes are not forgiven.
        #expect(await session.mistakeCount == 1)
    }

    @Test("redo of a conflicting move does NOT re-increment mistakeCount")
    func redoDoesNotReincrement() async throws {
        let session = GameSession(puzzle: TestPuzzles.simple)
        try await session.start()
        // Create a conflict (counted once at original placement).
        try await session.placeDigit(row: 0, col: 1, digit: 5)
        try await session.placeDigit(row: 0, col: 2, digit: 5)
        #expect(await session.mistakeCount == 1)
        // Undo keeps the count (never decrements)…
        try await session.undo()
        #expect(await session.mistakeCount == 1)
        // …and redo re-executes an already-counted move: still 1, not 2.
        try await session.redo()
        #expect(await session.mistakeCount == 1)
    }

    @Test("mistakeCount survives snapshot round-trip")
    func mistakeCountRoundTripsInSnapshot() async throws {
        let session = GameSession(puzzle: TestPuzzles.simple)
        try await session.start()
        // Two mistakes.
        try await session.placeDigit(row: 0, col: 1, digit: 6)
        try await session.placeDigit(row: 0, col: 2, digit: 6)
        try await session.placeDigit(row: 0, col: 3, digit: 7)
        try await session.placeDigit(row: 0, col: 4, digit: 7)
        #expect(await session.mistakeCount == 2)

        let snap = await session.snapshot()
        #expect(snap.mistakeCount == 2)

        let restored = await GameSession.restore(from: snap)
        #expect(await restored.mistakeCount == 2)
    }

    @Test("GameSessionSnapshot JSON round-trip preserves mistakeCount")
    func snapshotJsonPreservesMistakeCount() async throws {
        let session = GameSession(puzzle: TestPuzzles.simple)
        try await session.start()
        try await session.placeDigit(row: 0, col: 1, digit: 8)
        try await session.placeDigit(row: 0, col: 2, digit: 8)

        let snap = await session.snapshot()
        let data = try JSONEncoder().encode(snap)
        let decoded = try JSONDecoder().decode(GameSessionSnapshot.self, from: data)
        #expect(decoded.mistakeCount == 1)
    }
}
