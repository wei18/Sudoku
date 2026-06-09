// swiftlint:disable identifier_name
// `r`, `c`, `s` are idiomatic for tight test code (row / col / session).
//
// Snapshot / restore persistence-foundation tests (#455 step 1).

import Foundation
import Testing
@testable import MinesweeperGameState
import MinesweeperEngine

// MARK: - Fake clock

private final class FakeClock: MonotonicClock, @unchecked Sendable {
    private let lock = NSLock()
    private var _now: TimeInterval
    init(_ start: TimeInterval = 0) { _now = start }
    var now: TimeInterval { lock.lock(); defer { lock.unlock() }; return _now }
    func advance(by seconds: TimeInterval) { lock.lock(); _now += seconds; lock.unlock() }
}

// MARK: - Restore (#455)

@Suite struct MinesweeperSessionRestoreTests {

    /// snapshot → JSON → restore → snapshot is Equatable to the original.
    @Test func jsonRoundTripPreservesSnapshot() async throws {
        let clock = FakeClock()
        let session = MinesweeperSession(difficulty: .beginner, seed: 7, clock: clock)
        _ = try await session.reveal(row: 4, col: 4)
        // Flag a hidden cell so the captured state has a flag too.
        let snapAfterReveal = await session.snapshot()
        var flagged = false
        outer: for r in 0..<snapAfterReveal.rows {
            for c in 0..<snapAfterReveal.columns
            where snapAfterReveal.cell(row: r, col: c).state == .hidden {
                _ = try await session.toggleFlag(row: r, col: c)
                flagged = true
                break outer
            }
        }
        #expect(flagged)
        clock.advance(by: 30)
        _ = await session.pause()   // freeze elapsed at a known value
        let original = await session.snapshot()
        #expect(original.flagCount == 1)

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(MinesweeperSessionSnapshot.self, from: data)
        #expect(decoded == original)

        let restored = await MinesweeperSession.restore(from: decoded, clock: FakeClock())
        let restoredSnap = await restored.snapshot()
        #expect(restoredSnap == original)
    }

    /// Restored mine layout matches a fresh same-seed session replaying the
    /// same first reveal (mines are deferred to first-click) — seed determines
    /// the board.
    @Test func restoredBoardMatchesFreshSeedReconstruction() async throws {
        let original = MinesweeperSession(difficulty: .beginner, seed: 99, clock: FakeClock())
        _ = try await original.reveal(row: 4, col: 4)
        let originalSnap = await original.snapshot()

        let restored = await MinesweeperSession.restore(from: originalSnap, clock: FakeClock())
        let restoredSnap = await restored.snapshot()

        // Fresh session, same seed/difficulty, same first reveal.
        let fresh = MinesweeperSession(difficulty: .beginner, seed: 99, clock: FakeClock())
        _ = try await fresh.reveal(row: 4, col: 4)
        let freshSnap = await fresh.snapshot()

        // Mine positions + neighbor counts identical across all three — the
        // restored board equals both the original and a fresh seed-rebuild.
        let mines = { (cells: [Cell]) in cells.map { [$0.isMine ? 1 : 0, $0.neighborMineCount] } }
        #expect(mines(restoredSnap.cells) == mines(freshSnap.cells))
        #expect(mines(restoredSnap.cells) == mines(originalSnap.cells))
        #expect(restoredSnap.cells == originalSnap.cells)
    }

    /// Restored elapsed time is frozen at the snapshot's value — it does not
    /// jump even as the injected clock advances after restore.
    @Test func restoredClockIsFrozenAtSnapshotValue() async throws {
        let clock = FakeClock()
        let session = MinesweeperSession(difficulty: .beginner, seed: 5, clock: clock)
        _ = try await session.reveal(row: 4, col: 4)
        clock.advance(by: 42)
        _ = await session.pause()
        let snap = await session.snapshot()
        #expect(snap.elapsedSeconds == 42)

        let restoreClock = FakeClock()
        let restored = await MinesweeperSession.restore(from: snap, clock: restoreClock)
        restoreClock.advance(by: 100)   // clock moves; frozen elapsed must not
        let restoredSnap = await restored.snapshot()
        #expect(restoredSnap.elapsedSeconds == 42)
        // A restored mid-play (.playing) session is parked at .paused.
        #expect(restoredSnap.status == .paused || restoredSnap.status == snap.status)
    }
}

// swiftlint:enable identifier_name
