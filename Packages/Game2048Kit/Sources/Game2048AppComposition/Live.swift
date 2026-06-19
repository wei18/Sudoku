// Live + Preview composition for Game2048AppComposition.
//
// #479 SDD-005 Pillar C (2048): the game-agnostic live wiring (Telemetry +
// MetricKit + errorReporter + GameCenter + Persistence + monetization + audio +
// ATT + reminders) now lives in `GameAppKit.makeGameApp`. `live()` builds a
// `GameConfig<AppRoute>` carrying ONLY the 2048-specific values + builder
// closures and calls `makeGameAppWithDeps`, which returns the wired `GameDeps`
// bag + root VM + route factory. `Game2048AppComposition` is assembled from
// that bag so its public field shape (consumed by tests + the App target)
// is unchanged.
//
// Behaviour-preserving: every Tiles2048 string + default flows through the
// config, so the wired stack is byte-identical to the former hand-rolled wiring.
// Capability gaps now filled universally by makeGameApp: ResumePill mount,
// ATT primer, GC signed-out alert, audio + reminders sections in Settings.
//
// Deleted by this PR: Live+Resume.swift, Game2048Root.swift,
// Game2048HomeView.swift, Game2048HomeViewModel.swift (their logic is now
// in GameConfig/makeGameApp or expressed as config values below).

internal import AdsAdMob
internal import Foundation
internal import GameAppKit
internal import GameCenterClient
internal import GameCenterTesting
internal import GameShellUI
internal import IAPStoreKit2
internal import MonetizationCore
internal import MonetizationUI
internal import MonetizationTesting
internal import Persistence
internal import PersistenceTesting
internal import Telemetry
internal import Game2048Persistence
internal import Reminders
internal import SettingsUI
internal import Game2048UI
internal import SwiftUI

#if canImport(UIKit)
internal import UIKit
#endif

extension Game2048AppComposition {

