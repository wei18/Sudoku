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

    /// A snapshot captured WHILE `.playing` (not pre-paused) restores to
    /// `.paused` with elapsed preserved. The other tests pause before
    /// snapshotting, so this is the only one that actually exercises the
    /// `.playing → .paused` restore remap.
    @Test func restoringPlayingSessionParksAtPausedWithElapsed() async throws {
        let clock = FakeClock()
        let session = MinesweeperSession(difficulty: .beginner, seed: 13, clock: clock)
        _ = try await session.reveal(row: 4, col: 4)
        clock.advance(by: 17)
        let snap = await session.snapshot()   // NO pause — captured while playing
        #expect(snap.status == .playing)
        #expect(snap.elapsedSeconds == 17)

        let restored = await MinesweeperSession.restore(from: snap, clock: FakeClock())
        let restoredSnap = await restored.snapshot()
        #expect(restoredSnap.status == .paused)
        #expect(restoredSnap.elapsedSeconds == 17)
    }

    /// After restore the game is `.paused`; `resume()` → revealing a new hidden
    /// non-mine cell succeeds and reveals it — proves the reinstated board
    /// supports continued play (flood-fill uses the restored neighbor counts).
    @Test func restoredSessionResumesAndContinuesPlay() async throws {
        let session = MinesweeperSession(difficulty: .beginner, seed: 11, clock: FakeClock())
        _ = try await session.reveal(row: 4, col: 4)
        let snap = await session.snapshot()

        let restored = await MinesweeperSession.restore(from: snap, clock: FakeClock())
        #expect(await restored.snapshot().status == .paused)
        _ = await restored.resume()

        var revealedNew = false
        outer: for r in 0..<snap.rows {
            for c in 0..<snap.columns {
                let cell = snap.cell(row: r, col: c)
                if cell.state == .hidden, !cell.isMine {
                    let after = try await restored.reveal(row: r, col: c)
                    #expect(after.cell(row: r, col: c).state == .revealed)
                    revealedNew = true
                    break outer
                }
            }
        }
        #expect(revealedNew)
    }

    /// Revealing a known mine after restore transitions to `.lost` — terminal
    /// detection works on a reinstated board.
    @Test func restoredSessionDetectsLossOnMineReveal() async throws {
        let session = MinesweeperSession(difficulty: .beginner, seed: 23, clock: FakeClock())
        _ = try await session.reveal(row: 4, col: 4)
        let snap = await session.snapshot()

        let restored = await MinesweeperSession.restore(from: snap, clock: FakeClock())
        _ = await restored.resume()

        var hitMine = false
        outer: for r in 0..<snap.rows {
            for c in 0..<snap.columns where snap.cell(row: r, col: c).state == .hidden
            && snap.cell(row: r, col: c).isMine {
                let after = try await restored.reveal(row: r, col: c)
                #expect(after.status == .lost)
                hitMine = true
                break outer
            }
        }
        #expect(hitMine)
    }
}

// MARK: - everFlagged persistence (#700 CR)

@Suite struct MinesweeperSessionEverFlaggedTests {

    /// Find a hidden non-revealed cell to flag after the first reveal.
    private func firstHiddenCell(in snap: MinesweeperSessionSnapshot) -> (row: Int, col: Int)? {
        for r in 0..<snap.rows {
            for c in 0..<snap.columns where snap.cell(row: r, col: c).state == .hidden {
                return (r, c)
            }
        }
        return nil
    }

    @Test("Place-then-remove keeps everFlagged latched — removal never un-disqualifies")
    func placeThenRemoveKeepsEverFlagged() async throws {
        let session = MinesweeperSession(difficulty: .beginner, seed: 7, clock: FakeClock())
        _ = try await session.reveal(row: 4, col: 4)
        let snap = await session.snapshot()
        #expect(snap.everFlagged == false)
        let target = try #require(firstHiddenCell(in: snap))

        _ = try await session.toggleFlag(row: target.row, col: target.col)
        let afterRemove = try await session.toggleFlag(row: target.row, col: target.col)
        #expect(afterRemove.flagCount == 0)
        #expect(afterRemove.everFlagged == true)
    }

    @Test("everFlagged survives JSON round-trip + restore, even with zero flags on the board")
    func everFlaggedSurvivesRestore() async throws {
        let session = MinesweeperSession(difficulty: .beginner, seed: 7, clock: FakeClock())
        _ = try await session.reveal(row: 4, col: 4)
        let target = try #require(firstHiddenCell(in: await session.snapshot()))
        _ = try await session.toggleFlag(row: target.row, col: target.col)
        _ = try await session.toggleFlag(row: target.row, col: target.col) // removed again
        let snap = await session.snapshot()

        let blob = try JSONEncoder().encode(snap)
        let decoded = try JSONDecoder().decode(MinesweeperSessionSnapshot.self, from: blob)
        #expect(decoded.everFlagged == true)

        let restored = await MinesweeperSession.restore(from: decoded, clock: FakeClock())
        let restoredSnap = await restored.snapshot()
        #expect(restoredSnap.everFlagged == true)
    }

    @Test("Legacy blob without the everFlagged key decodes as false (pre-#700 back-compat)")
    func legacyBlobDecodesEverFlaggedFalse() async throws {
        let session = MinesweeperSession(difficulty: .beginner, seed: 7, clock: FakeClock())
        _ = try await session.reveal(row: 4, col: 4)
        let blob = try JSONEncoder().encode(await session.snapshot())

        // Simulate a pre-#700 save: strip the key from the encoded JSON.
        var json = try #require(
            try JSONSerialization.jsonObject(with: blob) as? [String: Any]
        )
        json.removeValue(forKey: "everFlagged")
        let legacyBlob = try JSONSerialization.data(withJSONObject: json)

        let decoded = try JSONDecoder().decode(MinesweeperSessionSnapshot.self, from: legacyBlob)
        #expect(decoded.everFlagged == false)
    }

    @Test("Restoring a legacy save with flags on the board conservatively sets everFlagged")
    func restoreLegacySaveWithFlagsOnBoardSetsEverFlagged() async throws {
        let session = MinesweeperSession(difficulty: .beginner, seed: 7, clock: FakeClock())
        _ = try await session.reveal(row: 4, col: 4)
        let target = try #require(firstHiddenCell(in: await session.snapshot()))
        _ = try await session.toggleFlag(row: target.row, col: target.col) // flag stays placed
        let snap = await session.snapshot()

        // Simulate the pre-#700 shape: same board, everFlagged not recorded.
        let legacy = MinesweeperSessionSnapshot(
            difficulty: snap.difficulty, seed: snap.seed, cells: snap.cells,
            status: snap.status, elapsedSeconds: snap.elapsedSeconds,
            mineCount: snap.mineCount, flagCount: snap.flagCount,
            everFlagged: false
        )
        let restored = await MinesweeperSession.restore(from: legacy, clock: FakeClock())
        let restoredSnap = await restored.snapshot()
        #expect(restoredSnap.flagCount == 1)
        #expect(restoredSnap.everFlagged == true)
    }
}

// swiftlint:enable identifier_name
