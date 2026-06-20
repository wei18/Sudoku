import Testing
@testable import Telemetry
import TelemetryTesting

@Suite("DeferredSink — late-binding fan-out")
struct DeferredSinkTests {

    // (a) After setDownstream, events are forwarded to the downstream sink.
    @Test func forwardsToDownstreamAfterSet() async {
        let deferred = DeferredSink()
        let recorder = RecordingSink()
        deferred.setDownstream([recorder])
        await deferred.receive(.moveUndone)
        let received = await recorder.received
        #expect(received == [.moveUndone])
    }

    // (b) receive before any setDownstream is a safe no-op.
    @Test func receiveBeforeSetIsNoOp() async {
        let deferred = DeferredSink()
        // No crash, no event stored (there is nothing to assert on, but
        // the test validates it doesn't trap or deadlock).
        await deferred.receive(.sessionPaused)
        // Now set downstream and verify no replay (no-op means no replay).
        let recorder = RecordingSink()
        deferred.setDownstream([recorder])
        let received = await recorder.received
        #expect(received.isEmpty)
    }

    // (c) Forwards to multiple downstream sinks in order.
    @Test func forwardsToMultipleDownstreamsInOrder() async {
        let deferred = DeferredSink()
        let first = RecordingSink()
        let second = RecordingSink()
        let third = RecordingSink()
        deferred.setDownstream([first, second, third])
        await deferred.receive(.sessionStarted(puzzleId: "2026-05-19-easy", mode: .daily, difficulty: .easy))
        await deferred.receive(.moveRedone)
        let receivedFirst = await first.received
        let receivedSecond = await second.received
        let receivedThird = await third.received
        let expected: [TelemetryEvent] = [
            .sessionStarted(puzzleId: "2026-05-19-easy", mode: .daily, difficulty: .easy),
            .moveRedone
        ]
        #expect(receivedFirst == expected)
        #expect(receivedSecond == expected)
        #expect(receivedThird == expected)
    }
}
