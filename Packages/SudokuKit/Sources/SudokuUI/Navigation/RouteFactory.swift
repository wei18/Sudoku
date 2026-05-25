// RouteFactory — single seam mapping an `AppRoute` value onto a concrete
// destination view (plan.md v2.3.3, promoted from Wave 3 architecture audit).
//
// Why a seam: every time the App gained a new top-level dependency (Telemetry,
// PuzzleProvider, then v2's AdProvider / IAPClient / AdGate) the `RootView`
// constructor grew another parameter — by v2.3.2's interim wiring it would
// have reached 8 deps. The factory absorbs all of those into a single object,
// so `RootView.init` stays at two arguments (viewModel + routeFactory)
// regardless of how many collaborators the destination views ultimately need.
//
// §設計決定: `view(for:) -> AnyView`
//   AnyView pays a small SwiftUI diff cost (identity-via-AnyView erasure) but
//   keeps the protocol non-generic so we can store it as `any RouteFactory`
//   in `AppComposition` and `RootView`. The alternative — an associated-type
//   `Destination: View` — would force `RootView` and `AppComposition` to be
//   generic over the factory and propagate that generic through every test
//   fixture. SwiftUI itself uses AnyView in its public navigationDestination
//   API closures, so we are not breaking new ground.

public import SwiftUI
public import MonetizationCore
public import GameCenterClient
public import Persistence
public import PuzzleStore
public import Telemetry

// MARK: - RouteFactory

public protocol RouteFactory: Sendable {
    @MainActor
    func view(for route: AppRoute) -> AnyView
}

// MARK: - LiveRouteFactory

/// Production `RouteFactory`. Holds all protocol deps the destination Views
/// need; `view(for:)` switches over `AppRoute` and returns the matching
/// pre-configured `View + ViewModel` pair wrapped in `AnyView`.
public struct LiveRouteFactory: RouteFactory {
    private let puzzleProvider: any PuzzleProviderProtocol
    private let persistence: any PersistenceProtocol
    private let gameCenter: any GameCenterClient
    private let telemetry: Telemetry
    // M10 (issue #67): unified error funnel passed into VMs / loader views
    // that previously `try?`-swallowed CloudKit / Persistence errors.
    private let errorReporter: any ErrorReporter
    // v2 monetization deps. Currently consumed by destination views landing
    // in v2.3.4-6 (HomeView banner, BoardView banner, Settings IAP rows).
    // Stored here now so RootView's signature does not have to grow.
    private let adProvider: any AdProvider
    private let iapClient: any IAPClient
    private let adGate: AdGate
    // v2.3.6: optional so existing callers (route factory tests, snapshot
    // fixtures) keep working without constructing a controller. Live wiring
    // injects one so Settings renders the Remove Ads section.
    private let monetizationController: MonetizationStateController?
    // v2.4.6: optional toast surface forwarded to `SettingsViewModel` so the
    // clear-cache success can route through the same overlay as IAP results.
    private let toastController: ToastController?

    public init(
        puzzleProvider: any PuzzleProviderProtocol,
        persistence: any PersistenceProtocol,
        gameCenter: any GameCenterClient,
        telemetry: Telemetry,
        errorReporter: any ErrorReporter = NoopErrorReporter(),
        adProvider: any AdProvider,
        iapClient: any IAPClient,
        adGate: AdGate,
        monetizationController: MonetizationStateController? = nil,
        toastController: ToastController? = nil
    ) {
        self.puzzleProvider = puzzleProvider
        self.persistence = persistence
        self.gameCenter = gameCenter
        self.telemetry = telemetry
        self.errorReporter = errorReporter
        self.adProvider = adProvider
        self.iapClient = iapClient
        self.adGate = adGate
        self.monetizationController = monetizationController
        self.toastController = toastController
    }

    @MainActor
    public func view(for route: AppRoute) -> AnyView {
        switch route {
        case .home:
            // `.home` is never pushed (root content renders HomeView). Keep
            // the switch exhaustive without forcing destination views to model
            // the un-pushable case.
            return AnyView(EmptyView())
        case .daily:
            return AnyView(
                DailyHubView(
                    viewModel: DailyHubViewModel(
                        provider: puzzleProvider,
                        persistence: persistence,
                        errorReporter: errorReporter
                    )
                )
            )
        case .practice:
            return AnyView(
                PracticeHubView(
                    viewModel: PracticeHubViewModel(provider: puzzleProvider)
                )
            )
        case .board(let puzzleId):
            return AnyView(
                BoardLoaderView(
                    puzzleId: puzzleId,
                    puzzleProvider: puzzleProvider,
                    persistence: persistence,
                    errorReporter: errorReporter,
                    adProvider: adProvider,
                    adGate: adGate
                )
            )
        case .completion(let puzzleId, let elapsedSeconds):
            return AnyView(
                CompletionView(
                    viewModel: CompletionViewModel(
                        puzzleId: puzzleId,
                        elapsedSeconds: elapsedSeconds,
                        leaderboardId: LeaderboardIDs.id(for: .dailyEasy),
                        gameCenter: gameCenter
                    )
                )
            )
        case .settings:
            return AnyView(
                SettingsView(
                    viewModel: SettingsViewModel(
                        persistence: persistence,
                        errorReporter: errorReporter,
                        toastController: toastController
                    ),
                    monetizationController: monetizationController
                )
            )
        }
    }
}
