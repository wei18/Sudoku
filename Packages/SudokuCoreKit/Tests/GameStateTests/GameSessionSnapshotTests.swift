import Foundation
import SudokuEngine
import Testing
@testable import GameState

@Suite("GameSession snapshot + telemetry coverage")
struct GameSessionSnapshotTests {

    @Test("snapshot() captures puzzle / board / status / elapsed / stacks / notes")
    func snapshotCapturesFullState() async throws {
        let clock = FakeMonotonicClock()
        let session = GameSession(puzzle: TestPuzzles.simple, clock: clock)
        try await session.start()
        clock.set(20)
        try await session.placeDigit(row: 0, col: 1, digit: 5)
        try await session.placeDigit(row: 0, col: 2, digit: 6)
        try await session.undo() // place a redo entry
        try await session.toggleNote(row: 1, col: 1, digit: 3)

        let snap = await session.snapshot()
        #expect(snap.puzzle == TestPuzzles.simple)
        #expect(snap.status == .playing)
        #expect(snap.elapsedSeconds == 20)
        #expect(snap.undoMoves.count == 1)
        #expect(snap.redoMoves.count == 1)
        #expect(snap.notes.contains(digit: 3, row: 1, col: 1))
    }

    @Test("Snapshot JSON round-trip")
    func jsonRoundtrip() async throws {
        let session = GameSession(puzzle: TestPuzzles.simple)
        try await session.start()
        try await session.placeDigit(row: 0, col: 1, digit: 5)
        let snap = await session.snapshot()

        let encoded = try JSONEncoder().encode(snap)
        let decoded = try JSONDecoder().decode(GameSessionSnapshot.self, from: encoded)
        #expect(decoded == snap)
    }

    @Test("restore() rebuilds an equivalent session")
    func restoreRoundtrip() async throws {
        let clock = FakeMonotonicClock()
        let session = GameSession(puzzle: TestPuzzles.simple, clock: clock)
        try await session.start()
        clock.set(15)
        try await session.placeDigit(row: 0, col: 1, digit: 5)
        try await session.placeDigit(row: 0, col: 2, digit: 6)
        try await session.undo()
        let snap = await session.snapshot()

        let restoredClock = FakeMonotonicClock()
        let restored = await GameSession.restore(from: snap, clock: restoredClock)

        // A restored in-progress (`.playing`) snapshot is normalized to
        // `.paused` — the only field that differs from the source snapshot.
        // See GameSession.applySnapshot for the rationale (frozen clock +
        // resume() can't transition from `.playing`).
        let restoredSnap = await restored.snapshot()
        #expect(restoredSnap.status == .paused)
        #expect(restoredSnap == GameSessionSnapshot(
            puzzle: snap.puzzle,
            currentBoard: snap.currentBoard,
            status: .paused,
            elapsedSeconds: snap.elapsedSeconds,
            undoMoves: snap.undoMoves,
            redoMoves: snap.redoMoves,
            notes: snap.notes,
            startedAt: snap.startedAt
        ))
    }

    @Test("After restore, undo / redo / placeDigit still work")
    func postRestoreOperationsWork() async throws {
        let session = GameSession(puzzle: TestPuzzles.simple)
        try await session.start()
        try await session.placeDigit(row: 0, col: 1, digit: 5)
        try await session.placeDigit(row: 0, col: 2, digit: 6)
        try await session.undo()
        let snap = await session.snapshot()

        let restored = await GameSession.restore(from: snap)
        // Restored in-progress session is `.paused`; resume before play.
        try await restored.resume()
        try await restored.redo()
        let cell = await restored.currentBoard.digit(atRow: 0, column: 2)
        #expect(cell == 6)

        try await restored.placeDigit(row: 0, col: 3, digit: 7)
        let cell3 = await restored.currentBoard.digit(atRow: 0, column: 3)
        #expect(cell3 == 7)
    }

    @Test("Restored .playing snapshot normalizes to .paused so resume() re-arms the clock")
    func restoredPlayingResumesAndAdvances() async throws {
        // Mid-play autosaves persist status == .playing (GameViewModel
        // scheduleSave runs during play). A restored session is always
        // frozen (runningSince = nil); a frozen .playing has no resume()
        // path (resume only transitions from .paused), so the clock would
        // stay stuck. Normalizing to .paused lets the explicit-resume path
        // (startOrResume .paused → resume()) re-open a running span.
        let snap = GameSessionSnapshot(
            puzzle: TestPuzzles.simple,
            currentBoard: TestPuzzles.simple.clues,
            status: .playing,
            elapsedSeconds: 120,
            undoMoves: [],
            redoMoves: [],
            notes: NotesGrid(),
            startedAt: nil
        )

        let clock = FakeMonotonicClock()
        let restored = await GameSession.restore(from: snap, clock: clock)

        // Frozen on restore — clock advancing alone must NOT accrue time.
        clock.set(50)
        let frozen = await restored.elapsedSeconds
        #expect(frozen == 120, "restore must not auto-resume the wall clock")

        // Explicit resume re-arms the span from the prior accumulated total.
        try await restored.resume()
        clock.set(80)
        let advanced = await restored.elapsedSeconds
        #expect(advanced == 150, "120 saved + 30 elapsed after resume")
    }

    @Test("All transitions emit their expected telemetry events")
    func transitionsEmitTelemetry() async throws {
        let spy = SpyTelemetry()
        let session = GameSession(puzzle: TestPuzzles.simple, telemetry: spy)
        try await session.start()
        try await session.pause()
        try await session.resume()
        try await session.abandon()
        let events = await spy.events
        #expect(events.contains(.sessionStarted))
        #expect(events.contains(.sessionPaused))
        #expect(events.contains(.sessionResumed))
        #expect(events.contains(.sessionAbandoned))
    }

    @Test("Auto-completion emits sessionCompleted with elapsedSeconds")
    func autoCompleteEmitsTelemetry() async throws {
        let clock = FakeMonotonicClock()
        let spy = SpyTelemetry()
        let puzzle = TestPuzzles.nearSolved(missingRow: 0, missingCol: 0)
        let session = GameSession(puzzle: puzzle, clock: clock, telemetry: spy)
        try await session.start()
        clock.set(42)
        try await session.placeDigit(
            row: 0,
            col: 0,
            digit: Int(puzzle.solution.cells[Board.index(row: 0, column: 0)])
        )
        let events = await spy.events
        // The nearSolved fixture uses a shifted Latin square (not a valid Sudoku),
        // so placing digit 1 at (0,0) conflicts with digit 1 already present in
        // column 0 (row 2 of the Latin square). mistakeCount is 1, not 0.
        // The test proves elapsedSeconds + mistakeCount are both forwarded.
        #expect(events.contains(.sessionCompleted(elapsedSeconds: 42, mistakeCount: 1)))
    }

    @Test("undo / redo emit moveUndone / moveRedone")
    func undoRedoEmitTelemetry() async throws {
        let spy = SpyTelemetry()
        let session = GameSession(puzzle: TestPuzzles.simple, telemetry: spy)
        try await session.start()
        try await session.placeDigit(row: 0, col: 1, digit: 5)
        try await session.undo()
        try await session.redo()
        let events = await spy.events
        #expect(events.contains(.moveUndone))
        #expect(events.contains(.moveRedone))
    }
}
