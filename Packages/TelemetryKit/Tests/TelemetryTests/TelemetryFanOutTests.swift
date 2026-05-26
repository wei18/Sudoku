import Testing
@testable import Telemetry
import TelemetryTesting

@Suite("Telemetry — fan-out")
struct TelemetryFanOutTests {

    @Test func allSinksReceiveEvent() async {
        let sinkA = RecordingSink()
        let sinkB = RecordingSink()
        let sinkC = RecordingSink()
        let telemetry = Telemetry(sinks: [sinkA, sinkB, sinkC])

        await telemetry.observe(.moveUndone)

        let receivedA = await sinkA.received
        let receivedB = await sinkB.received
        let receivedC = await sinkC.received
        #expect(receivedA == [.moveUndone])
        #expect(receivedB == [.moveUndone])
        #expect(receivedC == [.moveUndone])
    }

    @Test func slowSinkDoesNotBlockOthersFromReceiving() async {
        // Model "misbehaving sink": sleeps ~5ms before recording. The
        // facade awaits sequentially, so siblings before/after still
        // see every event — the assertion is that NO event is dropped.
        let fast1 = RecordingSink()
        let slow = SlowSink(delayNanoseconds: 5_000_000)
        let fast2 = RecordingSink()
        let telemetry = Telemetry(sinks: [fast1, slow, fast2])

        await telemetry.observe(.sessionPaused)
        await telemetry.observe(.sessionResumed)

        let receivedFast1 = await fast1.received
        let receivedSlow = await slow.received
        let receivedFast2 = await fast2.received
        #expect(receivedFast1 == [.sessionPaused, .sessionResumed])
        #expect(receivedSlow == [.sessionPaused, .sessionResumed])
        #expect(receivedFast2 == [.sessionPaused, .sessionResumed])
    }

    @Test func eventOrderingPreserved() async {
        let sinkA = RecordingSink()
        let sinkB = RecordingSink()
        let telemetry = Telemetry(sinks: [sinkA, sinkB])

        let events: [TelemetryEvent] = (1...10).map { digit in
            .digitPlaced(row: 0, col: 0, digit: digit, previous: nil)
        }
        for event in events {
            await telemetry.observe(event)
        }

        let receivedA = await sinkA.received
        let receivedB = await sinkB.received
        #expect(receivedA == events)
        #expect(receivedB == events)
    }
}
