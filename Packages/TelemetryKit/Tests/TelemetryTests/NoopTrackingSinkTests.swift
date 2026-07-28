import SudokuEngine
import Testing
@testable import Telemetry

@Suite("NoopTrackingSink")
struct NoopTrackingSinkTests {

    @Test func instantiable() {
        _ = NoopTrackingSink()
    }

    @Test func receiveIsNoOp() async {
        let sink = NoopTrackingSink()
        await sink.receive(.moveUndone)
        await sink.receive(.puzzleCompleted(
            puzzleId: "p", mode: .daily, difficulty: .easy, elapsedSeconds: 1, mistakeCount: 0
        ))
        // No observable side effect — assertion is "doesn't crash".
    }
}
