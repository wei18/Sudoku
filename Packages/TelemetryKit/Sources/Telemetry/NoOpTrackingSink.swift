// NoOpTrackingSink — placeholder for the future tracking branch
// (foundations.md §6).
//
// v1 ships with no third-party tracking SDK (Apple three-piece only:
// ASC Analytics + MetricKit + Game Center). The call site still wires
// `telemetry.observe(event)` exactly the same way; when v2 introduces a
// real tracking sink (TelemetryDeck / first-party CloudKit pipeline),
// only the sink implementation swaps — every caller is unchanged.

public struct NoOpTrackingSink: TelemetrySink {
    public init() {}

    public func receive(_ event: TelemetryEvent) async {
        // intentionally empty
    }
}
