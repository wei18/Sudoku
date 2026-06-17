// GameSessionClearAndStartedAtTests — regressions for Wave-2 BLOCKERs.
//
// Covers:
//   - B1: GameSession.clearDigit records a `.clearDigit` undo move and
//         the cleared cell survives `restore(from:)` round-trip.
//   - B4: `startedAt` is captured on first `.start()`, threaded through
//         the snapshot, and preserved across `restore(...)`.
//
// Per impl-notes meetings/2026-05-20_wave-2-blocker-fixes.impl-notes.md.

import Foundation
import SudokuEngine
import Testing
 import SudokuGameState

@Suite("GameSession — clearDigit + startedAt")
struct GameSessionClearAndStartedAtTests {

    // MARK: - B1: clearDigit

    @Test("clearDigit clears the cell and records a .clearDigit undo move")
    func clearDigitWritesAndRecords() async throws {
        let session = GameSession(puzzle: TestPuzzles.simple)
        try await session.start()
        try await session.placeDigit(row: 0, col: 1, digit: 5)
        try await session.clearDigit(row: 0, col: 1)

        let cell = await session.currentBoard.digit(atRow: 0, column: 1)
        #expect(cell == nil)

        let undoMoves = await session.undoStack.undoStack
        guard case .clearDigit(let row, let col, let previous) = undoMoves.last else {
            Issue.record("expected last undo to be .clearDigit, got \(String(describing: undoMoves.last))")
            return
        }
        #expect(row == 0 && col == 1 && previous == 5)
    }

    @Test("clearDigit then undo restores the prior digit")
    func clearThenUndoRestoresDigit() async throws {
        let session = GameSession(puzzle: TestPuzzles.simple)
        try await session.start()
        try await session.placeDigit(row: 0, col: 1, digit: 5)
        try await session.clearDigit(row: 0, col: 1)
        try await session.undo()

        let cell = await session.currentBoard.digit(atRow: 0, column: 1)
        #expect(cell == 5, "undo of clear must restore the 5")
    }

    @Test("clearDigit then redo re-clears the cell")
    func clearThenRedoReclears() async throws {
        let session = GameSession(puzzle: TestPuzzles.simple)
        try await session.start()
        try await session.placeDigit(row: 0, col: 1, digit: 5)
        try await session.clearDigit(row: 0, col: 1)
        try await session.undo()
        try await session.redo()

        let cell = await session.currentBoard.digit(atRow: 0, column: 1)
        #expect(cell == nil, "redo of clear must re-clear")
    }

    @Test("clearDigit on an empty cell is a no-op (no move pushed)")
    func clearEmptyCellIsNoOp() async throws {
        let session = GameSession(puzzle: TestPuzzles.simple)
        try await session.start()
        let beforeStack = await session.undoStack.undoStack
        try await session.clearDigit(row: 0, col: 1)
        let afterStack = await session.undoStack.undoStack
        #expect(afterStack.count == beforeStack.count, "empty-cell clear must not push a move")
    }

    @Test("clearDigit on a clue cell throws cellImmutable")
    func clearOnGivenThrows() async throws {
        // TestPuzzles.simple has a clue at (0,0).
        let session = GameSession(puzzle: TestPuzzles.simple)
        try await session.start()
        await #expect(throws: GameSessionError.self) {
            try await session.clearDigit(row: 0, col: 0)
        }
    }

    @Test("clearDigit while not playing throws invalidStateForAction")
    func clearWhenNotPlayingThrows() async {
        let session = GameSession(puzzle: TestPuzzles.simple) // idle
        await #expect(throws: GameSessionError.self) {
            try await session.clearDigit(row: 0, col: 1)
        }
    }

    @Test("Snapshot → restore round-trips a .clearDigit on the undo stack")
    func clearSurvivesSnapshotRestore() async throws {
        let session = GameSession(puzzle: TestPuzzles.simple)
        try await session.start()
        try await session.placeDigit(row: 0, col: 1, digit: 5)
        try await session.clearDigit(row: 0, col: 1)
        let snap = await session.snapshot()

        let restored = await GameSession.restore(from: snap)
        // A restored in-progress session is `.paused` (frozen clock); the
        // player resumes before mutating. See GameSession.applySnapshot.
        try await restored.resume()
        let cell = await restored.currentBoard.digit(atRow: 0, column: 1)
        #expect(cell == nil)
        try await restored.undo()
        let restoredCell = await restored.currentBoard.digit(atRow: 0, column: 1)
        #expect(restoredCell == 5)
    }

    // MARK: - B4: startedAt

    @Test("startedAt is captured on first .start() and not overwritten by pause/resume")
    func startedAtCapturedOnce() async throws {
        let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)
        let session = GameSession(
            puzzle: TestPuzzles.simple,
            now: { fixedDate }
        )
        var startedAt = await session.startedAt
        #expect(startedAt == nil, "nil before .start()")

        try await session.start()
        startedAt = await session.startedAt
        #expect(startedAt == fixedDate)

        // pause/resume must NOT overwrite startedAt even if the wall clock
        // would now return a different value.
        // (We can't inject a different `now()` post-init, but the resume
        // path takes a no-arg branch — only `start()` writes `startedAt`,
        // and it's guarded by `if startedAt == nil`.)
        try await session.pause()
        try await session.resume()
        startedAt = await session.startedAt
        #expect(startedAt == fixedDate, "startedAt must remain the original")
    }

    @Test("startedAt threads through snapshot and round-trips through restore")
    func startedAtThreadsThroughSnapshotAndRestore() async throws {
        let originalDate = Date(timeIntervalSince1970: 1_700_000_000)
        let session = GameSession(
            puzzle: TestPuzzles.simple,
            now: { originalDate }
        )
        try await session.start()
        try await session.placeDigit(row: 0, col: 1, digit: 5)
        let snap = await session.snapshot()
        #expect(snap.startedAt == originalDate)

        // Restore with a DIFFERENT wall clock; the restored startedAt must
        // be the snapshot's value, not the new clock's value.
        let differentDate = Date(timeIntervalSince1970: 9_999_999_999)
        let restored = await GameSession.restore(from: snap, now: { differentDate })
        let restoredStartedAt = await restored.startedAt
        #expect(restoredStartedAt == originalDate)
        // Snapshot from the restored session also carries the original.
        let restoredSnap = await restored.snapshot()
        #expect(restoredSnap.startedAt == originalDate)
    }
}
