// Live + Preview composition for Game2048AppComposition.
//
// Mirrors MinesweeperAppComposition/Live.swift; deferred items vs MS:
//   - No audio (#330-equivalent deferred for Tiles2048 post-M4)
//   - No reminders (no daily-ready fire-time concept for 2048 yet)
//   - No `.live()` puzzle loader (2048 has no PuzzleProvider; resume goes
//     through Game2048Persistence, not Sudoku-shaped SavedGameStore.loadOrCreate)
//
// `.live()` wires Telemetry (OSLog com.wei18.tiles2048) + LiveErrorReporter,
// LivePersistence (tiles2048 namespace) + Game2048SavedGameStore (M4 resume),
// LiveStoreKit2IAPClient (Tiles2048 Remove Ads), LiveAdMobAdProvider on iOS /
// NoopAdProvider on macOS, AdGate + MonetizationStateController, ToastController.
//
// `.preview()` wires MonetizationTesting fakes + FakePersistence (zero-IO).

internal import AdsAdMob
internal import Foundation
internal import GameCenterClient
internal import GameCenterTesting
internal import Game2048Persistence
internal import Game2048UI
internal import IAPStoreKit2
internal import MonetizationCore
internal import MonetizationTesting
internal import MonetizationUI
internal import Persistence
internal import PersistenceTesting
internal import Telemetry

extension Game2048AppComposition {

