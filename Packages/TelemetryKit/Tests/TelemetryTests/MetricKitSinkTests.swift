// MetricKitSinkTests — exercises the projection logic via the
// test-friendly `ingest(kind:payloadJSON:)` seam.
//
// Limitation: we cannot trigger `MXMetricManagerSubscriber` callbacks
// from a host test target (MetricKit only delivers payloads on real
// iOS devices). The seam decouples the "payload → MetricReport →
// Telemetry.observe" flow from the system subscriber registry, so the
// behavior we DO own is fully covered. Live subscriber wiring is
// validated manually in Phase 10 against TestFlight builds.

#if canImport(MetricKit)
import Foundation
import Testing
@testable import Telemetry
import SudokuKitTesting

@Suite("MetricKitSink — payload projection")
struct MetricKitSinkTests {

    @Test func dailyPayloadBecomesMetricKitReportEvent() async {
        let recorder = RecordingSink()
        let downstream = Telemetry(sinks: [recorder])
        let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)
        let sink = MetricKitSink(downstream: downstream, clock: { fixedDate })

        sink.ingest(kind: .daily, payloadJSON: MetricPayloadFixtures.dailyMetric)

        // ingest dispatches via Task — settle by yielding the cooperative
        // pool a few hops, then probe the recorder.
        for _ in 0..<10 { await Task.yield() }

        let received = await recorder.received
        #expect(received.count == 1)
        guard case let .metricKitReport(report) = received[0] else {
            Issue.record("Expected .metricKitReport, got \(received[0])")
            return
        }
        #expect(report.kind == .daily)
        #expect(report.payloadJSON == MetricPayloadFixtures.dailyMetric)
        #expect(report.receivedAt == fixedDate)
    }

    @Test func crashDiagnosticForwarded() async {
        let recorder = RecordingSink()
        let downstream = Telemetry(sinks: [recorder])
        let sink = MetricKitSink(downstream: downstream)

        sink.ingest(kind: .crash, payloadJSON: MetricPayloadFixtures.crashDiagnostic)

        for _ in 0..<10 { await Task.yield() }

        let received = await recorder.received
        #expect(received.count == 1)
        guard case let .metricKitReport(report) = received[0] else {
            Issue.record("Expected .metricKitReport, got \(received[0])")
            return
        }
        #expect(report.kind == .crash)
        #expect(report.payloadJSON.contains("crashDiagnostics"))
    }

    @Test func hangDiagnosticForwarded() async {
        let recorder = RecordingSink()
        let downstream = Telemetry(sinks: [recorder])
        let sink = MetricKitSink(downstream: downstream)

        sink.ingest(kind: .hang, payloadJSON: MetricPayloadFixtures.hangDiagnostic)

        for _ in 0..<10 { await Task.yield() }

        let received = await recorder.received
        #expect(received.count == 1)
        guard case let .metricKitReport(report) = received[0] else {
            Issue.record("Expected .metricKitReport, got \(received[0])")
            return
        }
        #expect(report.kind == .hang)
    }

    @Test func receiveAsSinkIsNoOp() async {
        // MetricKitSink conforms to TelemetrySink for symmetry but is a
        // producer in v1; calling receive(_:) must not crash and must
        // not feed back into the downstream facade.
        let recorder = RecordingSink()
        let downstream = Telemetry(sinks: [recorder])
        let sink = MetricKitSink(downstream: downstream)

        await sink.receive(.moveUndone)
        for _ in 0..<10 { await Task.yield() }

        let received = await recorder.received
        #expect(received.isEmpty)
    }
}
#endif
