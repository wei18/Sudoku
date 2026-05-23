// Live composition — concrete impls for production. design.md §How.1.
//
// Wires:
//   - LiveGameCenterClient(authDriver: GKAuthDriver())
//   - LivePersistence(...) bound to a PuzzleStore puzzle loader
//   - PuzzleStore() — default LivePuzzleGenerating
//   - Telemetry(sinks: [OSLogSink, NoOpTrackingSink, MetricKitSink])
//   - LiveAdMobAdProvider() / LiveStoreKit2IAPClient() (v2.3.2)
//   - AdGate(store: LivePersistence.monetizationStateStore()) (v2.3.2)
//   - LiveRouteFactory composing all of the above (v2.3.3)

internal import AdsAdMob
internal import Foundation
internal import GameCenterClient
internal import IAPStoreKit2
internal import MonetizationCore
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

        // PuzzleStore (default generator, v1 version).
        let puzzleStore = PuzzleStore()

        // Persistence facade. The puzzle loader closure routes through the
        // same PuzzleStore so SavedGameStore can re-derive a Puzzle from a
        // stored puzzleId (no Puzzle blob in CloudKit).
        let persistence = LivePersistence(
            telemetry: telemetry,
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
        #if os(iOS)
        let adProvider: any AdProvider = LiveAdMobAdProvider()
        #else
        let adProvider: any AdProvider = NoopAdProvider()
        #endif
        // `LiveStoreKit2IAPClient` reports catalog-desync (post-purchase
        // refetch returns empty) through the same Telemetry channel so the
        // M3 placeholder substitution doesn't silently mask a backend issue.
        let iapClient: any IAPClient = LiveStoreKit2IAPClient(
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

        let rootViewModel = RootViewModel(
            gameCenter: gameCenter,
            persistence: persistence
        )

        let routeFactory = LiveRouteFactory(
            puzzleProvider: puzzleStore,
            persistence: persistence,
            gameCenter: gameCenter,
            telemetry: telemetry,
            adProvider: adProvider,
            iapClient: iapClient,
            adGate: adGate,
            monetizationController: monetizationController
        )

        return AppComposition(
            rootViewModel: rootViewModel,
            routeFactory: routeFactory,
            puzzleProvider: puzzleStore,
            persistence: persistence,
            gameCenter: gameCenter,
            telemetry: telemetry,
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
