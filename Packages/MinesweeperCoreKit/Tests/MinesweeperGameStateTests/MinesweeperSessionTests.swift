// swiftlint:disable identifier_name
// `r`, `c`, `s` are idiomatic for tight test code (row / col / session).

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

// MARK: - Init

@Suite struct MinesweeperSessionInitTests {
    @Test func startsIdleWithNoElapsedTime() async {
        let session = MinesweeperSession(difficulty: .beginner, seed: 1, clock: FakeClock())
        let snap = await session.snapshot()
        #expect(snap.status == .idle)
        #expect(snap.elapsedSeconds == 0)
        #expect(snap.mineCount == 10)
        #expect(snap.flagCount == 0)
        #expect(snap.cells.count == 81)
        #expect(snap.cells.allSatisfy { $0.state == .hidden && !$0.isMine })
    }
}

// MARK: - Reveal

@Suite struct MinesweeperSessionRevealTests {
    @Test func firstRevealTransitionsToPlaying() async throws {
        let session = MinesweeperSession(difficulty: .beginner, seed: 1, clock: FakeClock())
        let snap = try await session.reveal(row: 4, col: 4)
        #expect(snap.status == .playing)
        #expect(snap.cells.contains(where: { $0.state == .revealed }))
    }

    @Test func revealForwardsToEngineFloodFill() async throws {
        let session = MinesweeperSession(difficulty: .beginner, seed: 42, clock: FakeClock())
        let snap = try await session.reveal(row: 4, col: 4)
        // Engine's fixed-seed beginner board: center reveal cascades to many cells.
        let revealed = snap.cells.filter { $0.state == .revealed }.count
        #expect(revealed >= 9)
    }

    @Test func revealMineLoses() async throws {
        let session = MinesweeperSession(difficulty: .beginner, seed: 13, clock: FakeClock())
        _ = try await session.reveal(row: 4, col: 4)
        // Find a mine from the snapshot and click it.
        let snap1 = await session.snapshot()
        var minePos: (Int, Int)?
        for r in 0..<snap1.rows {
            for c in 0..<snap1.columns where snap1.cell(row: r, col: c).isMine {
                minePos = (r, c); break
            }
            if minePos != nil { break }
        }
        let (mr, mc) = try #require(minePos)
        let final = try await session.reveal(row: mr, col: mc)
        #expect(final.status == .lost)
    }

    @Test func revealAllSafeWins() async throws {
        let session = MinesweeperSession(difficulty: .beginner, seed: 13, clock: FakeClock())
        _ = try await session.reveal(row: 4, col: 4)
        // Reveal every remaining non-mine cell.
        let snap = await session.snapshot()
        for r in 0..<snap.rows {
            for c in 0..<snap.columns {
                let cell = snap.cell(row: r, col: c)
                if !cell.isMine && cell.state == .hidden {
                    _ = try await session.reveal(row: r, col: c)
                }
            }
        }
        let final = await session.snapshot()
        #expect(final.status == .won)
    }

    @Test func revealAfterLossIsNoop() async throws {
        let session = MinesweeperSession(difficulty: .beginner, seed: 13, clock: FakeClock())
        _ = try await session.reveal(row: 4, col: 4)
        let snap1 = await session.snapshot()
        var minePos: (Int, Int)?
        for r in 0..<snap1.rows {
            for c in 0..<snap1.columns where snap1.cell(row: r, col: c).isMine {
                minePos = (r, c); break
            }
            if minePos != nil { break }
        }
        let (mr, mc) = try #require(minePos)
        _ = try await session.reveal(row: mr, col: mc)
        let lostSnap = await session.snapshot()
        _ = try await session.reveal(row: 0, col: 0)
        let after = await session.snapshot()
        #expect(after.cells == lostSnap.cells)
        #expect(after.status == .lost)
    }

    @Test func outOfBoundsRevealThrows() async {
        let session = MinesweeperSession(difficulty: .beginner, seed: 1, clock: FakeClock())
        await #expect(throws: MinesweeperError.self) {
            _ = try await session.reveal(row: -1, col: 0)
        }
    }
}

// MARK: - Flag

@Suite struct MinesweeperSessionFlagTests {
    @Test func toggleFlagAddsAndRemovesFlag() async throws {
        let session = MinesweeperSession(difficulty: .beginner, seed: 1, clock: FakeClock())
        let s1 = try await session.toggleFlag(row: 0, col: 0)
        #expect(s1.cell(row: 0, col: 0).state == .flagged)
        #expect(s1.flagCount == 1)
        let s2 = try await session.toggleFlag(row: 0, col: 0)
        #expect(s2.cell(row: 0, col: 0).state == .hidden)
        #expect(s2.flagCount == 0)
    }

    @Test func firstFlagTransitionsToPlaying() async throws {
        let session = MinesweeperSession(difficulty: .beginner, seed: 1, clock: FakeClock())
        let snap = try await session.toggleFlag(row: 0, col: 0)
        #expect(snap.status == .playing)
    }

