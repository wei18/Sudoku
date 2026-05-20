// CompositionTests — phase 9.1: AppComposition.live / .preview / .tests
// produce fully-wired AppComposition values.
//
// Live wiring goes through CloudKit / GameKit constructors; we do NOT
// invoke any IO method (no `await persistence.bootstrap()`). The tests
// only check that all factory closures are present and that .preview /
// .tests use fakes (typecheck via Mirror inspection on the rootViewModel).

import Foundation
import Testing
import GameCenterClient
import Persistence
import SudokuKitTesting
@testable import AppComposition

@MainActor
@Suite("AppComposition — live / preview / tests wiring")
struct CompositionTests {

    @Test
    func liveCompositionWiresAllProtocols() async {
        let composition = AppComposition.live()
        // RootViewModel is constructed; factories are non-nil.
        _ = composition.rootViewModel
        _ = composition.dailyHubViewModelFactory
        _ = composition.practiceHubViewModelFactory
        _ = composition.gameViewModelFactory
        _ = composition.completionViewModelFactory
        _ = composition.leaderboardViewModelFactory
        _ = composition.settingsViewModelFactory

        // The Mirror children of RootViewModel expose the injected
        // collaborators by stored-property name; assert live types.
        let mirror = Mirror(reflecting: composition.rootViewModel)
        let gcChild = mirror.children.first(where: { $0.label == "gameCenter" })?.value
        let persistChild = mirror.children.first(where: { $0.label == "persistence" })?.value
        #expect(gcChild != nil)
        #expect(persistChild != nil)
        // Use type-name string as a cheap discriminator (no `is` check —
        // the protocol existentials erase the concrete actor type).
        #expect(String(describing: type(of: gcChild!)).contains("LiveGameCenterClient"))
        #expect(String(describing: type(of: persistChild!)).contains("LivePersistence"))
    }

    @Test
    func previewCompositionUsesFakes() async {
        let composition = AppComposition.preview()
        let mirror = Mirror(reflecting: composition.rootViewModel)
        let gcChild = mirror.children.first(where: { $0.label == "gameCenter" })?.value
        let persistChild = mirror.children.first(where: { $0.label == "persistence" })?.value
        #expect(String(describing: type(of: gcChild!)).contains("FakeGameCenterClient"))
        #expect(String(describing: type(of: persistChild!)).contains("FakePersistence"))
    }

    @Test
    func testsCompositionUsesFakes() async {
        let composition = AppComposition.tests()
        let mirror = Mirror(reflecting: composition.rootViewModel)
        let gcChild = mirror.children.first(where: { $0.label == "gameCenter" })?.value
        let persistChild = mirror.children.first(where: { $0.label == "persistence" })?.value
        #expect(String(describing: type(of: gcChild!)).contains("FakeGameCenterClient"))
        #expect(String(describing: type(of: persistChild!)).contains("FakePersistence"))
    }
}
