// Game2048AppComposition — DI composition root for the Tiles2048 app.
//
// M4 fully wires all Live seams, mirroring MinesweeperAppComposition:
//   - `persistence`: LivePersistence(ckConfig: .tiles2048, ...)
//   - `iapClient`: LiveStoreKit2IAPClient(knownProductIds: [...remove_ads])
//   - `adProvider`: LiveAdMobAdProvider (iOS) / NoopAdProvider (macOS)
//   - `adGate` + `monetizationStateStore` + `monetizationController`
//   - `toastController`: shared toast surface (mirrors MS §U15)
//   - `gameCenter`: LiveGameCenterClient(authDriver: GKAuthDriver())
//   - `routeFactory`: LiveRouteFactory wired into Game2048Root
//   - `rootViewModel`: Game2048RootViewModel (GameRootViewModel<AppRoute> alias)
//
// Note: no audio in M4 (Tiles2048 v1.0 defers audio to a later milestone,
// unlike Minesweeper which wired #330 P2). No reminders in M4 (no
// daily-ready fire-time concept yet for a daily-tile game).
//
// Public surface:
//   - `Game2048AppComposition.live()`    — production bag (Live.swift).
//   - `Game2048AppComposition.preview()` — Preview / test fakes (Live.swift).
//
// The App target reads `bag.rootView` and hands it to `WindowGroup`.

public import SwiftUI
public import GameCenterClient
public import GameShellUI
public import Game2048UI
public import Telemetry
public import Persistence
public import MonetizationCore
public import MonetizationUI

/// ASC product ID for Tiles2048's "Remove Ads" non-consumable.
/// Mirrors `minesweeperRemoveAdsProductId` — distinct so the two apps'
/// ASC catalogs never collide. Held as `public let` so future tests can
/// import the same symbol (same precedent as SudokuKit / MinesweeperKit).
public let tiles2048RemoveAdsProductId: String = "com.wei18.tiles2048.iap.remove_ads"

@MainActor
public struct Game2048AppComposition {
    public let rootViewModel: Game2048RootViewModel
    public let routeFactory: any RouteFactory<AppRoute>
    public let telemetry: Telemetry
    public let errorReporter: any ErrorReporter
    public let gameCenter: any GameCenterClient
    public let persistence: any PersistenceProtocol
    public let adProvider: any AdProvider
    public let iapClient: any IAPClient
    public let adGate: AdGate
    public let monetizationStateStore: any AdGateStateStore
    public let monetizationController: MonetizationStateController
    public let toastController: ToastController

    public init(
        rootViewModel: Game2048RootViewModel,
        routeFactory: any RouteFactory<AppRoute>,
        telemetry: Telemetry,
        errorReporter: any ErrorReporter,
        gameCenter: any GameCenterClient,
        persistence: any PersistenceProtocol,
        adProvider: any AdProvider,
        iapClient: any IAPClient,
        adGate: AdGate,
        monetizationStateStore: any AdGateStateStore,
        monetizationController: MonetizationStateController,
        toastController: ToastController
    ) {
        self.rootViewModel = rootViewModel
        self.routeFactory = routeFactory
        self.telemetry = telemetry
        self.errorReporter = errorReporter
        self.gameCenter = gameCenter
        self.persistence = persistence
        self.adProvider = adProvider
        self.iapClient = iapClient
        self.adGate = adGate
        self.monetizationStateStore = monetizationStateStore
        self.monetizationController = monetizationController
        self.toastController = toastController
    }

    /// Convenience accessor — constructs the top-level `Game2048Root` view
    /// bound to this composition's `routeFactory`. The App target just calls
    /// `composition.rootView` inside its `WindowGroup`.
    public var rootView: some View {
        Game2048Root(
            viewModel: rootViewModel,
            routeFactory: routeFactory,
            toastController: toastController,
            // Home is the root content and mounts the banner slot + Remove
            // Ads card directly (not a RouteFactory destination), so Root
            // threads these in — mirrors MinesweeperAppComposition.rootView.
            adProvider: adProvider,
            adGate: adGate,
            monetizationController: monetizationController
        )
        // Inject Tiles2048's warm-tile palette at the composition root.
        // GameShellUI's `\.theme` default is a palette-neutral fallback (NOT
        // any app's brand), so every mounted view resolves amber/sand tokens
        // here. Mirrors Minesweeper's `.environment(\.theme, MinesweeperTheme())`.
        .environment(\.theme, Game2048Theme())
    }
}
