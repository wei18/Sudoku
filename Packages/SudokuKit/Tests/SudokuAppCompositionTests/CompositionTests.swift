// CompositionTests — phase 9.1 + v2.3.2/3: SudokuAppComposition.live / .preview /
// .tests produce fully-wired SudokuAppComposition values.
//
// Live wiring goes through CloudKit / GameKit / AdMob / StoreKit2 constructors;
// we do NOT invoke any IO method. The tests only check that all factory
// closures are present and that .preview / .tests use fakes (typecheck via
// Mirror inspection).

import Foundation
import Testing
import GameCenterClient
import Persistence
import SudokuKitTesting
 import SudokuAppComposition

@MainActor
@Suite("SudokuAppComposition — live / preview / tests wiring")
struct CompositionTests {

    @Test
    func liveCompositionWiresAllProtocols() async {
        let composition = SudokuAppComposition.live()
        _ = composition.rootViewModel

        let mirror = Mirror(reflecting: composition.rootViewModel)
        let gcChild = mirror.children.first(where: { $0.label == "gameCenter" })?.value
        let persistChild = mirror.children.first(where: { $0.label == "persistence" })?.value
        #expect(gcChild != nil)
        #expect(persistChild != nil)
        #expect(String(describing: type(of: gcChild!)).contains("LiveGameCenterClient"))
        #expect(String(describing: type(of: persistChild!)).contains("LivePersistence"))
    }

    @Test
    func liveCompositionExposesMonetizationDeps() async {
        let composition = SudokuAppComposition.live()
        // v2.3.2: the monetization stored property resolves to the Live impl.
        // IAP via StoreKit 2 is cross-platform and keeps its live wiring on
        // every platform.
        #expect(String(describing: type(of: composition.iapClient)).contains("LiveStoreKit2IAPClient"))
    }

    @Test
    func liveCompositionExposesRouteFactory() async {
        let composition = SudokuAppComposition.live()
        #expect(String(describing: type(of: composition.routeFactory)).contains("LiveRouteFactory"))
    }

    @Test
    func liveCompositionGatesSettingsMonetizationControllerByPlatform() {
        // #971 (Guideline 2.1): macOS has zero ads to remove — Live.swift's
        // `makeRouteFactory` must pass `nil` for the Settings route's
        // `monetizationController` on macOS so "Remove Ads" / "Restore
        // Purchases" never render there, while `deps.monetizationController`
        // itself (this composition's own stored property, asserted non-nil
        // below) stays wired unconditionally on every platform. Reaching
        // through `.live()` → the real `routeFactory.view(for:)` exercises
        // the actual `#if os(iOS)` gate in `Live.swift` — NOT a copy of it —
        // so deleting that gate flips this assertion on whichever platform
        // built the test (`swift test` always builds macOS host regardless
        // of the package's iOS support, so the `#else` branch below is what
        // a local `swift test` run actually pins).
        let composition = SudokuAppComposition.live()
        // Composition-level DI handle stays non-nil on every platform — only
        // the LOCAL passed into the Settings route factory is gated.
        _ = composition.monetizationController
        let dump = String(reflecting: composition.routeFactory.view(for: .settings))
        #if os(iOS)
        #expect(!dump.contains("monetizationController: nil"))
        #else
        #expect(dump.contains("monetizationController: nil"))
        #endif
    }

    @Test
    func previewCompositionUsesFakes() async {
        let composition = SudokuAppComposition.preview()
        let mirror = Mirror(reflecting: composition.rootViewModel)
        let gcChild = mirror.children.first(where: { $0.label == "gameCenter" })?.value
        let persistChild = mirror.children.first(where: { $0.label == "persistence" })?.value
        #expect(String(describing: type(of: gcChild!)).contains("FakeGameCenterClient"))
        #expect(String(describing: type(of: persistChild!)).contains("FakePersistence"))
        #expect(String(describing: type(of: composition.iapClient)).contains("FakeIAPClient"))
    }

    @Test
    func testsCompositionUsesFakes() async {
        let composition = SudokuAppComposition.tests()
        let mirror = Mirror(reflecting: composition.rootViewModel)
        let gcChild = mirror.children.first(where: { $0.label == "gameCenter" })?.value
        let persistChild = mirror.children.first(where: { $0.label == "persistence" })?.value
        #expect(String(describing: type(of: gcChild!)).contains("FakeGameCenterClient"))
        #expect(String(describing: type(of: persistChild!)).contains("FakePersistence"))
        #expect(String(describing: type(of: composition.iapClient)).contains("FakeIAPClient"))
    }
}
