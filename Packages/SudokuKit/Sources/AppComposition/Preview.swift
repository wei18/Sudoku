// Preview composition — fakes for SwiftUI #Preview.
//
// All factories return deterministic in-memory state. No CloudKit, no
// GameKit, no OSLog. Mirrors `.tests()` semantically; kept as a separate
// entry purely so future Preview-only tweaks (canned snapshots etc.) can
// land without affecting unit/snapshot test behavior.

internal import Foundation
internal import MonetizationCore
internal import MonetizationTesting
internal import SudokuKitTesting
internal import GameCenterTesting  // Stage 3: FakeGameCenterClient (was in SudokuKitTesting)
internal import SudokuUI
internal import Telemetry

extension AppComposition {

    public static func preview() -> AppComposition {
        fakeComposition()
    }

    public static func tests() -> AppComposition {
        fakeComposition()
    }

    internal static func fakeComposition() -> AppComposition {
        let gameCenter = FakeGameCenterClient()
        let persistence = FakePersistence()
        let puzzleProvider = FakePuzzleProvider()
        let telemetry = Telemetry(sinks: [])
        // M10 (issue #67): preview / tests reporter is a Noop — Preview hosts
        // must stay zero-IO, and tests that need to observe reports inject a
        // `FakeErrorReporter` directly through the affected VM init.
        let errorReporter: any ErrorReporter = NoopErrorReporter()

        // v2 monetization fakes.
        let adProvider: any AdProvider = FakeAdProvider()
        let iapClient: any IAPClient = FakeIAPClient()
        let adGateStore: any AdGateStateStore = FakeAdGateStateStore(
            initial: AdGateState(firstLaunchAt: Date(timeIntervalSince1970: 0))
        )
        let adGate = AdGate(store: adGateStore)

        let toastController = ToastController()

        let monetizationController = MonetizationStateController(
            iapClient: iapClient,
            stateStore: adGateStore,
            adGate: adGate,
            toastController: toastController
        )

        let rootViewModel = RootViewModel(
            gameCenter: gameCenter,
            persistence: persistence,
            errorReporter: errorReporter
        )

        let routeFactory = LiveRouteFactory(
            puzzleProvider: puzzleProvider,
            persistence: persistence,
            gameCenter: gameCenter,
            telemetry: telemetry,
            errorReporter: errorReporter,
            adProvider: adProvider,
            iapClient: iapClient,
            adGate: adGate,
            monetizationController: monetizationController,
            toastController: toastController
        )

        return AppComposition(
            rootViewModel: rootViewModel,
            routeFactory: routeFactory,
            puzzleProvider: puzzleProvider,
            persistence: persistence,
            gameCenter: gameCenter,
            telemetry: telemetry,
            errorReporter: errorReporter,
            adProvider: adProvider,
            iapClient: iapClient,
            adGate: adGate,
            monetizationStateStore: adGateStore,
            monetizationController: monetizationController,
            toastController: toastController
        )
    }
}
