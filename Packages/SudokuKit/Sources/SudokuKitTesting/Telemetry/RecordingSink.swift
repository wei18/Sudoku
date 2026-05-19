// RecordingSink — Telemetry test helper that records every event in order.
//
// Lives in SudokuKitTesting so multiple test targets (TelemetryTests,
// GameStateTests, future PersistenceTests) can share the same spy.

public import Telemetry

public actor RecordingSink: TelemetrySink {
    public private(set) var received: [TelemetryEvent] = []

    public init() {}

    public func receive(_ event: TelemetryEvent) async {
        received.append(event)
    }
}

/// SlowSink — sleeps for `delay` nanoseconds before recording. Used to
/// model a misbehaving sink that delays the fan-out chain; sibling sinks
/// must still see every event.
public actor SlowSink: TelemetrySink {
    public private(set) var received: [TelemetryEvent] = []
    private let delayNanoseconds: UInt64

    public init(delayNanoseconds: UInt64) {
        self.delayNanoseconds = delayNanoseconds
    }

    public func receive(_ event: TelemetryEvent) async {
        try? await Task.sleep(nanoseconds: delayNanoseconds)
        received.append(event)
    }
}
