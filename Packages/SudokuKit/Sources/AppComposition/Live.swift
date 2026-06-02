// Live composition — concrete impls for production. docs/v1/design.md §How.1.
//
// Wires:
//   - LiveGameCenterClient(authDriver: GKAuthDriver())
//   - LivePersistence(...) bound to a PuzzleStore puzzle loader
//   - PuzzleStore() — default LivePuzzleGenerating
//   - Telemetry(sinks: [OSLogSink, NoOpTrackingSink, MetricKitSink])
//   - LiveAdMobAdProvider(bannerAdUnitID:) / LiveStoreKit2IAPClient(knownProductIds:) (v2.3.2)
//   - AdGate(store: LivePersistence.monetizationStateStore()) (v2.3.2)
//   - LiveRouteFactory composing all of the above (v2.3.3)

internal import AdsAdMob
internal import Foundation
internal import GameCenterClient
internal import IAPStoreKit2
internal import MonetizationCore
internal import MonetizationUI
internal import Persistence
internal import PuzzleStore
internal import SudokuUI
internal import Telemetry

extension AppComposition {

    public static func live() -> AppComposition {
        // Telemetry fan-out: OSLog + NoOp tracking. MetricKit projects its
        // diagnostic payloads BACK INTO this same Telemetry instance via the
        // process-wide retained sink below.
        let telemetry = Telemetry(sinks: [
            OSLogSink(subsystem: "com.wei18.sudoku", category: "Telemetry"),
            NoOpTrackingSink()
        ])
        LiveMetricKitRetainer.install(downstream: telemetry)

        // M10 (issue #67): unified error funnel. All VM / loader catch sites
        // that previously `try?`-swallowed CloudKit / Persistence errors now
        // route through this reporter, which fans into the same Telemetry
        // facade as every other event (so OSLog + future tracking sinks both
        // see the failure) and retains a bounded ring buffer of the most
        // recent 20 reports for future diagnostic surfaces.
        let errorReporter: any ErrorReporter = LiveErrorReporter(telemetry: telemetry)

        // PuzzleStore (default generator, v1 version).
        let puzzleStore = PuzzleStore()

        // Persistence facade. The puzzle loader closure routes through the
        // same PuzzleStore so SavedGameStore can re-derive a Puzzle from a
        // stored puzzleId (no Puzzle blob in CloudKit).
        let persistence = LivePersistence(
            telemetry: telemetry,
            ckConfig: .sudoku,
            puzzleLoader: { puzzleId in
                try await puzzleStore.puzzle(for: puzzleId)
            }
        )

        // Game Center client.
        let gameCenter = LiveGameCenterClient(authDriver: GKAuthDriver())

        // v2 monetization deps.
        let monetizationStateStore = persistence.monetizationStateStore()
        // Route AdGate's CloudKit save failures into the same Telemetry
        // facade other subsystems use. `AdGate` doesn't depend on Telemetry
        // directly — the host injects the sink so MonetizationCore stays
        // observability-stack-free (M2 from v2-audit-code-polish).
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
        // AdMob SDK ships iOS-only binaries — see AppMonetizationKit/Package.swift
        // gating. On macOS we wire the `NoopAdProvider` (status always
        // `.suppressed`, BannerSlotView collapses to EmptyView); on iOS we use
        // the live AdMob-backed provider as before.
        //
        // Sudoku-specific identifiers (banner ad unit + ASC product IDs) are
        // declared here, NOT inside AppMonetizationKit, so the package can be
        // linked by a second app (Minesweeper) without baking Sudoku IDs into
        // its binary. See `meetings/2026-05-31_minesweeper-rfc.md` §5.2.
        //
        let sudokuRemoveAdsProductID = "com.wei18.sudoku.iap.remove_ads"

        #if os(iOS)
        // DEBUG vs Release swap for the banner ad unit ID: v2.5.2 ships with
        // Google's universal TEST banner; v2.5.3 (user-owned, pre-ASC) swaps
        // to Sudoku's production unit. The `GADApplicationIdentifier` in
        // `App/Info.plist` follows the same swap. The `fatalError` is
        // intentional and EAGER — any Release/iOS build constructed before
        // v2.5.3 production wiring crashes at composition-root construction
        // (immediately-invoked closure), surfacing the misconfiguration on
        // first launch / smoke test rather than later at first ad impression.
        // See `docs/v2/v2.5-readiness.md §v2.5.3` for the paired-flip checklist.
        #if DEBUG
        let sudokuBannerAdUnitID = "ca-app-pub-3940256099942544/2934735716"  // Google test
        #else
        let sudokuBannerAdUnitID: String = {
            fatalError("REPLACE_IN_v2.5.3: production AdMob banner ad unit ID not wired — see docs/v2/v2.5-readiness.md §v2.5.3")
        }()
        #endif
        let adProvider: any AdProvider = LiveAdMobAdProvider(bannerAdUnitID: sudokuBannerAdUnitID)
        #else
        let adProvider: any AdProvider = NoopAdProvider()
        #endif
        // `LiveStoreKit2IAPClient` reports catalog-desync (post-purchase
        // refetch returns empty) through the same Telemetry channel so the
        // M3 placeholder substitution doesn't silently mask a backend issue.
        let iapClient: any IAPClient = LiveStoreKit2IAPClient(
            knownProductIds: [sudokuRemoveAdsProductID],
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

        // v2.3.6: shared @Observable controller for Settings + HomeView's
        // Remove Ads surfaces. Constructed eagerly so both views observe the
        // same instance; `.bootstrap()` is invoked lazily inside each View's
        // `.task` modifier.
        // v2.4.5: shared toast surface. Constructed before the controller so
        // we can inject it; RootView mounts the same instance as a bottom
        // overlay.
        let toastController = ToastController()

        let monetizationController = MonetizationStateController(
            iapClient: iapClient,
            stateStore: monetizationStateStore,
            adGate: adGate,
            toastController: toastController
        )
        // Fix B (RCA 2026-05-25): bootstrap() no longer auto-subscribes
        // to `purchaseUpdates()`. Production opts in here, exactly once,
        // for the lifetime of the app. Tests opt in per-test + tear down
        // via `FakeIAPClient.finishUpdates()`.
        monetizationController.startListeningForLifetimeOfApp()

        let rootViewModel = RootViewModel(
            gameCenter: gameCenter,
            persistence: persistence,
            errorReporter: errorReporter
        )

        let routeFactory = LiveRouteFactory(
            puzzleProvider: puzzleStore,
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
            puzzleProvider: puzzleStore,
            persistence: persistence,
            gameCenter: gameCenter,
            telemetry: telemetry,
            errorReporter: errorReporter,
            adProvider: adProvider,
            iapClient: iapClient,
            adGate: adGate,
            monetizationStateStore: monetizationStateStore,
            monetizationController: monetizationController,
            toastController: toastController
        )
    }

}

/// Process-wide retainer for `MetricKitSink` — MXMetricManager's subscriber
/// list holds a weak reference, so we must keep the sink alive ourselves
/// for the lifetime of the App. Installation is idempotent.
private enum LiveMetricKitRetainer {
    nonisolated(unsafe) private static var sink: MetricKitSink?
    private static let lock = NSLock()

    static func install(downstream: Telemetry) {
        lock.lock()
        defer { lock.unlock() }
        guard sink == nil else { return }
        let metricSink = MetricKitSink(downstream: downstream)
        // Skip system registration in test environments — MXMetricManager
        // is unavailable outside a properly entitled app bundle and would
        // crash the test process. Detection: swift-testing / XCTest sets
        // `XCTestConfigurationFilePath`.
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil {
            metricSink.startReceivingSystemReports()
        }
        sink = metricSink
    }
}
