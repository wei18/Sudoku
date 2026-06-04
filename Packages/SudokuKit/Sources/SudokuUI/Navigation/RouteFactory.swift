// LiveRouteFactory — Sudoku's concrete `RouteFactory` (PR X2 split, 2026-06-01):
// the game-agnostic protocol moved to `GameShellKit/Sources/GameShellUI/RouteFactory.swift`.
// This file holds the Sudoku-specific implementation and its destination
// wiring; the protocol's `associatedtype Route` is bound to `AppRoute` here.
//
// Why the protocol seam exists: every time the App gained a new top-level
// dependency (Telemetry, PuzzleProvider, then v2's AdProvider / IAPClient /
// AdGate) the `RootView` constructor grew another parameter — by v2.3.2's
// interim wiring it would have reached 8 deps. The factory absorbs all of
// those into a single object, so `RootView.init` stays at two arguments
// (viewModel + routeFactory) regardless of how many collaborators the
// destination views ultimately need.

public import SwiftUI
public import MonetizationCore
public import MonetizationUI
public import GameCenterClient
public import Persistence
public import PuzzleStore
public import Telemetry
public import GameShellUI

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
    // #287 Phase 2: builds a fresh daily-ready primer coordinator for a Daily
    // completion mount. Injected as a closure (not the raw Reminders seams) so
    // ALL reminder wiring — Live conformers, copy, telemetry bridge — stays in
    // AppComposition; the factory only decides WHEN (Daily, not Practice). `nil`
    // in previews / tests → no primer, byte-identical Completion screens.
    private let makeDailyReminderPrimer: (@MainActor () -> ReminderPrimerCoordinator)?

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
        toastController: ToastController? = nil,
        makeDailyReminderPrimer: (@MainActor () -> ReminderPrimerCoordinator)? = nil
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
        self.makeDailyReminderPrimer = makeDailyReminderPrimer
    }

    /// A puzzleId is a Daily unless it carries the practice prefix — same
    /// encoding `BoardLoaderView.identity(from:)` relies on. The reminder primer
    /// is offered only after a Daily solve (proposal §5.1; flow S02).
    private static func isDaily(puzzleId: String) -> Bool {
        !puzzleId.hasPrefix("practice-")
    }

    @MainActor
    public func view(for route: AppRoute, path: Binding<[AppRoute]>?) -> AnyView {
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
                        errorReporter: errorReporter,
                        path: path
                    )
                )
            )
        case .practice:
            return AnyView(
                PracticeHubView(
                    viewModel: PracticeHubViewModel(provider: puzzleProvider, path: path)
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
            // #287 Phase 2: offer the daily-ready primer ONLY on a Daily solve
            // (flow S02). Practice solves pass `reminderPrimer: nil` → no change.
            let reminderPrimer = Self.isDaily(puzzleId: puzzleId)
                ? makeDailyReminderPrimer?()
                : nil
            return AnyView(
                CompletionView(
                    viewModel: CompletionViewModel(
                        puzzleId: puzzleId,
                        elapsedSeconds: elapsedSeconds,
                        leaderboardId: LeaderboardIDs.id(for: .dailyEasy),
                        gameCenter: gameCenter
                    ),
                    reminderPrimer: reminderPrimer
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
