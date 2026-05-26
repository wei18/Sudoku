import SudokuEngine
import Testing
@testable import Telemetry

@Suite("NoOpTrackingSink")
struct NoOpTrackingSinkTests {

    @Test func instantiable() {
        _ = NoOpTrackingSink()
    }

    @Test func receiveIsNoOp() async {
        let sink = NoOpTrackingSink()
        await sink.receive(.moveUndone)
        await sink.receive(.puzzleCompleted(
            puzzleId: "p", mode: .daily, difficulty: .easy, elapsedSeconds: 1
        ))
        // No observable side effect — assertion is "doesn't crash".
    }
}
