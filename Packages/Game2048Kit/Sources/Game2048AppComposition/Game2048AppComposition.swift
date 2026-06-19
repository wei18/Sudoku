// Game2048AppComposition — DI composition root for the Tiles2048 app.
//
// #479 SDD-005 Pillar C: migrated to GameConfig/makeGameApp (mirrors
// MinesweeperAppComposition post-#572). The public field shape is preserved
// so existing tests and the App target compile unchanged.
//
// The App target reads `bag.rootView` and hands it to `WindowGroup`. After
// #479 `rootView` returns `wiredView` (from `makeGameApp`) — the shared
// GameRoot + GameHomeView + universal ResumePill + ATT sheet + GC alert,
// assembled by makeGameApp. The theme injection (`\.theme, Game2048Theme()`)
// is now applied inside `makeGameApp` via `config.theme`.
//
// Deleted by this PR: Live+Resume.swift, Game2048Root.swift,
// Game2048HomeView.swift, Game2048HomeViewModel.swift.
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
public import GameAppKit

/// ASC product ID for Tiles2048's "Remove Ads" non-consumable.
/// Mirrors `minesweeperRemoveAdsProductId` — distinct so the two apps'
/// ASC catalogs never collide. Held as `public let` so future tests can
/// import the same symbol (same precedent as SudokuKit / MinesweeperKit).
public let tiles2048RemoveAdsProductId: String = "com.wei18.tiles2048.iap.remove_ads"

@MainActor
public struct Game2048AppComposition {
    // #479: rootViewModel comes from makeGameAppWithDeps. Type is
    // GameRootViewModel<AppRoute> — identical to Game2048RootViewModel
    // (which is a typealias over it). Kept as the typealias type for
    // backward compatibility with tests that use Game2048RootViewModel.
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
    // #479: the fully-wired root view from makeGameApp — GameRoot + shared
    // GameHomeView + ResumePill + ATT sheet + GC alert. Mounted by `rootView`.
    private let wiredView: AnyView

    // MARK: - Root view accessor (#479)

    /// Composed root view ready to mount in `@main`'s `WindowGroup`.
    ///
    /// After #479: `wiredView` (from `makeGameApp`) is the live mount point.
    /// It carries the shared `GameHomeView` + universal ResumePill + ATT sheet
    /// + GC-signed-out alert + monetization boot. The theme injection
    /// (`.environment(\.theme, Game2048Theme())`) is applied inside
    /// `makeGameApp` via `config.theme` — not duplicated here.
    public var rootView: some View {
        wiredView
    }

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
        toastController: ToastController,
        wiredView: AnyView = AnyView(EmptyView())
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
        self.wiredView = wiredView
    }
}
