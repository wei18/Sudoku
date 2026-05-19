// MetricKitSink — subscribes to MXMetricManager and projects every
// payload into a TelemetryEvent.metricKitReport, then forwards through
// the downstream Telemetry facade.
//
// Architectural shape (design.md §How.1 + foundations.md §6):
//
//   MXMetricManager (system)
//        │
//        │ MXMetricManagerSubscriber callbacks
//        ▼
//   MetricKitSink (here) — wraps payload JSON into MetricReport
//        │
//        │ downstream.observe(.metricKitReport(report))
//        ▼
//   Telemetry → OSLogSink (lands report in unified log) + others
//
// MetricKitSink also conforms to TelemetrySink for symmetry, but its
// `receive(_:)` is a no-op — it is a one-way *source* in v1, not an
// endpoint. The conformance keeps the construction site uniform if a
// future composition wants to plug it as a sink as well.
//
// Platform availability: MetricKit is iOS / macCatalyst only at the
// `MXMetricManager` API level. On macOS-native the type compiles only
// because `MetricKit` is technically importable; sub-class registration
// is wrapped behind `MetricKitSink.startIfAvailable` to keep the unit
// test target (macOS host) decoupled from live registration.

#if canImport(MetricKit)
public import Foundation
public import MetricKit

public final class MetricKitSink: NSObject, MXMetricManagerSubscriber, TelemetrySink, @unchecked Sendable {
    private let downstream: Telemetry
    private let clock: @Sendable () -> Date

    /// - Parameter downstream: facade that receives the projected event.
    /// - Parameter clock: injectable time source for `MetricReport.receivedAt`.
    public init(
        downstream: Telemetry,
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.downstream = downstream
        self.clock = clock
        super.init()
    }

    /// Register with the shared MXMetricManager. Split out so unit tests
    /// can exercise the projection logic via `ingest(...)` without
    /// touching the system subscriber registry.
    public func startReceivingSystemReports() {
        MXMetricManager.shared.add(self)
    }

    /// Mirror of `startReceivingSystemReports` for symmetric teardown.
    public func stopReceivingSystemReports() {
        MXMetricManager.shared.remove(self)
    }

    // MARK: - MXMetricManagerSubscriber

    public func didReceive(_ payloads: [MXMetricPayload]) {
        for payload in payloads {
            let json = decode(payload.jsonRepresentation())
            ingest(kind: .daily, payloadJSON: json)
        }
    }

    public func didReceive(_ payloads: [MXDiagnosticPayload]) {
        for payload in payloads {
            let json = decode(payload.jsonRepresentation())
            let kind: MetricReport.Kind = (payload.crashDiagnostics?.isEmpty == false) ? .crash : .hang
            ingest(kind: kind, payloadJSON: json)
        }
    }

    // MARK: - TelemetrySink

    public func receive(_ event: TelemetryEvent) async {
        // MetricKitSink is a producer, not an endpoint — no-op.
    }

    // MARK: - Test-friendly seam

    /// Directly project a canned MetricKit JSON payload as if it had
    /// arrived from the system. Exercised by unit tests that ship
    /// fixture JSON because MetricKit cannot deliver in a host test.
    public func ingest(kind: MetricReport.Kind, payloadJSON: String) {
        let report = MetricReport(kind: kind, payloadJSON: payloadJSON, receivedAt: clock())
        let downstream = downstream
        Task { await downstream.observe(.metricKitReport(report)) }
    }

    // MARK: -

    private func decode(_ data: Data) -> String {
        String(data: data, encoding: .utf8) ?? "{}"
    }
}
#endif
