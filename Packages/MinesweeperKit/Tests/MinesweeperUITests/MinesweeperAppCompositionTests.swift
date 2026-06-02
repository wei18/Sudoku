// MinesweeperAppCompositionTests — sentinel coverage for the `.live()` and
// `.preview()` factories added in the 2026-06-02 parity-audit telemetry wire.
//
// Coverage is shape-only: the factories construct, the bag's `telemetry` +
// `errorReporter` fields are populated, and `observe(_:)` / `report(_:...)`
// round-trip without crashing. View-level emission isn't wired yet.

import Testing
@testable import MinesweeperAppComposition
import Telemetry

@MainActor
@Suite struct MinesweeperAppCompositionTests {

    @Test func liveFactoryConstructs() {
        let bag = MinesweeperAppComposition.live()
        _ = bag.routeFactory
        _ = bag.telemetry
        _ = bag.errorReporter
    }

    @Test func previewFactoryConstructs() {
        let bag = MinesweeperAppComposition.preview()
        _ = bag.routeFactory
        _ = bag.telemetry
        _ = bag.errorReporter
    }

    @Test func previewTelemetrySmokeObserve() async {
        // Empty-sinks Telemetry must absorb an observe() call without crashing.
        let bag = MinesweeperAppComposition.preview()
        await bag.telemetry.observe(
            .errorOccurred(source: "test", code: "smoke", message: "noop")
        )
    }

    @Test func previewErrorReporterSmokeReport() async {
        // NoopErrorReporter must absorb a report() call without crashing.
        let bag = MinesweeperAppComposition.preview()
        struct DummyError: Error {}
        await bag.errorReporter.report(
            .unknown,
            underlying: DummyError(),
            source: "test"
        )
    }
}
