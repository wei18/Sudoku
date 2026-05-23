// Telemetry — the fan-out facade (foundations.md §5 / docs/v1/design.md §How.1).
//
// Callers say "what happened" (`telemetry.observe(event)`); the facade
// dispatches sequentially to every sink. Sequential dispatch (rather than
// a TaskGroup) preserves per-sink FIFO ordering trivially and removes any
// risk of one slow sink starving another via task scheduling.
//
// Sinks are responsible for absorbing their own failures — `TelemetrySink`
// is not throwing — so a poorly-behaved sink can only delay the chain, not
// break it. The "throwingSinkDoesNotBlockOthers" test models a slow sink
// (a sleeping one) and asserts siblings still observe every event.

public actor Telemetry {
    private let sinks: [any TelemetrySink]

    public init(sinks: [any TelemetrySink]) {
        self.sinks = sinks
    }

    public func observe(_ event: TelemetryEvent) async {
        for sink in sinks {
            await sink.receive(event)
        }
    }
}
