import Testing
@testable import Telemetry
import SudokuGameState
import SudokuEngine
import TelemetryTesting

@Suite("GameStateTelemetryAdapter — mapping")
struct GameStateTelemetryAdapterTests {

    private func makeAdapter() async -> (GameStateTelemetryAdapter, RecordingSink) {
        let recorder = RecordingSink()
        let telemetry = Telemetry(sinks: [recorder])
        let adapter = GameStateTelemetryAdapter(
            telemetry: telemetry,
            puzzleId: "2026-05-19-easy",
            mode: .daily,
            difficulty: .easy
        )
        return (adapter, recorder)
    }

    @Test func sessionStartedCarriesContext() async {
        let (adapter, recorder) = await makeAdapter()
        await adapter.dispatch(.sessionStarted)
        let received = await recorder.received
        #expect(received == [.sessionStarted(
            puzzleId: "2026-05-19-easy",
            mode: .daily,
            difficulty: .easy
        )])
    }

    @Test func sessionCompletedMapsToPuzzleCompletedWithElapsed() async {
        let (adapter, recorder) = await makeAdapter()
        await adapter.dispatch(.sessionCompleted(elapsedSeconds: 321, mistakeCount: 2))
        let received = await recorder.received
        #expect(received == [.puzzleCompleted(
            puzzleId: "2026-05-19-easy",
            mode: .daily,
            difficulty: .easy,
            elapsedSeconds: 321,
            mistakeCount: 2
        )])
    }

    @Test func sessionAbandonedEmitsZeroElapsed() async {
        let (adapter, recorder) = await makeAdapter()
        await adapter.dispatch(.sessionAbandoned)
        let received = await recorder.received
        #expect(received == [.sessionAbandoned(
            puzzleId: "2026-05-19-easy",
            mode: .daily,
            difficulty: .easy,
            elapsedSeconds: 0
        )])
    }

    @Test func gameplayEventsPassThroughUnchanged() async {
        let (adapter, recorder) = await makeAdapter()
        await adapter.dispatch(.digitPlaced(row: 1, col: 2, digit: 3, previous: nil))
        await adapter.dispatch(.noteToggled(row: 4, col: 5, digit: 6, added: true))
        await adapter.dispatch(.moveUndone)
        await adapter.dispatch(.moveRedone)
        await adapter.dispatch(.sessionPaused)
        await adapter.dispatch(.sessionResumed)
        let received = await recorder.received
        #expect(received == [
            .digitPlaced(row: 1, col: 2, digit: 3, previous: nil),
            .noteToggled(row: 4, col: 5, digit: 6, added: true),
            .moveUndone,
            .moveRedone,
            .sessionPaused,
            .sessionResumed
        ])
    }
}
