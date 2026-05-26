// TelemetrySink — endpoint for one branch of the Telemetry fan-out.
//
// Sinks are Sendable; `receive(_:)` is async (not throws) — sinks must
// absorb their own failures (log them, drop them, retry internally) so a
// single misbehaving sink cannot break sibling sinks. The facade
// (`Telemetry` actor) awaits each sink in order; ordering per sink is FIFO.

public protocol TelemetrySink: Sendable {
    func receive(_ event: TelemetryEvent) async
}
