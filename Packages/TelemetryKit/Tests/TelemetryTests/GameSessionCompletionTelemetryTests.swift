// GameSessionCompletionTelemetryTests — Phase 1 integration test:
// GameSession driven to completion via GameStateTelemetryAdapter emits
// .puzzleCompleted into the Telemetry fan-out.
//
// This is the observable contract that BoardLoaderView/RouteFactory wire in phase 1:
// when telemetry is non-nil, a GameStateTelemetryAdapter is built and passed
// to GameSession.restore(from:telemetry:), so completions reach the Telemetry.

import Testing
@testable import Telemetry
import TelemetryTesting
import SudokuGameState
import SudokuEngine

@Suite("GameSession completion → Telemetry fan-out (phase 1 contract)")
struct GameSessionCompletionTelemetryTests {

    @Test func sessionCompleteEmitsPuzzleCompletedViaAdapter() async throws {
        let recorder = RecordingSink()
        let telemetry = Telemetry(sinks: [recorder])
        let puzzleId = "2026-05-19-easy"
        let mode = Mode.daily
        let difficulty = Difficulty.easy

        let adapter = GameStateTelemetryAdapter(
            telemetry: telemetry,
            puzzleId: puzzleId,
            mode: mode,
            difficulty: difficulty
        )

        // Build a session from a fully-solved puzzle snapshot (status .paused)
        // so we can resume + complete it without filling cells manually.
        let puzzle = try PuzzleGenerator.generate(seed: 42, difficulty: .easy, version: .v1)
        let snapshot = GameSessionSnapshot(
            puzzle: puzzle,
            currentBoard: puzzle.solution,
            status: .paused,
            elapsedSeconds: 120,
            undoMoves: [],
            redoMoves: [],
            notes: NotesGrid(),
            startedAt: nil,
            mistakeCount: 0
        )
        let session = await GameSession.restore(from: snapshot, telemetry: adapter)
        try await session.resume()

        // Call complete() directly — simulating the sticky-completion path
        // that fires when the board matches the solution in placeDigit.
        try await session.complete()

        let received = await recorder.received
        let completionEvents = received.filter {
            if case .puzzleCompleted = $0 { return true }; return false
        }
        #expect(!completionEvents.isEmpty, "expected .puzzleCompleted event from adapter")
        if case let .puzzleCompleted(pid, modeVal, diffVal, elapsedSecs, _) = completionEvents[0] {
            #expect(pid == puzzleId)
            #expect(modeVal == mode)
            #expect(diffVal == difficulty)
            #expect(elapsedSecs >= 0)
        }
    }
}
