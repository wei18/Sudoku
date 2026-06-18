// AppComposition — DI composition root (docs/v1/design.md §How.1).
//
// Three factory methods produce a fully-wired `AppComposition` for the
// three environments the App needs to run in:
//
//   - `.live()`    — CloudKit / GameKit / OSLog / AdMob / StoreKit2 wiring.
//   - `.preview()` — SwiftUI Preview fakes (no IO).
//   - `.tests()`   — Unit / snapshot test fakes (no IO).
//
// The App target depends only on this product; `SudokuApp.body` mounts
// `composition.rootView`, which (since #557) returns the shared view assembled
// by `GameAppKit.makeGameApp` — Sudoku's bespoke `RootView`/`HomeView` are retired.
//
// Stored shape:
//   - `rootViewModel` + `routeFactory` come from the `makeGameAppWithDeps` handle
//     (#556/#557).
//   - The remaining protocol deps (puzzleProvider / persistence / gameCenter
//     / telemetry / adProvider / iapClient / adGate) stay accessible on the
//     bag for callers that need direct references (e.g. App-level boot order,
//     CompositionTests / BootOrderTests).

internal import AdsAdMob
internal import Foundation
public import GameCenterClient
public import GameShellUI
public import MonetizationCore
public import MonetizationUI
public import Persistence
public import SudokuPersistence
public import SudokuUI
public import SwiftUI
public import Telemetry

@MainActor
public struct AppComposition {
    public let rootViewModel: RootViewModel
    public let routeFactory: any RouteFactory<AppRoute>
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
    // #371 / #195: ATT pre-prompt coordinator. Built in `.live()` (wired to
    // `ATTPresenter`); `nil` in `.preview()` / `.tests()`. After #557 the
    // ATT priming sheet is applied universally by makeGameApp on wiredView.
    public let attPrimer: ATTPrimerCoordinator?
    // #557: the fully-wired root view from makeGameApp — GameRoot + shared
    // GameHomeView + ResumePill + ATT sheet + GC alert. Mounted by `rootView`.
    private let wiredView: AnyView

    // MARK: - Root view accessor (#244, #557)

    /// Composed root view ready to mount in `@main`'s `WindowGroup`.
    ///
    /// After #557: `wiredView` (from `makeGameApp`) is the live mount point.
    /// It carries the shared `GameHomeView` + universal ResumePill + ATT sheet
    /// + GC-signed-out alert + monetization boot. Two Sudoku-specific layers
    /// are still applied here (not in makeGameApp, which is game-agnostic):
    ///   - `\.sudokuCell` environment (#278 Tier-1 Phase 2a — board cell tokens)
    ///   - `SudokuNearWinModifier` (#510 DEBUG near-win test hook)
    /// The theme injection (`.environment(\.theme, DefaultTheme())`) is now
    /// applied inside `makeGameApp` via `config.theme` — not duplicated here.
    public var rootView: some View {
        wiredView
        // #278 Tier-1 Phase 2a: cell tokens are Sudoku-shaped and were pulled
        // out of the generic `Theme` protocol into SudokuUI's `\.sudokuCell`
        // env key. `makeGameApp` injects `config.theme` but not `\.sudokuCell`
        // (game-specific). Inject here so board cells render byte-identically.
        .environment(\.sudokuCell, DefaultTheme().cell)
        // #510: DEBUG-only near-win hook. When launched with `-uitest-near-win`,
        // present a board that is one digit entry from winning immediately over
        // the normal root — bypasses persistence, GameCenter, and monetization
        // entirely. Compiled out of Release builds by the `#if DEBUG` guard.
        #if DEBUG
        .modifier(SudokuNearWinModifier())
        #endif
    }

    public init(
        rootViewModel: RootViewModel,
        routeFactory: any RouteFactory<AppRoute>,
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
        toastController: ToastController,
        attPrimer: ATTPrimerCoordinator? = nil,
        wiredView: AnyView = AnyView(EmptyView())
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
        self.attPrimer = attPrimer
        self.wiredView = wiredView
    }

    // MARK: - v2.3.7 boot order

    /// App-launch monetization boot. Runs UMP consent → (ATT no-op) → AdMob
    /// SDK initialize in that order. Each step is attempted independently;
    /// a failing earlier step never blocks later steps (banner gate will
    /// surface `.failed` honestly while AdMob is still un-initialized).
    ///
    /// #371 / #195: the ATT step is intentionally a NO-OP at boot. The
    /// coordinator keeps the 3-slot UMP/ATT/AdMob shape (ordering tests rely on
    /// it) but `MonetizationBootBridges.live` wires the ATT closure to nothing —
    /// the real ATT prompt is driven later by `ATTPrimerCoordinator` (after Home
    /// + first ad-context). UMP (GDPR consent) legitimately stays at cold launch.
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

    // MARK: - Resume helpers (#455)

    /// `%d:%02d` elapsed label for the resume pill subtitle. Moved out of the
    /// former `SavedGameSummary`-typed `ResumePill` (now game-agnostic) into a
    /// single shared home so `.live()` and `.preview()` map `SavedGameSummary`
    /// into the game-agnostic `ResumeCandidate` with byte-identical strings.
    static func elapsed(_ totalSeconds: Int) -> String {
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
