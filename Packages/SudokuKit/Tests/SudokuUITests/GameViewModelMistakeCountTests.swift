// GameViewModelMistakeCountTests — SDD-003 Epic 3 (AC-3.4).
//
// Verifies that the `mistakeCount` the player had when they left is
// correctly surfaced in `GameViewModel` after the BoardLoaderView.load()
// path restores it from the persisted snapshot.

import Foundation
import GameState
import Persistence
import PersistenceTesting
import PuzzleStore
import SudokuEngine
import Testing
@testable import SudokuUI

@MainActor
@Suite("GameViewModel — mistakeCount restored on resume (#SDD-003 AC-3.4)")
struct GameViewModelMistakeCountTests {

    /// Build a snapshot using the wide-open fixture (only one clue, 80 free
    /// cells) so conflict placements are testable. Sets `mistakeCount` to
    /// the desired value directly on the snapshot (bypassing the session
    /// conflict path — the goal here is testing the restore path, not
    /// conflict detection, which is already tested in SudokuCoreKit).
    private func makeSnapshotWithMistakes(mistakeCount: Int) async throws -> GameSessionSnapshot {
        let puzzle = SudokuKitTestPuzzles.manyFreeCells
        let clock = SettableClock2()
        let session = GameSession(puzzle: puzzle, clock: clock)
        try await session.start()
        clock.set(75)
        // Place digit 2 at (0,1) — no conflict with the clue '1' at (0,0).
        try await session.placeDigit(row: 0, col: 1, digit: 2)
        let snap = await session.snapshot()
        return GameSessionSnapshot(
            puzzle: snap.puzzle,
            currentBoard: snap.currentBoard,
            status: snap.status,
            elapsedSeconds: snap.elapsedSeconds,
            undoMoves: snap.undoMoves,
            redoMoves: snap.redoMoves,
            notes: snap.notes,
            startedAt: snap.startedAt,
            mistakeCount: mistakeCount
        )
    }

    @Test("mistakeCount from snapshot is passed into GameViewModel initialMistakeCount")
    func mistakeCountPassedThroughBoardLoaderPath() async throws {
        let snapshot = try await makeSnapshotWithMistakes(mistakeCount: 3)

        // === Mirror of BoardLoaderView.load() ===
        let resumeClock = SettableClock2()
        let session = await GameSession.restore(from: snapshot, clock: resumeClock)
        let viewModel = GameViewModel(
            identity: .practice(salt: 999, difficulty: .easy),
            session: session,
            initialBoard: snapshot.currentBoard,
            initialNotes: snapshot.notes,
            initialStatus: snapshot.status,
            initialElapsedSeconds: snapshot.elapsedSeconds,
            initialMistakeCount: snapshot.mistakeCount,
            persistence: PersistenceTesting.FakePersistence(),
            saveDebounceNanos: 0
        )
        await viewModel.startOrResume()
        // =========================================

        #expect(viewModel.mistakeCount == 3)
    }

    @Test("mistakeCount increments on a conflicting digit placement via the live session")
    func mistakeCountIncrementsOnConflict() async throws {
        let snapshot = try await makeSnapshotWithMistakes(mistakeCount: 0)

        let clock = SettableClock2()
        let session = await GameSession.restore(from: snapshot, clock: clock)
        let viewModel = GameViewModel(
            identity: .practice(salt: 999, difficulty: .easy),
            session: session,
            initialBoard: snapshot.currentBoard,
            initialNotes: snapshot.notes,
            initialStatus: snapshot.status,
            initialElapsedSeconds: snapshot.elapsedSeconds,
            initialMistakeCount: snapshot.mistakeCount,
            persistence: PersistenceTesting.FakePersistence(),
            saveDebounceNanos: 0
        )
        await viewModel.startOrResume()
        #expect(viewModel.mistakeCount == 0)

        // The snapshot has digit 2 at (0,1). Placing 2 at (0,2) creates a
        // row conflict with the 2 already at (0,1) → mistake. Both cells
        // are non-given (manyFreeCells only has clue '1' at (0,0)).
        await viewModel.placeDigit(2, at: GridCoordinate(row: 0, column: 2))
        #expect(viewModel.mistakeCount == 1)
    }

    @Test("resync after placeDigit reflects the session mistakeCount")
    func resyncReflectsMistakeCount() async throws {
        let snapshot = try await makeSnapshotWithMistakes(mistakeCount: 2)

        let clock = SettableClock2()
        let session = await GameSession.restore(from: snapshot, clock: clock)
        let viewModel = GameViewModel(
            identity: .practice(salt: 999, difficulty: .easy),
            session: session,
            initialBoard: snapshot.currentBoard,
            initialNotes: snapshot.notes,
            initialStatus: snapshot.status,
            initialElapsedSeconds: snapshot.elapsedSeconds,
            initialMistakeCount: snapshot.mistakeCount,
            persistence: PersistenceTesting.FakePersistence(),
            saveDebounceNanos: 0
        )
        await viewModel.startOrResume()
        // Starts at 2 (restored from snapshot).
        #expect(viewModel.mistakeCount == 2)
        // Add another row conflict: place 2 at (0,2) — conflicts with 2 at (0,1).
        await viewModel.placeDigit(2, at: GridCoordinate(row: 0, column: 2))
        #expect(viewModel.mistakeCount == 3)
    }
}

/// Test-only deterministic monotonic clock — avoids name clash with the
/// identical helper in `ResumeRestoreViewModelTests.swift` (same target).
private final class SettableClock2: MonotonicClock, @unchecked Sendable {
    private let lock = NSLock()
    private var value: TimeInterval = 0
    var now: TimeInterval { lock.withLock { value } }
    func set(_ seconds: TimeInterval) { lock.withLock { value = seconds } }
}

/// Minimal puzzle fixture with only one given cell ('1' at (0,0)) and 80
/// free cells. Suitable for VM-level conflict tests where multiple non-given
/// cells must be writable.
private enum SudokuKitTestPuzzles {
    /// Intentionally NOT a valid Sudoku solution (row-shifted Latin square —
    /// columns/boxes repeat digits). These tests exercise conflict detection,
    /// not completion; `Puzzle` performs no solution validation. Replace with
    /// a real solution if `Puzzle` ever gains stricter validation.
    static let manyFreeCells: Puzzle = {
        let cluesEncoded = "1" + String(repeating: ".", count: 80)
        // swiftlint:disable:next force_try
        let clues = try! Board(clues: cluesEncoded)
        var solution = Board()
        for index in 0..<Board.cellCount {
            // swiftlint:disable:next force_try
            try! solution.setDigit(((index % 9) + 1), atIndex: index)
        }
        return Puzzle(
            clues: clues,
            solution: solution,
            difficulty: .easy,
            generatorVersion: .v1,
            seed: 0
        )
    }()
}