    @Test func revealOnFlaggedCellIsNoop() async throws {
        let session = MinesweeperSession(difficulty: .beginner, seed: 1, clock: FakeClock())
        _ = try await session.toggleFlag(row: 0, col: 0)
        let snap = try await session.reveal(row: 0, col: 0)
        #expect(snap.cell(row: 0, col: 0).state == .flagged)
    }
}

// MARK: - Elapsed time

@Suite struct MinesweeperSessionClockTests {
    @Test func clockStartsAfterFirstAction() async throws {
        let clock = FakeClock(100)
        let session = MinesweeperSession(difficulty: .beginner, seed: 1, clock: clock)
        let pre = await session.elapsedSeconds
        #expect(pre == 0)
        _ = try await session.reveal(row: 4, col: 4)
        clock.advance(by: 5)
        let mid = await session.elapsedSeconds
        #expect(mid == 5)
    }

    @Test func clockFreezesOnWin() async throws {
        let clock = FakeClock(0)
        let session = MinesweeperSession(difficulty: .beginner, seed: 13, clock: clock)
        _ = try await session.reveal(row: 4, col: 4)
        clock.advance(by: 3)
        let snap = await session.snapshot()
        for r in 0..<snap.rows {
            for c in 0..<snap.columns {
                let cell = snap.cell(row: r, col: c)
                if !cell.isMine && cell.state == .hidden {
                    _ = try await session.reveal(row: r, col: c)
                }
            }
        }
        let elapsedAtWin = await session.elapsedSeconds
        clock.advance(by: 100)
        let elapsedLater = await session.elapsedSeconds
        #expect(elapsedAtWin == elapsedLater)
        let final = await session.snapshot()
        #expect(final.status == .won)
    }

    @Test func clockFreezesOnLoss() async throws {
        let clock = FakeClock(0)
        let session = MinesweeperSession(difficulty: .beginner, seed: 13, clock: clock)
        _ = try await session.reveal(row: 4, col: 4)
        clock.advance(by: 7)
        let snap = await session.snapshot()
        var minePos: (Int, Int)?
        for r in 0..<snap.rows {
            for c in 0..<snap.columns where snap.cell(row: r, col: c).isMine {
                minePos = (r, c); break
            }
            if minePos != nil { break }
        }
        let (mr, mc) = try #require(minePos)
        _ = try await session.reveal(row: mr, col: mc)
        let elapsedAtLoss = await session.elapsedSeconds
        clock.advance(by: 100)
        let elapsedLater = await session.elapsedSeconds
        #expect(elapsedAtLoss == elapsedLater)
    }
}

// MARK: - Concurrency smoke

@Suite struct MinesweeperSessionConcurrencyTests {
    @Test func concurrentTogglesAreSerialized() async throws {
        // 20 concurrent toggles on the SAME cell — this is the real
        // contention case. Actor serialization must process them in some
        // order without corruption. Even parity (20 toggles) returns the
        // cell to `.hidden`.
        let session = MinesweeperSession(difficulty: .beginner, seed: 1, clock: FakeClock())
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<20 {
                group.addTask {
                    try? await session.toggleFlag(row: 0, col: 0)
                }
            }
        }
        let snap = await session.snapshot()
        #expect(snap.cell(row: 0, col: 0).state == .hidden)
    }
}

// MARK: - OOB does not start session

@Suite struct MinesweeperSessionOutOfBoundsTests {
    @Test func revealOutOfBoundsLeavesStatusIdle() async throws {
        let clock = FakeClock(100)
        let session = MinesweeperSession(difficulty: .beginner, seed: 1, clock: clock)
        await #expect(throws: (any Error).self) {
            _ = try await session.reveal(row: -1, col: 0)
        }
        let snap = await session.snapshot()
        #expect(snap.status == .idle)
        #expect(snap.elapsedSeconds == 0)
    }

    @Test func toggleFlagOutOfBoundsLeavesStatusIdle() async throws {
        let clock = FakeClock(100)
        let session = MinesweeperSession(difficulty: .beginner, seed: 1, clock: clock)
        await #expect(throws: (any Error).self) {
            _ = try await session.toggleFlag(row: -1, col: 0)
        }
        let snap = await session.snapshot()
        #expect(snap.status == .idle)
        #expect(snap.elapsedSeconds == 0)
    }
}

// MARK: - Pause / resume (#434)

@Suite struct MinesweeperSessionPauseTests {
    @Test func pauseFreezesTheClock() async throws {
        let clock = FakeClock(0)
        let session = MinesweeperSession(difficulty: .beginner, seed: 1, clock: clock)
        _ = try await session.reveal(row: 4, col: 4)
        clock.advance(by: 5)

        let paused = await session.pause()
        #expect(paused.status == .paused)
        #expect(paused.elapsedSeconds == 5)

        // Time keeps moving in the wall clock, but elapsed stays frozen.
        clock.advance(by: 100)
        let stillPaused = await session.elapsedSeconds
        #expect(stillPaused == 5)
    }

