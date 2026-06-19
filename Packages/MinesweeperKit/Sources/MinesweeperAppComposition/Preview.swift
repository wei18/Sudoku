// Preview composition — fakes for SwiftUI #Preview and tests.
//
// #572: extracted from Live.swift (mirrors Sudoku's AppComposition/Preview.swift).
// All factories return deterministic in-memory state. No CloudKit, no
// GameKit, no OSLog. Mirrors `.live()` field shape so composition tests
// pass without live seams.

internal import Foundation
internal import GameAppKit
internal import GameAudio
internal import GameCenterClient
internal import GameCenterTesting
internal import GameShellUI
internal import MinesweeperUI
internal import MonetizationCore
internal import MonetizationTesting
internal import MonetizationUI
internal import Persistence
internal import PersistenceTesting
internal import Telemetry
internal import SwiftUI

extension MinesweeperAppComposition {

    /// Preview / test wiring: empty-sinks `Telemetry`, fake IAP / AdGate
    /// store / AdProvider, `FakePersistence` (zero-IO — #261) — no Preview
    /// path can trap on a real CloudKit gateway (mirrors Sudoku's Preview).
    public static func preview() -> MinesweeperAppComposition {
        let telemetry = Telemetry(sinks: [])
        let errorReporter: any ErrorReporter = NoopErrorReporter()

        // #291: fake GC client — zero-IO, never touches GameKit.
        let gameCenter: any GameCenterClient = FakeGameCenterClient()

        let persistence = FakePersistence()

        let adProvider: any AdProvider = FakeAdProvider()
        let iapClient: any IAPClient = FakeIAPClient()
        let monetizationStateStore: any AdGateStateStore = FakeAdGateStateStore(
            initial: AdGateState(firstLaunchAt: Date(timeIntervalSince1970: 0))
        )
        let adGate = AdGate(store: monetizationStateStore)

        let toastController = ToastController()

        let monetizationController = MonetizationStateController(
            iapClient: iapClient,
            stateStore: monetizationStateStore,
            adGate: adGate,
            toastController: toastController,
            productId: minesweeperRemoveAdsProductId
        )

        let routeFactory = LiveRouteFactory(
            monetizationController: monetizationController,
            adProvider: adProvider,
            adGate: adGate,
            persistence: persistence,
            gameCenter: gameCenter,
            errorReporter: errorReporter,
            toastController: toastController,
            // #330 P2: preview audio is the silent Noop — zero-IO, never touches
            // AVFoundation / the system audio session. `audioSettings` stays nil so
            // the preview Settings screen is byte-identical (no Sound section).
            soundPlayer: NoopSoundPlaying()
        )

        // #313: preview launch-bootstrap VM over the fake GC client + fake
        // persistence — zero-IO.
        let rootViewModel = MinesweeperRootViewModel(
            gameCenter: gameCenter,
            persistence: persistence,
            errorReporter: errorReporter
        )

        return MinesweeperAppComposition(
            rootViewModel: rootViewModel,
            routeFactory: routeFactory,
            telemetry: telemetry,
            errorReporter: errorReporter,
            gameCenter: gameCenter,
            persistence: persistence,
            adProvider: adProvider,
            iapClient: iapClient,
            adGate: adGate,
            monetizationStateStore: monetizationStateStore,
            monetizationController: monetizationController,
            toastController: toastController
        )
    }

}
