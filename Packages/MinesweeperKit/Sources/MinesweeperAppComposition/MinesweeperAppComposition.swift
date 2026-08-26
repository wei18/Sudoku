// MinesweeperAppComposition — DI composition root for the Minesweeper app.
//
// #572 SDD-005 Pillar C: migrated to GameConfig/makeGameApp (mirrors Sudoku's
// SudokuAppComposition post-#557). The public field shape is preserved so existing
// tests and the App target compile unchanged.
//
// The App target reads `bag.rootView` and hands it to `WindowGroup`. After #572
// `rootView` returns `wiredView` (from `makeGameApp`) — the shared GameRoot +
// the #1020 `sidebarAdaptable` 3-tab shell (Today/Practice/Progress) +
// universal ResumePill (#554) + ATT sheet + GC alert, assembled by
// makeGameApp. Two MS-specific layers are still applied here (not in
// makeGameApp, which is game-agnostic):
//   - `\.minesweeperCell` environment (#278 Tier-1 Phase 2b)
//   - `MinesweeperNearWinModifier` (#510 DEBUG near-win test hook)
// The theme injection (`\.theme, MinesweeperTheme()`) is now applied inside
// `makeGameApp` via `config.theme` — not duplicated here.

public import SwiftUI
public import GameCenterClient
public import GameShellUI
public import MinesweeperUI
#if DEBUG
// Internal-only: `Difficulty` is named directly by `uitestRoute(for:)` below
// (an internal, DEBUG-only func), so this doesn't need public exposure.
internal import MinesweeperEngine
#endif
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
    // #572/#1020: the fully-wired root view from makeGameApp — GameRoot +
    // the 3-tab shell + ResumePill (#554) + ATT sheet + GC alert. Mounted by
    // `rootView`.
    private let wiredView: AnyView

    // MARK: - Root view accessor (#572)

    /// Composed root view ready to mount in `@main`'s `WindowGroup`.
    ///
    /// After #572: `wiredView` (from `makeGameApp`) is the live mount point.
    /// It carries the #1020 3-tab `sidebarAdaptable` shell (Today/Practice/
    /// Progress) + universal ResumePill + ATT sheet + GC-signed-out alert +
    /// monetization boot. Two MS-specific layers are still applied here (not
    /// in makeGameApp, which is game-agnostic):
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
    /// Fixed seed for the `board:<difficulty>` deep-link key below — pins the
    /// generated board so macOS zero-click measurement runs (#1026 B-1) and
    /// any E2E assertions against it stay reproducible across launches.
    static let uitestBoardSeed: UInt64 = 0x5EED_B1

    /// #510: map a `-uitest-route` screen key to Minesweeper's launch target.
    /// #1020: `daily` / `practice` used to be push routes; they are tab
    /// identities now, so both just select their tab — `settings` still
    /// pushes onto the Today tab's stack. Unknown keys stay at the root. Keys:
    /// `daily` / `practice` / `settings` / `resumeFail` /
    /// `board:<beginner|intermediate|expert>` (#1026 B-1: zero-click straight
    /// into a practice board at that difficulty, fixed seed above, pushed on
    /// the Practice tab so the runner sees it where a Start tap would land it).
    static func uitestRoute(for key: String) -> UITestLaunchTarget<AppRoute>? {
        switch key {
        case "daily": return .tab(.today)
        case "practice": return .tab(.practice)
        case "settings": return .push(.settings)
        // #719: `.resumeBoard` is the ONLY route that mounts
        // `MinesweeperBoardLoaderView` — unlike Sudoku, a fresh MS board never
        // goes through the loader. Without this key there is no way to reach
        // the loader (and its `-uitest-loader-fail` hook) in a sim that has no
        // real in-progress CloudKit save to resume. The `recordName` is never
        // read when `-uitest-loader-fail` is also passed — the hook short-
        // circuits `load()` before `store.loadInProgress` is called.
        case "resumeFail": return .push(.resumeBoard(recordName: "uitest-loader-fail", mode: .practice))
        default:
            // #1026 B-1: `board:<difficulty>` — macOS has no synthetic tap
            // path to the practice hub's Start button, so this is the only
            // zero-click route to a sized board on that platform.
            guard key.hasPrefix("board:") else { return nil }
            let difficultyKey = key.dropFirst("board:".count)
            guard let difficulty = Difficulty(rawValue: String(difficultyKey)) else { return nil }
            return .push(.board(difficulty: difficulty, seed: uitestBoardSeed, mode: .practice), tab: .practice)
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