    public static func live() -> Game2048AppComposition {
        // Tiles2048-specific identifiers live here (NOT inside AppMonetizationKit)
        // so the package can be linked by Sudoku without baking 2048 IDs into its
        // binary. Mirrors MinesweeperAppComposition.live() and SudokuKit.AppComposition.live().

        // #455 step 4: saved-game store over the public gateway factory
        // (same container/zone LivePersistence.bootstrap() provisions).
        // Constructed here (not inside makeGameApp) because the 2048 route factory
        // also needs a reference to it for board persistence + .resumeBoard.
        let savedGameStore = Game2048SavedGameStore(
            gateway: PrivateCKGatewayFactory.live(config: .tiles2048),
            telemetry: nil  // telemetry threaded lazily; store funnels errors
        )

        // Shared daily-ready notification payload — used both by the primer
        // (initial schedule) and the Settings time picker (reschedule on change).
        let dailyReadyContent = ReminderContent(
            title: "Today's 2048 Tiles is ready",
            body: "Your daily board is waiting — come back and play."
        )
        let primerCopy = ReminderPrimerCopy(
            title: "Never miss a Daily",
            lede: "We'll let you know the moment tomorrow's Daily 2048 is ready.",
            bullets: [
                "One gentle nudge a day, default 9 AM",
                "Adjustable anytime in Settings",
                "Turn it off whenever you like"
            ],
            acceptCTA: "Remind me",
            declineCTA: "Not now",
            fineprint: "\"Not now\" keeps this for later — it does not ask iOS yet."
        )
        let deniedCopy = ReminderDeniedCopy(
            title: "Reminders are off",
            message: "Notifications are turned off for 2048 Tiles in Settings, so we can't tell you when the Daily is ready.",
            openSettingsCTA: "Open Settings",
            dismissCTA: "Not now",
            macOSGuidance: "Enable notifications in System Settings → Notifications → 2048 Tiles."
        )
        let settingsCopy = ReminderSettingsCopy(
            sectionTitle: "Reminders",
            enableTitle: "Daily reminder",
            enableCTA: "Turn On",
            enabledTitle: "Daily reminder",
            enabledStatus: "On",
            disableTitle: "Turn off reminders",
            timeTitle: "Time",
            deniedTitle: "Notifications are off",
            deniedCTA: "Fix"
        )

        let config = GameConfig<AppRoute>(
            subsystem: "com.wei18.tiles2048",
            ckConfig: .tiles2048,
            removeAdsProductId: tiles2048RemoveAdsProductId,
            // Tiles2048 has no PuzzleProvider; its resume path goes through
            // Game2048Persistence, never through SavedGameStore.loadOrCreate.
            puzzleLoader: { _ in
                throw Game2048LivePuzzleLoaderUnavailable()
            },
            theme: Game2048Theme(),
            title: "2048 Tiles",
            // sidebarItems derived by makeGameApp from homeModes.modeItems.
            sidebarItems: [],
            successTint: Game2048Theme().status.success.resolved,
            failureTint: Game2048Theme().status.error.resolved,
            audio: AudioConfig(keyPrefix: "com.wei18.tiles2048.audio"),
            reminders: ReminderContentConfig(
                dailyReadyContent: dailyReadyContent,
                primerCopy: primerCopy,
                deniedCopy: deniedCopy,
                settingsCopy: settingsCopy
            ),
            settingsNotices: LiveRouteFactory.makeSettingsNotices(),
            // #479 SDD-005 Pillar C: per-mode subtitle copy + route mapping.
            // Byte-identical to the former Game2048HomeViewModel.subtitleKey
            // literals so snapshot baselines do not move.
            homeModes: [
                .daily: HomeModeContent(subtitleKey: "Today's seeded board", route: .daily),
                .practice: HomeModeContent(subtitleKey: "Unlimited classic play", route: .practice),
                .leaderboard: HomeModeContent(subtitleKey: "Top daily scores"),
                .settings: HomeModeContent(subtitleKey: "Purchases / about", route: .settings)
            ],
            // 2048 Game Center dashboard presenter. Injected here (not inside
            // GameAppKit) so GameAppKit stays free of the GK dependency.
            presentLeaderboard: { GameCenterDashboard.present() },
            // #455 / #479: map Game2048SavedGameSummary into the game-agnostic
            // ResumeCandidate. Strings match the former ResumePill rendering exactly
            // so snapshot baselines do not move.
            fetchResume: { _ in
                { [savedGameStore] in
                    guard let summary = try await savedGameStore.latestInProgress() else { return nil }
                    let mode = GameMode(rawValue: summary.modeRaw) ?? .practice
                    return ResumeCandidate(
                        title: "Resume \(mode == .daily ? "Daily" : "Classic")",
                        subtitle: Game2048AppComposition.elapsed(summary.elapsedSeconds),
                        route: .resumeBoard(recordName: summary.recordName, mode: mode)
                    )
                }
            },
            makeRouteFactory: { deps, rootViewModel in
                Game2048AppComposition.makeRouteFactory(
                    deps: deps,
                    rootViewModel: rootViewModel,
                    savedGameStore: savedGameStore
                )
            },
            // makeHome superseded by the universal GameHomeView built from
            // homeModes in makeGameApp (#479). Kept for API stability; ignored
            // by makeGameApp when homeModes is non-empty.
            makeHome: { _, _ in AnyView(EmptyView()) }
        )

        // Wire the shared live stack once. The returned wired.view is the
        // live mount point after #479: GameRoot + shared GameHomeView + universal
        // ResumePill + ATT sheet + GC-signed-out alert, assembled by makeGameApp.
        let wired = makeGameAppWithDeps(config: config)
        let deps = wired.deps

        return Game2048AppComposition(
            rootViewModel: wired.rootViewModel,
            routeFactory: wired.routeFactory,
            telemetry: deps.telemetry,
            errorReporter: deps.errorReporter,
            gameCenter: deps.gameCenter,
            persistence: deps.persistence,
            adProvider: deps.adProvider,
            iapClient: deps.iapClient,
            adGate: deps.adGate,
            monetizationStateStore: deps.monetizationStateStore,
            monetizationController: deps.monetizationController,
            toastController: deps.toastController,
            wiredView: wired.view
        )
    }

