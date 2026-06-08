// ResumeRestoreViewModelTests — issue #413.
//
// Replicates `BoardLoaderView.load()` exactly: given a persisted in-progress
// snapshot (board with player progress + elapsed > 0), restore a GameSession,
// build the GameViewModel with the snapshot's initial mirrors, then
// `startOrResume()`. The observable mirrors the BoardView renders
// (`board`, `elapsedSeconds`, `status`) must reflect the SAVED game, not a
// fresh seed, and the timer must keep ticking after resume.
//
// Covers BOTH daily and practice identities (BoardLoaderView re-derives mode
// from the puzzleId string, so both formats flow through this same path).

import Foundation
import GameState
import Persistence
import PersistenceTesting
import PuzzleStore
import SudokuEngine
import Testing
@testable import SudokuUI

@MainActor
@Suite("GameViewModel — resume restores board + elapsed (#413)")
struct ResumeRestoreViewModelTests {

    /// Build the in-progress snapshot a mid-play autosave would persist:
    /// player digit placed at (0,0), elapsed accrued, status `.playing`.
    private func makeInProgressSnapshot(elapsedSeconds: Int) async throws -> GameSessionSnapshot {
        let puzzle = PuzzleFixtures.latinSquarePuzzle()
        let clock = SettableClock()
        let session = GameSession(puzzle: puzzle, clock: clock)
        try await session.start()
        clock.set(TimeInterval(elapsedSeconds))
        // (0,0) is the only empty cell; solution is 1. Place a non-solution
        // digit so the board carries progress but stays in-progress.
        try await session.placeDigit(row: 0, col: 0, digit: 2)
        let snapshot = await session.snapshot()
        #expect(snapshot.status == .playing)
        #expect(snapshot.elapsedSeconds == elapsedSeconds)
        return snapshot
    }

    /// Drive BoardLoaderView.load()'s construction + startOrResume for a given
    /// identity and assert the UI mirrors reflect the saved game.
    private func assertResumeRestoresUI(identity: PuzzleIdentity) async throws {
        let snapshot = try await makeInProgressSnapshot(elapsedSeconds: 137)

        // === Mirror of BoardLoaderView.load() ===
        let resumeClock = SettableClock()
        let session = await GameSession.restore(from: snapshot, clock: resumeClock)
        let viewModel = GameViewModel(
            identity: identity,
            session: session,
            initialBoard: snapshot.currentBoard,
            initialNotes: snapshot.notes,
            initialStatus: snapshot.status,
            initialElapsedSeconds: snapshot.elapsedSeconds,
            persistence: PersistenceTesting.FakePersistence(),
            saveDebounceNanos: 0
        )
        await viewModel.startOrResume()
        // =========================================

        // The board the user left off on — not a fresh puzzle.
        #expect(viewModel.board == snapshot.currentBoard)
        #expect(viewModel.board.digit(atRow: 0, column: 0) == 2)
        // Elapsed reflects the saved value (NOT reset to 0).
        #expect(viewModel.elapsedSeconds == 137)
        #expect(viewModel.status == .playing)

        // Timer keeps ticking after resume.
        resumeClock.set(10)
        await viewModel.refreshElapsed()
        #expect(viewModel.elapsedSeconds == 147)
    }

    @Test func dailyResumeRestoresUIMirrors() async throws {
        try await assertResumeRestoresUI(
            identity: .daily(date: Date(timeIntervalSince1970: 1_780_272_000), difficulty: .easy)
        )
    }

    @Test func practiceResumeRestoresUIMirrors() async throws {
        try await assertResumeRestoresUI(
            identity: .practice(salt: 413, difficulty: .easy)
        )
    }
}

/// Test-only deterministic monotonic clock.
private final class SettableClock: MonotonicClock, @unchecked Sendable {
    private let lock = NSLock()
    private var value: TimeInterval = 0
    var now: TimeInterval { lock.withLock { value } }
    func set(_ seconds: TimeInterval) { lock.withLock { value = seconds } }
}
