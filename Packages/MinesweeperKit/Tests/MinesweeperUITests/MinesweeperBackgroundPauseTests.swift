// MinesweeperBackgroundPauseTests — regression net for issue #539 (MS parity).
//
// Mirrors GameViewModelBackgroundPauseTests in SudokuKit: verifies that calling
// viewModel.pause() (what MinesweeperBoardView now does on scenePhase != .active)
// freezes the elapsed clock and that the game is paused on return. Also covers
// the multi-cycle over-accumulation regression.
//
// NOTE: MinesweeperSession starts the clock on the first reveal action (idle →
// playing), so tests that check elapsed must reveal a cell first.

import Foundation
import Testing
import MinesweeperEngine
import MinesweeperGameState
@testable import MinesweeperUI

@MainActor
@Suite("MinesweeperGameViewModel — background auto-pause freezes timer (#539)")
struct MinesweeperBackgroundPauseTests {

    // MARK: - Helpers

    /// Build a playing MS VM with a controllable clock, then make a single
    /// safe reveal to transition idle → playing and start the clock.
    private func makePlayingViewModel(
        clock: SettableMSClock539
    ) async -> MinesweeperGameViewModel {
        let session = MinesweeperSession(difficulty: .beginner, seed: 7, clock: clock)
        let viewModel = MinesweeperGameViewModel(session: session)
        // First reveal starts the clock; (4,4) is the safe opening used in
        // other MS tests (MinesweeperPersistHooksTests).
        await viewModel.reveal(row: 4, col: 4)
        return viewModel
    }

    // MARK: - Core contract: pause() freezes the clock

    @Test("elapsed does not advance while paused by background transition")
    func elapsedFreezesOnBackgroundPause() async {
        let clock = SettableMSClock539()
        let viewModel = await makePlayingViewModel(clock: clock)

        // Play for 30 s (clock at 30, started at 0 relative to first reveal).
        clock.set(30)
        await viewModel.refresh()
        #expect(viewModel.elapsedSeconds == 30)

        // Simulate scenePhase → non-active.
        await viewModel.pause()
        #expect(viewModel.isPaused)
        #expect(viewModel.elapsedSeconds == 30)

        // Advance 60 s of background time — must not count.
        clock.set(90)
        await viewModel.refresh()   // refresh is a no-op while paused; elapsed stays frozen
        #expect(
            viewModel.elapsedSeconds == 30,
            "background time must not accrue when paused; got \(viewModel.elapsedSeconds)"
        )
    }

    @Test("game is in .paused state after background-triggered pause()")
    func stateIsPausedAfterBackgroundPause() async {
        let clock = SettableMSClock539()
        let viewModel = await makePlayingViewModel(clock: clock)
        clock.set(10)
        await viewModel.pause()

        #expect(viewModel.isPaused)
        #expect(viewModel.status == .paused)
    }

    @Test("pause() is idempotent when already paused (scenePhase fires .inactive then .background)")
    func doubleBackgroundPauseIsIdempotent() async {
        let clock = SettableMSClock539()
        let viewModel = await makePlayingViewModel(clock: clock)

        clock.set(20)
        await viewModel.pause()
        let elapsedAfterFirst = viewModel.elapsedSeconds

        clock.set(50)
        await viewModel.pause()   // second call — no-op; already paused
        #expect(viewModel.status == .paused)
        #expect(
            viewModel.elapsedSeconds == elapsedAfterFirst,
            "second pause() must not re-freeze and add background time"
        )
    }

    // MARK: - Over-accumulation regression

    @Test("elapsed is correct and monotonic across multiple pause/resume cycles")
    func elapsedIsCorrectAcrossMultipleCycles() async {
        let clock = SettableMSClock539()
        let viewModel = await makePlayingViewModel(clock: clock)

        // Cycle 1: 30 s play → background → 60 s → foreground → 10 s more
        clock.set(30)
        await viewModel.pause()
        #expect(viewModel.elapsedSeconds == 30)

        clock.set(90)
        await viewModel.resume()

        clock.set(100)
        await viewModel.refresh()
        #expect(
            viewModel.elapsedSeconds == 40,
            "cycle 1: 30 s + 10 s = 40 s; got \(viewModel.elapsedSeconds)"
        )

        // Cycle 2: background again → 120 s → foreground → 5 s more
        await viewModel.pause()
        #expect(viewModel.elapsedSeconds == 40)

        clock.set(220)
        await viewModel.resume()

        clock.set(225)
        await viewModel.refresh()
        #expect(
            viewModel.elapsedSeconds == 45,
            "cycle 2: 40 s + 5 s = 45 s; got \(viewModel.elapsedSeconds)"
        )
    }
}

// MARK: - File-private test helpers

private final class SettableMSClock539: MonotonicClock, @unchecked Sendable {
    private let lock = NSLock()
    private var value: TimeInterval = 0
    var now: TimeInterval { lock.withLock { value } }
    func set(_ seconds: TimeInterval) { lock.withLock { value = seconds } }
}
