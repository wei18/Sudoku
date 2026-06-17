// GameViewModelBackgroundPauseTests — regression net for issue #539.
//
// ROOT CAUSE: BoardView.onChange(of: scenePhase) only called flush() on
// non-active transitions — it never paused the session. The GameSession
// clock uses a running span (runningSince) that keeps ticking even while the
// app is backgrounded, so background time was silently added to elapsedSeconds.
// On a 12 s background the timer advanced +12 s; repeated cycles compounded
// (3:19 → 22:06 was ~18 min of background, not a math bug).
//
// THE FIX: BoardView now calls viewModel.pause() when the phase becomes
// non-active and the game is playing. pause() already calls flush()
// internally, so the save point is preserved.
//
// THESE TESTS drive pause() directly (the BoardView's scenePhase hook
// calls the same code path) and verify:
//   1. elapsed does NOT advance after pause() is called (background-pause)
//   2. state is .paused after the background transition
//   3. multiple pause/resume cycles keep elapsed monotonically correct (no jump)

import Foundation
import SudokuGameState
import Persistence
import PersistenceTesting
import SudokuPersistence
import SudokuEngine
import Testing
@testable import SudokuUI

@MainActor
@Suite("GameViewModel — background auto-pause freezes timer (#539)")
struct GameViewModelBackgroundPauseTests {

    private static let identity = PuzzleIdentity.practice(salt: 539, difficulty: .easy)

    // MARK: - Helpers

    /// Build a live VM with a controllable monotonic clock, started and playing.
    private func makeLiveViewModel(clock: SettableClock539) async -> (GameViewModel, GameSession) {
        let puzzle = PuzzleFixtures.latinSquarePuzzle()
        let session = GameSession(puzzle: puzzle, clock: clock)
        let viewModel = GameViewModel(
            identity: Self.identity,
            session: session,
            initialBoard: puzzle.clues,
            initialStatus: .idle,
            persistence: FakePersistence(),
            saveDebounceNanos: 0
        )
        await viewModel.startOrResume()
        return (viewModel, session)
    }

    // MARK: - Core contract: pause() freezes the clock

    @Test("elapsed does not advance while paused by background transition")
    func elapsedFreezesOnBackgroundPause() async throws {
        let clock = SettableClock539()
        let (viewModel, _) = await makeLiveViewModel(clock: clock)

        // Play for 30 s.
        clock.set(30)
        await viewModel.refreshElapsed()
        #expect(viewModel.elapsedSeconds == 30)

        // Simulate scenePhase → non-active: call pause() as BoardView now does.
        await viewModel.pause()
        #expect(viewModel.status == .paused)
        #expect(viewModel.elapsedSeconds == 30)

        // Advance clock by 60 s (simulating 60 s of background time).
        clock.set(90)

        // Pull elapsed again — must still be 30, not 90.
        await viewModel.refreshElapsed()
        #expect(
            viewModel.elapsedSeconds == 30,
            "background time must not accrue when paused; got \(viewModel.elapsedSeconds)"
        )
    }

    @Test("game is in .paused state after background-triggered pause()")
    func stateIsPausedAfterBackgroundPause() async throws {
        let clock = SettableClock539()
        let (viewModel, _) = await makeLiveViewModel(clock: clock)

        clock.set(10)
        await viewModel.pause()  // what BoardView now calls on non-active

        #expect(viewModel.isPaused)
        #expect(viewModel.status == .paused)
    }

    @Test("pause() is idempotent when already paused (non-active fires twice: .inactive then .background)")
    func doubleBackgroundPauseIsIdempotent() async throws {
        let clock = SettableClock539()
        let (viewModel, _) = await makeLiveViewModel(clock: clock)

        clock.set(20)
        await viewModel.pause()   // .inactive fires first
        let elapsedAfterFirst = viewModel.elapsedSeconds

        clock.set(50)
        await viewModel.pause()   // .background fires next — must be a no-op
        #expect(viewModel.status == .paused)
        #expect(
            viewModel.elapsedSeconds == elapsedAfterFirst,
            "second pause() must not re-freeze and add more background time"
        )
    }

    // MARK: - Over-accumulation regression (#539 secondary symptom)
    //
    // The "3:19 → 22:06" jump was background time accruing because pause() was
    // never called. Repeated pause/resume cycles must keep elapsed monotonically
    // correct with no phantom jumps.

    @Test("elapsed is correct and monotonic across multiple pause/resume cycles")
    func elapsedIsCorrectAcrossMultipleCycles() async throws {
        let clock = SettableClock539()
        let (viewModel, _) = await makeLiveViewModel(clock: clock)

        // Cycle 1: play 30 s, background (pause), 60 s background, foreground (resume), 10 s
        clock.set(30)
        await viewModel.pause()
        #expect(viewModel.elapsedSeconds == 30)

        clock.set(90)             // 60 s background — must not count
        await viewModel.resume()  // foreground

        clock.set(100)            // 10 s of active play after resume
        await viewModel.refreshElapsed()
        #expect(
            viewModel.elapsedSeconds == 40,
            "cycle 1: 30 s play + 10 s play = 40 s; got \(viewModel.elapsedSeconds)"
        )

        // Cycle 2: background again, 120 s background, foreground, 5 s more play
        await viewModel.pause()
        #expect(viewModel.elapsedSeconds == 40)

        clock.set(220)            // 120 s background — must not count
        await viewModel.resume()

        clock.set(225)            // 5 s more play
        await viewModel.refreshElapsed()
        #expect(
            viewModel.elapsedSeconds == 45,
            "cycle 2: 40 s + 5 s = 45 s; got \(viewModel.elapsedSeconds)"
        )
    }
}

// MARK: - Test helpers (file-private; name avoids clash with other test files)

/// Deterministic monotonic clock whose current time can be set from the test.
/// Named with a suffix to avoid redeclaration clashes with other test files
/// in the same module (e.g. SettableClock2 in GameViewModelMistakeCountTests).
private final class SettableClock539: MonotonicClock, @unchecked Sendable {
    private let lock = NSLock()
    private var value: TimeInterval = 0
    var now: TimeInterval { lock.withLock { value } }
    func set(_ seconds: TimeInterval) { lock.withLock { value = seconds } }
}
