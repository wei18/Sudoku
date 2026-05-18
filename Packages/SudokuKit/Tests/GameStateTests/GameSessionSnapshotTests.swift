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

        let restoredSnap = await restored.snapshot()
        #expect(restoredSnap == snap)
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
        try await restored.redo()
        let cell = await restored.currentBoard.digit(atRow: 0, column: 2)
        #expect(cell == 6)

        try await restored.placeDigit(row: 0, col: 3, digit: 7)
        let cell3 = await restored.currentBoard.digit(atRow: 0, column: 3)
        #expect(cell3 == 7)
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
        #expect(events.contains(.sessionCompleted(elapsedSeconds: 42)))
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