    @Test func resumeRestartsTheClockWithoutLosingAccumulatedTime() async throws {
        let clock = FakeClock(0)
        let session = MinesweeperSession(difficulty: .beginner, seed: 1, clock: clock)
        _ = try await session.reveal(row: 4, col: 4)
        clock.advance(by: 5)
        _ = await session.pause()

        // Paused gap should NOT count toward elapsed.
        clock.advance(by: 30)
        let resumed = await session.resume()
        #expect(resumed.status == .playing)
        #expect(resumed.elapsedSeconds == 5)

        // After resume the clock advances again from the accumulated base.
        clock.advance(by: 4)
        let afterResume = await session.elapsedSeconds
        #expect(afterResume == 9)
    }

    @Test func pauseIsNoopWhenIdle() async {
        let session = MinesweeperSession(difficulty: .beginner, seed: 1, clock: FakeClock())
        let snap = await session.pause()
        #expect(snap.status == .idle)
    }

    @Test func pauseIsNoopAfterTerminal() async throws {
        let clock = FakeClock(0)
        let session = MinesweeperSession(difficulty: .beginner, seed: 13, clock: clock)
        _ = try await session.reveal(row: 4, col: 4)
        // Drive to a loss.
        let snap = await session.snapshot()
        var minePos: (Int, Int)?
        for r in 0..<snap.rows {
            for c in 0..<snap.columns where snap.cell(row: r, col: c).isMine {
                minePos = (r, c); break
            }
            if minePos != nil { break }
        }
        let (mr, mc) = try #require(minePos)
        _ = try await session.reveal(row: mr, col: mc)
        let paused = await session.pause()
        #expect(paused.status == .lost)
    }

    @Test func resumeIsNoopWhenNotPaused() async throws {
        let session = MinesweeperSession(difficulty: .beginner, seed: 1, clock: FakeClock())
        _ = try await session.reveal(row: 4, col: 4)
        let snap = await session.resume()
        #expect(snap.status == .playing)
    }

    @Test func revealWhilePausedIsNoop() async throws {
        let clock = FakeClock(0)
        let session = MinesweeperSession(difficulty: .beginner, seed: 1, clock: clock)
        _ = try await session.reveal(row: 4, col: 4)
        let before = await session.snapshot()
        _ = await session.pause()
        // A reveal while paused must be absorbed (guard excludes `.paused`).
        let after = try await session.reveal(row: 0, col: 0)
        #expect(after.status == .paused)
        #expect(after.cells == before.cells)
    }
}

// MARK: - Fixed-layout construction (#841)

/// #841 "daily retry after loss generates a different board per first click
/// — daily must be one fixed game": `MinesweeperSession.init(difficulty:
/// seed:fixedMineIndices:)` is the session-layer entry point the daily-replay
/// loader uses to reproduce an already-lost daily's exact mine layout.
@Suite struct MinesweeperSessionFixedLayoutTests {
    @Test func fixedLayoutSessionHasMinesPlacedImmediately() async throws {
        let indices: Set<Int> = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9]
        let session = try MinesweeperSession(
            difficulty: .beginner, seed: 42, fixedMineIndices: indices, clock: FakeClock()
        )
        let snap = await session.snapshot()
        // Mines are set on the underlying cells even though nothing has
        // been revealed yet — `mineIndices` reads them straight off the
        // idle snapshot (this is exactly what the daily's terminal-save
        // blob already captures for the ORIGINAL first-ever attempt).
        #expect(snap.mineIndices == indices)
        #expect(snap.status == .idle)
    }

    /// The end-to-end #841 acceptance test at the session layer: two
    /// sessions built from the SAME persisted layout but revealed at
    /// DIFFERENT first cells still produce an IDENTICAL mine layout — the
    /// exact scenario the issue reported (lose a daily, retry with a
    /// different first click, get a different board).
    @Test func retryWithDifferentFirstClickReproducesIdenticalLayout() async throws {
        let indices: Set<Int> = [5, 17, 33, 44, 55, 61, 70, 72, 80, 12]
        let firstAttempt = try MinesweeperSession(
            difficulty: .beginner, seed: 99, fixedMineIndices: indices, clock: FakeClock()
        )
        let retry = try MinesweeperSession(
            difficulty: .beginner, seed: 99, fixedMineIndices: indices, clock: FakeClock()
        )
        _ = try await firstAttempt.reveal(row: 0, col: 0)
        _ = try await retry.reveal(row: 8, col: 8)
        let firstSnap = await firstAttempt.snapshot()
        let retrySnap = await retry.snapshot()
        #expect(firstSnap.mineIndices == retrySnap.mineIndices)
        #expect(firstSnap.mineIndices == indices)
    }

    @Test func wrongMineCountThrowsInvalidFixedLayout() {
        #expect(throws: MinesweeperError.self) {
            _ = try MinesweeperSession(
                difficulty: .beginner, seed: 1, fixedMineIndices: [0, 1], clock: FakeClock()
            )
        }
    }
}

// swiftlint:enable identifier_name
