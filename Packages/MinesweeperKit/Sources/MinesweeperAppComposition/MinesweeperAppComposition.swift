// MinesweeperAppComposition — DI composition root for the Minesweeper app.
//
// #572 SDD-005 Pillar C: migrated to GameConfig/makeGameApp (mirrors Sudoku's
// AppComposition post-#557). The public field shape is preserved so existing
// tests and the App target compile unchanged.
//
// The App target reads `bag.rootView` and hands it to `WindowGroup`. After #572
// `rootView` returns `wiredView` (from `makeGameApp`) — the shared GameRoot +
// GameHomeView + universal ResumePill (#554) + ATT sheet + GC alert, assembled
// by makeGameApp. Two MS-specific layers are still applied here (not in
// makeGameApp, which is game-agnostic):
//   - `\.minesweeperCell` environment (#278 Tier-1 Phase 2b)
//   - `MinesweeperNearWinModifier` (#510 DEBUG near-win test hook)
// The theme injection (`\.theme, MinesweeperTheme()`) is now applied inside
// `makeGameApp` via `config.theme` — not duplicated here.

public import SwiftUI
public import GameCenterClient
public import GameShellUI
public import MinesweeperUI
public import Telemetry
public import Persistence
public import MonetizationCore
public import MonetizationUI
public import GameAppKit

/// ASC product ID for Minesweeper's "Remove Ads" non-consumable. Mirrors
/// `removeAdsProductId` (Sudoku) — distinct here so the two apps' ASC
/// catalogs never collide. Held as a `public let` so future MS tests can
/// import the same symbol the way Sudoku tests import `removeAdsProductId`.
public let minesweeperRemoveAdsProductId: String = "com.wei18.minesweeper.iap.remove_ads"

@MainActor
public struct MinesweeperAppComposition {
    // #572: rootViewModel comes from makeGameAppWithDeps. Type is
    // GameRootViewModel<AppRoute> — identical to MinesweeperRootViewModel
    // (which is a typealias over it). Kept as the typealias type for
    // backward compatibility with tests that use MinesweeperRootViewModel.
    public let rootViewModel: MinesweeperRootViewModel
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
    // #572: the fully-wired root view from makeGameApp — GameRoot + shared
    // GameHomeView + ResumePill (#554) + ATT sheet + GC alert. Mounted by `rootView`.
    private let wiredView: AnyView

    // MARK: - Root view accessor (#572)

    /// Composed root view ready to mount in `@main`'s `WindowGroup`.
    ///
    /// After #572: `wiredView` (from `makeGameApp`) is the live mount point.
    /// It carries the shared `GameHomeView` + universal ResumePill + ATT sheet
    /// + GC-signed-out alert + monetization boot. Two MS-specific layers are
    /// still applied here (not in makeGameApp, which is game-agnostic):
    ///   - `\.minesweeperCell` environment (#278 Tier-1 Phase 2b — board cell tokens)
    ///   - `MinesweeperNearWinModifier` (#510 DEBUG near-win test hook)
    /// The theme injection (`.environment(\.theme, MinesweeperTheme())`) is now
    /// applied inside `makeGameApp` via `config.theme` — not duplicated here.
    public var rootView: some View {
        wiredView
        // #278 Tier-1 Phase 2b: cell tokens are MS-shaped and were pulled
        // out of the generic `Theme` protocol into MinesweeperUI's `\.minesweeperCell`
        // env key. `makeGameApp` injects `config.theme` but not `\.minesweeperCell`
        // (game-specific). Inject here so board cells render byte-identically.
        .environment(\.minesweeperCell, MinesweeperTheme().cell)
        // #510: DEBUG-only near-win hook. Mirrors Sudoku's SudokuNearWinModifier.
        // Compiled out of Release builds by the `#if DEBUG` guard.
        #if DEBUG
        .modifier(MinesweeperNearWinModifier())
        // #510: DEBUG-only deep-link hook (mirrors Sudoku). `-uitest-route
        // <daily|practice|settings>` pushes that screen onto the live root path
        // in one launch (board + completion stay on the near-win hook above).
        .modifier(UITestRouteModifier(rootViewModel: rootViewModel, resolve: Self.uitestRoute(for:)))
        #endif
    }

    #if DEBUG
    /// #510: map a `-uitest-route` screen key to Minesweeper's push routes.
    /// Returns nil for `"home"` / unknown keys (stay at the root).
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
        rootViewModel: MinesweeperRootViewModel,
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
