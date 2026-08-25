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
import MinesweeperEngine
import MinesweeperUI
import MonetizationCore
import MonetizationTesting
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

    @Test func liveAdProviderIsLiveOnIOSNoopOnMac() {
        // U15 (2026-06-03): `.live()` swaps `NoopAdProvider` for the real
        // `LiveAdMobAdProvider` on iOS. macOS keeps Noop since the Google
        // Mobile Ads SDK ships an iOS-only xcframework.
        let bag = MinesweeperAppComposition.live()
        let providerType = String(describing: type(of: bag.adProvider))
        #if os(iOS)
        #expect(providerType.contains("LiveAdMobAdProvider"))
        #else
        #expect(providerType.contains("NoopAdProvider"))
        #endif
    }

    @Test func liveCompositionGatesSettingsMonetizationControllerByPlatform() {
        // #971 (Guideline 2.1): macOS has zero ads to remove — Live.swift's
        // `makeRouteFactory` must pass `nil` for the Settings route's
        // `monetizationController` on macOS so "Remove Ads" / "Restore
        // Purchases" never render there, while `bag.monetizationController`
        // itself (this composition's own stored property, exercised below)
        // stays wired unconditionally on every platform. Reaching through
        // `.live()` → the real `routeFactory.view(for:)` exercises the
        // actual `#if os(iOS)` gate in `Live.swift` — NOT a copy of it — so
        // deleting that gate flips this assertion on whichever platform
        // built the test (`swift test` always builds macOS host regardless
        // of the package's iOS support, so the `#else` branch below is what
        // a local `swift test` run actually pins). Mirrors
        // `SudokuAppCompositionTests`'s analogous test.
        let bag = MinesweeperAppComposition.live()
        // Composition-level DI handle stays non-nil on every platform — only
        // the LOCAL passed into the Settings route factory is gated.
        _ = bag.monetizationController
        let dump = String(reflecting: bag.routeFactory.view(for: .settings))
        #if os(iOS)
        #expect(!dump.contains("monetizationController: nil"))
        #else
        #expect(dump.contains("monetizationController: nil"))
        #endif
    }

    @Test func monetizationControllerUsesMSProductId() {
        // Sanity: the parameterised `productId` flows through. Fallback
        // display price = "$0.99" because availableProducts is empty before
        // `bootstrap()` runs.
        let bag = MinesweeperAppComposition.preview()
        #expect(bag.monetizationController.removeAdsDisplayPrice == "$0.99")
        #expect(minesweeperRemoveAdsProductId == "com.wei18.minesweeper.iap.remove_ads")
    }

    @Test func monetizationControllerReadsMSProductDisplayPrice() async throws {
        // Proves the controller is wired to `minesweeperRemoveAdsProductId`:
        // seed a product under that id with a price that differs from the
        // "$0.99" empty-catalog fallback, bootstrap, and assert the real price
        // surfaces. If the controller were constructed with Sudoku's productId,
        // the lookup would miss and fall back — failing this test.
        let bag = MinesweeperAppComposition.preview()
        let fake = try #require(bag.iapClient as? FakeIAPClient)
        await fake.setProducts([
            IAPProduct(
                id: minesweeperRemoveAdsProductId,
                displayName: "Remove Ads",
                displayPrice: "$4.99",
                isPurchased: false
            )
        ])
        await bag.monetizationController.bootstrap()
        #expect(bag.monetizationController.removeAdsDisplayPrice == "$4.99")
    }

    #if DEBUG
    // #1026 B-1: `uitestRoute(for:)` is the DEBUG-only `-uitest-route` key
    // resolver — zero-click macOS access to a sized practice board.

    @Test(arguments: Difficulty.allCases)
    func uitestRouteBoardResolvesToFixedSeedPracticeBoard(_ difficulty: Difficulty) {
        #expect(
            MinesweeperAppComposition.uitestRoute(for: "board:\(difficulty.rawValue)")
                == .board(
                    difficulty: difficulty,
                    seed: MinesweeperAppComposition.uitestBoardSeed,
                    mode: .practice
                )
        )
    }

    @Test(arguments: ["board:bogus", "board:", "board", "board:BEGINNER", "board:expert "])
    func uitestRouteBoardRejectsUnknownOrMalformedKeys(_ key: String) {
        #expect(MinesweeperAppComposition.uitestRoute(for: key) == nil)
    }

    @Test func uitestRoutePracticeStillResolves() {
        // Regression: the new `board:` prefix branch must not shadow the
        // pre-existing exact-match keys.
        #expect(MinesweeperAppComposition.uitestRoute(for: "practice") == .practice)
    }
    #endif
}