    /// Production wiring.
    public static func live() -> Game2048AppComposition {
        let telemetry = Telemetry(sinks: [
            OSLogSink(subsystem: "com.wei18.tiles2048", category: "Telemetry"),
            NoOpTrackingSink()
        ])
        let errorReporter: any ErrorReporter = LiveErrorReporter(telemetry: telemetry)

        // Game Center client. Shared GameCenterKit seam — GameKit is fully
        // encapsulated inside `LiveGameCenterClient` / `GKAuthDriver`. The
        // board VM submits daily score on stuck; Home Leaderboard card presents
        // the native dashboard.
        let gameCenter: any GameCenterClient = LiveGameCenterClient(authDriver: GKAuthDriver())

        // Persistence. Tiles2048 has no PuzzleProvider; its resume path goes
        // through Game2048Persistence, never through Sudoku-shaped
        // SavedGameStore.loadOrCreate. Throwing on call makes the absence loud.
        let persistence = LivePersistence(
            telemetry: telemetry,
            ckConfig: .tiles2048,
            puzzleLoader: { _ in
                throw Game2048LivePuzzleLoaderUnavailable()
            }
        )

        // Monetization state store + AdGate. Same Telemetry funnel shape as
        // Sudoku / Minesweeper.
        let monetizationStateStore = persistence.monetizationStateStore()
        let adGate = AdGate(
            store: monetizationStateStore,
            onPersistenceError: { [telemetry] error in
                Task {
                    await telemetry.observe(
                        .errorOccurred(
                            source: "AdGate",
                            code: "save_failed",
                            message: String(describing: error)
                        )
                    )
                }
            }
        )

        // AdProvider: live AdMob on iOS, Noop on macOS (AdMob SDK ships an
        // iOS-only xcframework). Tiles2048-specific identifiers live here (banner
        // ad unit), NOT inside AppMonetizationKit. The GADBannerUnitID key is
        // substituted at build time from Tuist/AdMob.xcconfig (gitignored;
        // .example committed). Mirrors MS Live.swift guard exactly.
        #if os(iOS)
        guard
            let tiles2048BannerAdUnitID = Bundle.main
                .object(forInfoDictionaryKey: "GADBannerUnitID") as? String,
            !tiles2048BannerAdUnitID.isEmpty,
            !tiles2048BannerAdUnitID.hasPrefix("$(")
        else {
            preconditionFailure(
                "GADBannerUnitID missing or unresolved — check"
                    + " Tuist/AdMob.xcconfig exists locally or that XCC env"
                    + " vars are set for Release builds."
            )
        }
        let adProvider: any AdProvider = LiveAdMobAdProvider(bannerAdUnitID: tiles2048BannerAdUnitID)
        #else
        let adProvider: any AdProvider = NoopAdProvider()
        #endif

        // IAP client. Telemetry-funnels catalog desync into the same channel
        // Sudoku / Minesweeper use.
        let iapClient: any IAPClient = LiveStoreKit2IAPClient(
            knownProductIds: [tiles2048RemoveAdsProductId],
            onCatalogDesync: { [telemetry] productId in
                Task {
                    await telemetry.observe(
                        .errorOccurred(
                            source: "LiveStoreKit2IAPClient",
                            code: "catalog_desync_post_purchase",
                            message: "post-purchase refetch returned empty for productId=\(productId)"
                        )
                    )
                }
            }
        )

        let toastController = ToastController()

        let monetizationController = MonetizationStateController(
            iapClient: iapClient,
            stateStore: monetizationStateStore,
            adGate: adGate,
            toastController: toastController,
            productId: tiles2048RemoveAdsProductId
        )
        // Mirror Sudoku / MS: opt in to lifetime-of-app purchaseUpdates() once.
        monetizationController.startListeningForLifetimeOfApp()

        // M4 saved-game store over the public gateway factory (same
        // container/zone `LivePersistence.bootstrap()` provisions).
        let savedGameStore = Game2048SavedGameStore(
            gateway: PrivateCKGatewayFactory.live(config: .tiles2048),
            telemetry: telemetry
        )

        // Launch-bootstrap VM (GC auth + persistence bootstrap). Constructed
        // before routeFactory so `onPresentBoard` can capture it without a
        // forward-reference — mirrors MinesweeperAppComposition.live().
        let rootViewModel = Game2048RootViewModel(
            gameCenter: gameCenter,
            persistence: persistence,
            errorReporter: errorReporter,
            fetchResume: makeFetchResume(store: savedGameStore)
        )

        let routeFactory = LiveRouteFactory(
            monetizationController: monetizationController,
            adProvider: adProvider,
            adGate: adGate,
            persistence: persistence,
            gameCenter: gameCenter,
            errorReporter: errorReporter,
            toastController: toastController,
            savedGameStore: savedGameStore,
            // SDD-003 Epic 1 board-modal pattern: on iOS present board as
            // fullScreenCover via GameRootViewModel.presentGame(route:).
            onPresentBoard: {
                #if os(iOS)
                { [rootViewModel] route in rootViewModel.presentGame(route: route) }
                #else
                nil
                #endif
            }()
        )

        return Game2048AppComposition(
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

    /// Preview / test wiring: empty-sinks `Telemetry`, fake IAP / AdGate
    /// store / AdProvider, `FakePersistence` (zero-IO) — no Preview path can
    /// trap on a real CloudKit gateway (mirrors MS Preview).
    public static func preview() -> Game2048AppComposition {
        let telemetry = Telemetry(sinks: [])
        let errorReporter: any ErrorReporter = NoopErrorReporter()

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
            productId: tiles2048RemoveAdsProductId
        )

        let routeFactory = LiveRouteFactory(
            monetizationController: monetizationController,
            adProvider: adProvider,
            adGate: adGate,
            persistence: persistence,
            gameCenter: gameCenter,
            errorReporter: errorReporter,
            toastController: toastController
        )

        let rootViewModel = Game2048RootViewModel(
            gameCenter: gameCenter,
            persistence: persistence,
            errorReporter: errorReporter
        )

        return Game2048AppComposition(
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

/// Sentinel thrown by the `.live()` puzzle loader stub — Tiles2048 has no
/// PuzzleProvider; its resume path goes through `Game2048Persistence`, never
/// through Sudoku-shaped `SavedGameStore.loadOrCreate`.
private struct Game2048LivePuzzleLoaderUnavailable: Error {}
