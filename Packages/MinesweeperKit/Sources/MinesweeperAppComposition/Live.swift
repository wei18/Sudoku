// Live + Preview composition for MinesweeperAppComposition.
//
// Mirrors Sudoku's split (`AppComposition/Live.swift` + `Preview.swift`)
// collapsed into one file — the Minesweeper bag is small enough to keep
// both factories adjacent until Game Center / additional surfaces grow.
//
// `.live()` wires:
//   - `Telemetry(sinks: [OSLogSink, NoOpTrackingSink])` — OSLog subsystem
//     `com.wei18.minesweeper`, category `Telemetry`. MetricKit sink
//     intentionally NOT installed yet.
//   - `LiveErrorReporter(telemetry:)`.
//   - `LivePersistence(ckConfig: .minesweeper, ...)` — puzzle loader is a
//     no-op stub; MS has no PuzzleProvider yet and no SavedGame flow
//     hits it. Wired via the `PrivateCKConfig.minesweeper` namespace from
//     PR #257 so the MS zone / subscription IDs never collide with Sudoku.
//   - `LiveStoreKit2IAPClient(knownProductIds: [...])` — MS Remove Ads SKU
//     from PR #258.
//   - `NoopAdProvider` on ALL platforms this round — `LiveAdMobAdProvider`
//     wire deferred to U15 (per dispatch §Out of scope). BoardView banner
//     and AdMob bridge initialization come with U15.
//   - `AdGate(store: persistence.monetizationStateStore(),
//             onPersistenceError: telemetry funnel)`.
//   - `MonetizationStateController(productId: minesweeperRemoveAdsProductId,
//             ...)` — the parameterized init shipped with this PR so the
//             same controller drives MS's ASC product instead of Sudoku's.
//   - `ToastController()` — instantiated but not yet mounted on
//     MinesweeperRoot (U15 follow-up).
//
// `.preview()` wires fakes from MonetizationTesting + `LivePersistence` with
// .minesweeper config (IO is lazy — safe in Previews per its docstring).

internal import Foundation
internal import IAPStoreKit2
internal import MonetizationCore
internal import MonetizationTesting
internal import MonetizationUI
internal import Persistence
internal import Telemetry

extension MinesweeperAppComposition {

    /// Production wiring.
    public static func live() -> MinesweeperAppComposition {
        let telemetry = Telemetry(sinks: [
            OSLogSink(subsystem: "com.wei18.minesweeper", category: "Telemetry"),
            NoOpTrackingSink()
        ])
        let errorReporter: any ErrorReporter = LiveErrorReporter(telemetry: telemetry)

        // Persistence. Puzzle loader is a no-op stub — MS has no
        // PuzzleProvider yet and SavedGameStore.fetch never fires for MS
        // until the save-flow lands (separate dispatch). Throwing on call
        // makes the absence loud if something does call into it.
        let persistence = LivePersistence(
            telemetry: telemetry,
            ckConfig: .minesweeper,
            puzzleLoader: { _ in
                throw MinesweeperLivePuzzleLoaderUnavailable()
            }
        )

        // Monetization state store + AdGate. Same Telemetry funnel shape as
        // Sudoku — `AdGate` doesn't depend on Telemetry directly; we inject
        // the sink via `onPersistenceError`.
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

        // AdProvider: NoopAdProvider on ALL platforms this round. The live
        // AdMob wire is deferred to U15 (banner + bridge work). NoopAdProvider
        // returns `.suppressed` so BannerSlotView collapses to EmptyView once
        // MS mounts one.
        let adProvider: any AdProvider = NoopAdProvider()

        // IAP client. Telemetry-funnels catalog desync into the same channel
        // Sudoku uses so the M3 placeholder substitution doesn't silently
        // mask backend issues.
        let iapClient: any IAPClient = LiveStoreKit2IAPClient(
            knownProductIds: [minesweeperRemoveAdsProductId],
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
            productId: minesweeperRemoveAdsProductId
        )
        // Mirror Sudoku: opt in to lifetime-of-app purchaseUpdates() exactly
        // once at composition.
        monetizationController.startListeningForLifetimeOfApp()

        let routeFactory = LiveRouteFactory(
            monetizationController: monetizationController
        )

        return MinesweeperAppComposition(
            routeFactory: routeFactory,
            telemetry: telemetry,
            errorReporter: errorReporter,
            persistence: persistence,
            adProvider: adProvider,
            iapClient: iapClient,
            adGate: adGate,
            monetizationStateStore: monetizationStateStore,
            monetizationController: monetizationController,
            toastController: toastController
        )
    }

    /// Preview / test wiring. Empty-sinks `Telemetry`, fake IAP / AdGate
    /// store / AdProvider, and `LivePersistence` with `.minesweeper`
    /// config (IO is lazy — safe in zero-IO previews per its docstring).
    public static func preview() -> MinesweeperAppComposition {
        let telemetry = Telemetry(sinks: [])
        let errorReporter: any ErrorReporter = NoopErrorReporter()

        let persistence = LivePersistence(
            telemetry: telemetry,
            ckConfig: .minesweeper,
            puzzleLoader: { _ in
                throw MinesweeperLivePuzzleLoaderUnavailable()
            }
        )

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
            monetizationController: monetizationController
        )

        return MinesweeperAppComposition(
            routeFactory: routeFactory,
            telemetry: telemetry,
            errorReporter: errorReporter,
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

/// Sentinel thrown by the `.live()` / `.preview()` puzzle loader stub. MS
/// has no PuzzleProvider yet; the loader closure only ever fires if
/// `SavedGameStore.fetch(...)` walks a saved record back through it, which
/// can't happen until MS save-flow lands (separate dispatch).
private struct MinesweeperLivePuzzleLoaderUnavailable: Error {}