    /// Builds Tiles2048's `LiveRouteFactory` from the wired `GameDeps`. Shared
    /// by the `GameConfig.makeRouteFactory` closure.
    @MainActor
    private static func makeRouteFactory(
        deps: GameDeps,
        rootViewModel: GameRootViewModel<AppRoute>,
        savedGameStore: Game2048SavedGameStore
    ) -> any RouteFactory<AppRoute> {
        LiveRouteFactory(
            monetizationController: deps.monetizationController,
            adProvider: deps.adProvider,
            adGate: deps.adGate,
            persistence: deps.persistence,
            gameCenter: deps.gameCenter,
            errorReporter: deps.errorReporter,
            toastController: deps.toastController,
            makeReminderSettings: deps.makeReminderSettings,
            soundPlayer: deps.soundPlayer,
            audioSettings: deps.audioSettings,
            savedGameStore: savedGameStore,
            onPresentBoard: {
                #if os(iOS)
                { [rootViewModel] route in rootViewModel.presentGame(route: route) }
                #else
                nil
                #endif
            }()
        )
    }

    // MARK: - Resume helpers (#455)

    /// `%d:%02d` elapsed label for the resume pill subtitle. Mirrors
    /// MinesweeperAppComposition.elapsed (the exact string the pre-#460 shared
    /// ResumePill rendered).
    static func elapsed(_ totalSeconds: Int) -> String {
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    // MARK: - Preview / test wiring

    /// Preview / test wiring: empty-sinks `Telemetry`, fake IAP / AdGate
    /// store / AdProvider, `FakePersistence` (zero-IO) — no Preview path can
    /// trap on a real CloudKit gateway (mirrors MS Preview).
    public static func preview() -> Game2048AppComposition {
        let telemetry = Telemetry(sinks: [])
        let errorReporter: any ErrorReporter = NoopErrorReporter()

        let gameCenter: any GameCenterClient = FakeGameCenterClient()

        let persistence = FakePersistence()

        let adProvider: any AdProvider = FakeAdProvider()
        let iapClient: any IAPClient = FakeIAPClient()
        let monetizationStateStore: any AdGateStateStore = FakeAdGateStateStore(
            initial: AdGateState(firstLaunchAt: Date(timeIntervalSince1970: 0))
        )
        let adGate = AdGate(store: monetizationStateStore)

        let toastController = ToastController()

        let monetizationController = MonetizationStateController(
            iapClient: iapClient,
            stateStore: monetizationStateStore,
            adGate: adGate,
            toastController: toastController,
            productId: tiles2048RemoveAdsProductId
        )

        let routeFactory = LiveRouteFactory(
            monetizationController: monetizationController,
            adProvider: adProvider,
            adGate: adGate,
            persistence: persistence,
            gameCenter: gameCenter,
            errorReporter: errorReporter,
            toastController: toastController
        )

        let rootViewModel = Game2048RootViewModel(
            gameCenter: gameCenter,
            persistence: persistence,
            errorReporter: errorReporter
        )

        return Game2048AppComposition(
            rootViewModel: rootViewModel,
            routeFactory: routeFactory,
            telemetry: telemetry,
            errorReporter: errorReporter,
            gameCenter: gameCenter,
            persistence: persistence,
            adProvider: adProvider,
            iapClient: iapClient,
            adGate: adGate,
            monetizationStateStore: monetizationStateStore,
            monetizationController: monetizationController,
            toastController: toastController
        )
    }

}

/// Sentinel thrown by the `.live()` puzzle loader stub — Tiles2048 has no
/// PuzzleProvider; its resume path goes through `Game2048Persistence`, never
/// through Sudoku-shaped `SavedGameStore.loadOrCreate`.
private struct Game2048LivePuzzleLoaderUnavailable: Error {}
