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
//   - `LiveAdMobAdProvider` on iOS (DEBUG = Google universal test banner,
//     Release = fatalError gate per Sudoku precedent until v1 release
//     checklist swaps in MS production banner id from project memory
//     `minesweeper-admob-ids`); `NoopAdProvider` on macOS (AdMob SDK is
//     iOS-only). Wired in U15 (2026-06-03).
//   - `AdGate(store: persistence.monetizationStateStore(),
//             onPersistenceError: telemetry funnel)`.
//   - `MonetizationStateController(productId: minesweeperRemoveAdsProductId,
//             ...)` — the parameterized init shipped with this PR so the
//             same controller drives MS's ASC product instead of Sudoku's.
//   - `ToastController()` — mounted on MinesweeperRoot via `.toastOverlay`
//     (wired in U15 / PR #263; surfaced through `composition.rootView`).
//
// `.preview()` wires fakes from MonetizationTesting + `LivePersistence` with
// .minesweeper config (IO is lazy — safe in Previews per its docstring).

internal import AdsAdMob
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

        // AdProvider: live AdMob on iOS, Noop on macOS (AdMob SDK ships an
        // iOS-only xcframework — see AppMonetizationKit/Package.swift gating).
        // Mirrors Sudoku's `Live.swift` shape exactly. MS-specific identifiers
        // live here (banner ad unit), NOT inside AppMonetizationKit, so the
        // package can be linked by Sudoku without baking MS IDs into its
        // binary (and vice-versa). The DEBUG-gate keeps debug builds on
        // Google's universal test banner so real-device verification never
        // accidentally serves production creatives. Release builds use MS's
        // production banner unit registered with the AdMob console.
        #if os(iOS)
        // Banner ad unit ID via Info.plist `GADBannerUnitID` key, substituted
        // at build time from `Tuist/AdMob.xcconfig` (gitignored; .example
        // committed). XCC writes the xcconfig from per-workflow env vars;
        // local builds use the .example sandbox values. Replaces the old
        // DEBUG-vs-Release fatalError gate with smoke-test (key presence —
        // `MinesweeperUITests/InfoPlistAdMobKeysTests`) + runtime guard
        // below (catches missing-key + empty + unresolved-`$()` token
        // before AdMob SDK init).
        guard
            let minesweeperBannerAdUnitID = Bundle.main
                .object(forInfoDictionaryKey: "GADBannerUnitID") as? String,
            !minesweeperBannerAdUnitID.isEmpty,
            !minesweeperBannerAdUnitID.hasPrefix("$(")
        else {
            preconditionFailure(
                "GADBannerUnitID missing or unresolved — check"
                    + " Tuist/AdMob.xcconfig exists locally or that XCC env"
                    + " vars are set for Release builds."
            )
        }
        let adProvider: any AdProvider = LiveAdMobAdProvider(bannerAdUnitID: minesweeperBannerAdUnitID)
        #else
        let adProvider: any AdProvider = NoopAdProvider()
        #endif

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
            monetizationController: monetizationController,
            adProvider: adProvider,
            adGate: adGate
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
            monetizationController: monetizationController,
            adProvider: adProvider,
            adGate: adGate
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
