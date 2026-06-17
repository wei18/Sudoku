// ResumeRestoreRoundtripTests — issue #413.
//
// End-to-end reproduction of the Home → Resume defect: an in-progress game
// saved mid-play must, when resumed via the same path the app uses
// (`latestInProgress()` → `loadOrCreate(puzzleId, mode, difficulty)` →
// `GameSession.restore` → `startOrResume`), come back with (a) the SAME
// in-progress board and (b) an elapsed time that reflects the saved value
// AND keeps ticking after resume.
//
// The mode/difficulty passed to `loadOrCreate` are derived from the
// puzzleId STRING exactly as `BoardLoaderView.identity(from:)` does it —
// because `RootViewModel.resumeTapped()` forwards only the puzzleId, not
// the saved mode. Covers BOTH daily and practice ids.

import Foundation
import Testing
import SudokuGameState
import SudokuEngine
import Telemetry
import PersistenceTesting
import TelemetryTesting
@testable import Persistence

@Suite("Persistence — resume restores board + elapsed (#413)")
struct ResumeRestoreRoundtripTests {

    /// Mirror of `BoardLoaderView.identity(from:)` mode/difficulty derivation
    /// (the resume path re-derives these from the puzzleId string).
    private func derivedMode(from puzzleId: String) -> Mode {
        puzzleId.hasPrefix("practice-") ? .practice : .daily
    }

    private func derivedDifficulty(from puzzleId: String) -> Difficulty {
        let raw = puzzleId.split(separator: "-").last.map(String.init) ?? Difficulty.easy.rawValue
        return Difficulty(rawValue: raw) ?? .easy
    }

    private func makeStore(
        clock: @escaping @Sendable () -> Date
    ) async -> (SavedGameStore, FakePrivateCKGateway) {
        let gateway = FakePrivateCKGateway()
        let puzzle = PuzzleFixtures.latinSquarePuzzle()
        let store = SavedGameStore(
            gateway: gateway,
            telemetry: Telemetry(sinks: [RecordingSink()]),
            puzzleLoader: { _ in puzzle },
            clock: clock
        )
        return (store, gateway)
    }

    /// Drive the full Home → Resume path for a given puzzleId and assert the
    /// in-progress board + elapsed survive the round-trip.
    private func assertResumeRoundtrip(
        puzzleId: String,
        savedMode: Mode
    ) async throws {
        // Fixed "today" so daily ids are never filtered as stale.
        let today = Date(timeIntervalSince1970: 1_780_272_000) // 2026-06-01 UTC
        let (store, _) = await makeStore(clock: { today })

        // 1) Play an in-progress game: place a digit, accrue elapsed time.
        let puzzle = PuzzleFixtures.latinSquarePuzzle()
        let sessionClock = FakeMonotonicClock()
        let session = GameSession(puzzle: puzzle, clock: sessionClock)
        try await session.start()
        sessionClock.set(137) // 2m17s elapsed
        // (0,0) is the puzzle's only empty cell; solution there is 1. Place a
        // NON-solution digit (2) so the board has player progress but stays
        // in-progress (placing 1 would complete + freeze the game).
        try await session.placeDigit(row: 0, col: 0, digit: 2)
        let liveSnapshot = await session.snapshot()
        #expect(liveSnapshot.status == .playing)
        #expect(liveSnapshot.elapsedSeconds == 137)

        // 2) Autosave persists the live (.playing) snapshot under the saved mode.
        try await store.save(
            liveSnapshot,
            puzzleId: puzzleId,
            mode: savedMode,
            difficulty: .easy
        )

        // 3) Home → Resume: pick the candidate, then load via the puzzleId
        //    string (mode/difficulty re-derived, as BoardLoaderView does).
        let candidate = try #require(try await store.latestInProgress())
        #expect(candidate.puzzleId == puzzleId)

        let resumedSnapshot = try await store.loadOrCreate(
            puzzleId: candidate.puzzleId,
            mode: derivedMode(from: candidate.puzzleId),
            difficulty: derivedDifficulty(from: candidate.puzzleId)
        )

        // Board + elapsed must match what was saved (NOT a fresh seed).
        #expect(resumedSnapshot.currentBoard == liveSnapshot.currentBoard)
        #expect(resumedSnapshot.currentBoard.digit(atRow: 0, column: 0) == 2)
        #expect(resumedSnapshot.elapsedSeconds == 137)

        // 4) Restore + startOrResume re-arms the clock and keeps ticking.
        let resumeClock = FakeMonotonicClock()
        let restored = await GameSession.restore(from: resumedSnapshot, clock: resumeClock)
        #expect(await restored.elapsedSeconds == 137)   // frozen at saved value
        try await restored.resume()                      // .paused → .playing
        resumeClock.set(10)                              // 10s pass after resume
        #expect(await restored.elapsedSeconds == 147)    // saved + new span
        #expect(await restored.currentBoard.digit(atRow: 0, column: 0) == 2)
    }

    @Test func dailyResumeRestoresBoardAndElapsed() async throws {
        try await assertResumeRoundtrip(
            puzzleId: "2026-06-01-easy",
            savedMode: .daily
        )
    }

    @Test func practiceResumeRestoresBoardAndElapsed() async throws {
        try await assertResumeRoundtrip(
            puzzleId: "practice-ABC-easy",
            savedMode: .practice
        )
    }
}

/// Test-only deterministic clock (mirrors GameStateTests' helper, which is
/// private to that target). Lock-protected so `now` is `nonisolated`.
private final class FakeMonotonicClock: MonotonicClock, @unchecked Sendable {
    private let lock = NSLock()
    private var value: TimeInterval = 0
    init(start: TimeInterval = 0) { self.value = start }
    var now: TimeInterval { lock.withLock { value } }
    func set(_ seconds: TimeInterval) { lock.withLock { value = seconds } }
}
