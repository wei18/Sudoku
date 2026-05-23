// CompositionTests — phase 9.1 + v2.3.2/3: AppComposition.live / .preview /
// .tests produce fully-wired AppComposition values.
//
// Live wiring goes through CloudKit / GameKit / AdMob / StoreKit2 constructors;
// we do NOT invoke any IO method. The tests only check that all factory
// closures are present and that .preview / .tests use fakes (typecheck via
// Mirror inspection).

import Foundation
import Testing
import GameCenterClient
import MonetizationCore
import Persistence
import SudokuKitTesting
@testable import AppComposition

@MainActor
@Suite("AppComposition — live / preview / tests wiring")
struct CompositionTests {

    @Test
    func liveCompositionWiresAllProtocols() async {
        let composition = AppComposition.live()
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
        let composition = AppComposition.live()
        // v2.3.2: all three monetization stored properties resolve to Live impls.
        // On non-iOS platforms (macOS) AdMob's xcframework has no platform
        // slice, so the live composition wires `NoopAdProvider` instead of
        // `LiveAdMobAdProvider`. IAP via StoreKit 2 is cross-platform and
        // keeps its live wiring on every platform.
        #if os(iOS)
        #expect(String(describing: type(of: composition.adProvider)).contains("LiveAdMobAdProvider"))
        #else
        #expect(String(describing: type(of: composition.adProvider)).contains("NoopAdProvider"))
        #endif
        #expect(String(describing: type(of: composition.iapClient)).contains("LiveStoreKit2IAPClient"))
        // adGate is the same concrete type for both live + preview (it is
        // injection-driven via its store), so type identity here is just
        // a smoke that the property exists and is reachable.
        _ = composition.adGate
    }

    @Test
    func liveCompositionExposesRouteFactory() async {
        let composition = AppComposition.live()
        #expect(String(describing: type(of: composition.routeFactory)).contains("LiveRouteFactory"))
    }

    @Test
    func previewCompositionUsesFakes() async {
        let composition = AppComposition.preview()
        let mirror = Mirror(reflecting: composition.rootViewModel)
        let gcChild = mirror.children.first(where: { $0.label == "gameCenter" })?.value
        let persistChild = mirror.children.first(where: { $0.label == "persistence" })?.value
        #expect(String(describing: type(of: gcChild!)).contains("FakeGameCenterClient"))
        #expect(String(describing: type(of: persistChild!)).contains("FakePersistence"))
        #expect(String(describing: type(of: composition.adProvider)).contains("FakeAdProvider"))
        #expect(String(describing: type(of: composition.iapClient)).contains("FakeIAPClient"))
    }

    @Test
    func testsCompositionUsesFakes() async {
        let composition = AppComposition.tests()
        let mirror = Mirror(reflecting: composition.rootViewModel)
        let gcChild = mirror.children.first(where: { $0.label == "gameCenter" })?.value
        let persistChild = mirror.children.first(where: { $0.label == "persistence" })?.value
        #expect(String(describing: type(of: gcChild!)).contains("FakeGameCenterClient"))
        #expect(String(describing: type(of: persistChild!)).contains("FakePersistence"))
        #expect(String(describing: type(of: composition.adProvider)).contains("FakeAdProvider"))
        #expect(String(describing: type(of: composition.iapClient)).contains("FakeIAPClient"))
    }
}
