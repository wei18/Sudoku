// MinesweeperAppCompositionTests — sentinel coverage for the `.live()` and
// `.preview()` factories.
//
// 2026-06-02 (Track A): Telemetry + ErrorReporter seam; shape-only coverage.
// 2026-06-03 (Phase 3): MS monetization wire fields — persistence, IAP,
// AdGate, MonetizationStateController, ToastController.
//
// Shape coverage is appropriate here: the bag is a struct of DI handles;
// behavior tests for each component live in the component's own test target.

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
        _ = bag.persistence
        _ = bag.adProvider
        _ = bag.iapClient
        _ = bag.adGate
        _ = bag.monetizationStateStore
        _ = bag.monetizationController
        _ = bag.toastController
    }

    @Test func previewFactoryConstructs() {
        let bag = MinesweeperAppComposition.preview()
        _ = bag.routeFactory
        _ = bag.telemetry
        _ = bag.errorReporter
        _ = bag.persistence
        _ = bag.adProvider
        _ = bag.iapClient
        _ = bag.adGate
        _ = bag.monetizationStateStore
        _ = bag.monetizationController
        _ = bag.toastController
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

    @Test func monetizationControllerUsesMSProductId() {
        // Sanity: the parameterised `productId` flows through. Fallback
        // display price = "$2.99" because availableProducts is empty before
        // `bootstrap()` runs.
        let bag = MinesweeperAppComposition.preview()
        #expect(bag.monetizationController.removeAdsDisplayPrice == "$2.99")
        #expect(minesweeperRemoveAdsProductId == "com.wei18.minesweeper.iap.remove_ads")
    }
}
