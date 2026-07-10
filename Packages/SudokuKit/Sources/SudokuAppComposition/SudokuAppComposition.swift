// SudokuAppComposition — DI composition root (docs/v1/design.md §How.1).
//
// Three factory methods produce a fully-wired `SudokuAppComposition` for the
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
// #510: name GameAppKit directly at the target boundary — the public
// `rootViewModel: RootViewModel` property aliases `GameAppKit.GameRootViewModel`
// (so it must be public), and the DEBUG-only `UITestRouteModifier` lives here too.
public import GameAppKit

@MainActor
public struct SudokuAppComposition {
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
        // DEBUG-only modal near-win hook. When launched with
        // `-uitest-near-win-modal`, present a near-win board through the
        // PRODUCTION modal path (path == nil fullScreenCover) so the #610
        // in-board Completion overlay fires on the winning tap. Distinct from
        // `SudokuNearWinModifier` which uses a push NavigationStack (path != nil).
        .modifier(SudokuNearWinModalModifier())
        // #510: DEBUG-only deep-link hook. `-uitest-route <daily|practice|settings>`
        // pushes that screen onto the live root path in one launch (board +
        // completion stay on the near-win hooks above).
        .modifier(UITestRouteModifier(rootViewModel: rootViewModel, resolve: Self.uitestRoute(for:)))
        #endif
    }

    #if DEBUG
    /// #510: map a `-uitest-route` screen key to Sudoku's push routes. Returns
    /// nil for `"home"` / unknown keys (stay at the root).
    static func uitestRoute(for key: String) -> AppRoute? {
        switch key {
        case "daily": return .daily
        case "practice": return .practice
        case "settings": return .settings
        default: return nil
        }
    }
    #endif

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
}
