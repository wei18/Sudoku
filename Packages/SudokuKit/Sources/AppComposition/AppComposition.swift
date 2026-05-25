// AppComposition — DI composition root (docs/v1/design.md §How.1).
//
// Three factory methods produce a fully-wired `AppComposition` for the
// three environments the App needs to run in:
//
//   - `.live()`    — CloudKit / GameKit / OSLog / AdMob / StoreKit2 wiring.
//   - `.preview()` — SwiftUI Preview fakes (no IO).
//   - `.tests()`   — Unit / snapshot test fakes (no IO).
//
// The App target depends only on this product; `SudokuApp.body` reads
// the bag's properties and hands them to `RootView`.
//
// Stored shape (v2.3.3):
//   - `rootViewModel` + `routeFactory` are what `RootView.init` reads.
//   - The remaining protocol deps (puzzleProvider / persistence / gameCenter
//     / telemetry / adProvider / iapClient / adGate) stay accessible on the
//     bag for callers that need direct references (e.g. App-level boot order
//     in v2.3.7, individual destination views that escape the RouteFactory
//     such as HomeView's Game Center modal callback in v2.3.4-6).

internal import AdsAdMob
internal import Foundation
public import GameCenterClient
public import MonetizationCore
public import Persistence
public import PuzzleStore
public import SudokuUI
public import Telemetry

@MainActor
public struct AppComposition {
    public let rootViewModel: RootViewModel
    public let routeFactory: any RouteFactory
    public let puzzleProvider: any PuzzleProviderProtocol
    public let persistence: any PersistenceProtocol
    public let gameCenter: any GameCenterClient
    public let telemetry: Telemetry
    /// M10 (issue #67): unified error funnel. Live wiring constructs a
    /// `LiveErrorReporter` over the shared `Telemetry` actor; `.preview()`
    /// and `.tests()` wire `NoopErrorReporter`. VMs that previously
    /// `try?`-swallowed CloudKit / Persistence errors now route through
    /// this reporter so failures surface in OSLog + telemetry breadcrumbs.
    public let errorReporter: any ErrorReporter
    // v2 monetization deps. v2.3.4-6 read these directly from individual Views
    // (banner slot, IAP CTAs, restore button); v2.3.7 reads them to drive the
    // UMP → ATT → AdMob boot sequence.
    public let adProvider: any AdProvider
    public let iapClient: any IAPClient
    public let adGate: AdGate
    // v2.3.6: the persisted MonetizationState store + the shared @Observable
    // controller derived from it. Settings + HomeView read the controller
    // directly; `monetizationStateStore` stays exposed so future Views
    // (e.g. v2.4 purchase entry from CompletionView) can rebuild a controller
    // without re-routing through Persistence.
    public let monetizationStateStore: any AdGateStateStore
    public let monetizationController: MonetizationStateController
    // v2.4.5: shared toast surface. RootView mounts this as a bottom overlay;
    // MonetizationStateController pushes success / failure toasts on purchase
    // and restore (and on out-of-band `purchaseUpdates()` events).
    public let toastController: ToastController

    public init(
        rootViewModel: RootViewModel,
        routeFactory: any RouteFactory,
        puzzleProvider: any PuzzleProviderProtocol,
        persistence: any PersistenceProtocol,
        gameCenter: any GameCenterClient,
        telemetry: Telemetry,
        errorReporter: any ErrorReporter = NoopErrorReporter(),
        adProvider: any AdProvider,
        iapClient: any IAPClient,
        adGate: AdGate,
        monetizationStateStore: any AdGateStateStore,
        monetizationController: MonetizationStateController,
        toastController: ToastController
    ) {
        self.rootViewModel = rootViewModel
        self.routeFactory = routeFactory
        self.puzzleProvider = puzzleProvider
        self.persistence = persistence
        self.gameCenter = gameCenter
        self.telemetry = telemetry
        self.errorReporter = errorReporter
        self.adProvider = adProvider
        self.iapClient = iapClient
        self.adGate = adGate
        self.monetizationStateStore = monetizationStateStore
        self.monetizationController = monetizationController
        self.toastController = toastController
    }

    // MARK: - v2.3.7 boot order

    /// App-launch monetization boot. Runs UMP consent → ATT prompt → AdMob
    /// SDK initialize in that order. Each step is attempted independently;
    /// a failing earlier step never blocks later steps (banner gate will
    /// surface `.failed` honestly while AdMob is still un-initialized).
    ///
    /// Callable from `.task` on the root scene — the boot runs concurrently
    /// with first-frame rendering, never blocks UI.
    public func bootMonetization() async {
        #if !os(iOS)
        // AdMob + UMP are iOS-only (Google's xcframeworks ship iOS slices
        // only — see PR #101 for the conditional dep wiring). On macOS /
        // other platforms, `NoopAdProvider` is wired in Live.swift and the
        // UMP / ATT bridges always return `.unsupported`, which the
        // coordinator's failure path would otherwise misclassify as a
        // runtime fault and fan into `Telemetry.errorOccurred` (2 spurious
        // breadcrumbs per cold launch). Nothing to initialize here.
        return
        #else
        let bridges = MonetizationBootBridges.live(adProvider: adProvider)
        let telemetryHandle = telemetry
        let coordinator = MonetizationBootCoordinator(
            bridges: bridges,
            log: { outcome in
                // Telemetry's typed catalog does not have an "info"/"trace"
                // case suited to boot-sequence breadcrumbs, so we only fan
                // failures into Telemetry.observe(.errorOccurred(...)); the
                // success path takes the `print` fallback per spec §boot
                // notes. (See impl-notes §未決 — promoting boot events to
                // a first-class TelemetryEvent case is deferred to v2.4.)
                if !outcome.succeeded {
                    Task {
                        await telemetryHandle.observe(
                            .errorOccurred(
                                source: "MonetizationBoot",
                                code: outcome.step.rawValue,
                                message: outcome.errorDescription ?? "unknown"
                            )
                        )
                    }
                } else {
                    print("[MonetizationBoot] step=\(outcome.step.rawValue) succeeded")
                }
            }
        )
        await coordinator.boot()
        #endif
    }
}
