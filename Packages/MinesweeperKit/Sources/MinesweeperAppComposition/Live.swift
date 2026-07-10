// Live composition — concrete impls for production. docs/v1/design.md §How.1.
//
// #572 SDD-005 Pillar C (MS): the game-agnostic live wiring (Telemetry +
// MetricKit + errorReporter + GameCenter + Persistence + monetization + audio +
// ATT + reminders) now lives in `GameAppKit.makeGameApp`. `live()` builds a
// `GameConfig<AppRoute>` carrying ONLY the MS-specific values + builder closures
// and calls `makeGameAppWithDeps`, which returns the wired `GameDeps` bag + root
// VM + route factory. `MinesweeperAppComposition` is assembled from that bag so
// its public field shape (consumed by tests + the App target) is unchanged.
//
// Behaviour-preserving: every Minesweeper string + default flows through the
// config, so the wired stack is byte-identical to the former hand-rolled wiring.
// Capability gaps now filled universally by makeGameApp: ResumePill mount (#554),
// ATT primer, GC signed-out alert.
//
// Deleted by this PR: Live+Resume.swift, Live+Audio.swift (their logic is now
// in GameConfig/makeGameApp or expressed as config values below).

internal import Foundation
internal import GameAppKit
internal import GameCenterClient
internal import GameShellUI
internal import MonetizationUI
internal import Persistence
internal import MinesweeperPersistence
internal import Reminders
internal import SettingsUI
internal import MinesweeperUI
internal import SwiftUI

#if canImport(UIKit)
internal import UIKit
#endif

extension MinesweeperAppComposition {

    public static func live() -> MinesweeperAppComposition {
        // MS-specific identifiers live here (NOT inside AppMonetizationKit) so
        // the package can be linked by Sudoku without baking MS IDs into its
        // binary (and vice-versa). Mirrors Sudoku's SudokuAppComposition.live().

        // #455 step 4: saved-game store over the public gateway factory
        // (same container/zone LivePersistence.bootstrap() provisions).
        // Constructed here (not inside makeGameApp) because MS route factory
        // also needs a reference to it for board persistence + .resumeBoard.
        let savedGameStore = MinesweeperSavedGameStore(
            gateway: PrivateCKGatewayFactory.live(config: .minesweeper),
            telemetry: nil  // telemetry threaded lazily; store funnels errors
        )

        // #699: MS-specific personal-best store, over the same lazy gateway
        // factory. Owner decision (2026-07-05): MS gets its own store rather
        // than generalizing the shared `PersonalRecordSink`/`TelemetryEvent`
        // pipeline to a second game's types — same precedent as
        // `savedGameStore` above.
        let personalRecordStore = MinesweeperPersonalRecordStore(
            gateway: PrivateCKGatewayFactory.live(config: .minesweeper)
        )

        // Shared daily-ready notification payload — used both by the primer
        // (initial schedule) and the Settings time picker (reschedule on change).
        let dailyReadyContent = ReminderContent(
            title: "Today's Minesweeper is ready",
            body: "Your daily boards are waiting — keep your streak going."
        )
        let primerCopy = ReminderPrimerCopy(
            title: "Never miss a Daily",
            lede: "We'll let you know the moment tomorrow's Daily Minesweeper is ready.",
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
            message: "Notifications are turned off for Minesweeper in Settings, so we can't tell you when the Daily is ready.",
            openSettingsCTA: "Open Settings",
            dismissCTA: "Not now",
            macOSGuidance: "Enable notifications in System Settings → Notifications → Minesweeper."
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
            subsystem: "com.wei18.minesweeper",
            ckConfig: .minesweeper,
            removeAdsProductId: minesweeperRemoveAdsProductId,
            // MS has no PuzzleProvider; its resume path goes through
            // MinesweeperPersistence, never through SavedGameStore.loadOrCreate.
            puzzleLoader: { _ in
                throw MinesweeperLivePuzzleLoaderUnavailable()
            },
            theme: MinesweeperTheme(),
            title: "Minesweeper",
            // sidebarItems derived by makeGameApp from homeModes.modeItems.
            sidebarItems: [],
            successTint: MinesweeperTheme().status.success.resolved,
            failureTint: MinesweeperTheme().status.error.resolved,
            audio: AudioConfig(keyPrefix: "com.wei18.minesweeper.audio"),
            reminders: ReminderContentConfig(
                dailyReadyContent: dailyReadyContent,
                primerCopy: primerCopy,
                deniedCopy: deniedCopy,
                settingsCopy: settingsCopy
            ),
            // #572 SDD-005 Pillar C: per-mode subtitle copy + route mapping.
            // Byte-identical to the former MinesweeperHomeViewModel.subtitleKey
            // literals so snapshot baselines do not move.
            homeModes: [
                .daily: HomeModeContent(subtitleKey: "3 boards today", route: .daily),
                .practice: HomeModeContent(subtitleKey: "All difficulties", route: .practice),
                .leaderboard: HomeModeContent(subtitleKey: "Best times"),
                .settings: HomeModeContent(subtitleKey: "Purchases / about", route: .settings)
            ],
            // MS Game Center dashboard presenter. Injected here (not inside
            // GameAppKit) so GameAppKit stays free of the GK dependency.
            presentLeaderboard: { GameCenterDashboard.present() },
            // #455 / #572: map MinesweeperSavedGameSummary into the game-agnostic
            // ResumeCandidate. Strings match the former ResumePill rendering exactly
            // so snapshot baselines do not move.
            fetchResume: { _ in
                { [savedGameStore] in
                    guard let summary = try await savedGameStore.latestInProgress() else { return nil }
                    return ResumeCandidate(
                        title: ResumeTitle.make(
                            difficultyKey: summary.difficulty.rawValue.capitalized
                        ),
                        subtitle: ResumeTitle.elapsed(summary.elapsedSeconds),
                        route: .resumeBoard(
                            recordName: summary.recordName,
                            mode: GameMode(rawValue: summary.modeRaw) ?? .practice
                        )
                    )
                }
            },
            makeRouteFactory: { deps, rootViewModel in
                MinesweeperAppComposition.makeRouteFactory(
                    deps: deps,
                    rootViewModel: rootViewModel,
                    savedGameStore: savedGameStore,
                    personalRecordStore: personalRecordStore
                )
            },
            // makeHome superseded by the universal GameHomeView built from
            // homeModes in makeGameApp (#572). Kept for API stability; ignored
            // by makeGameApp when homeModes is non-empty.
            makeHome: { _, _ in AnyView(EmptyView()) },
            // #696: a tapped `dailyReady` reminder deep-links to the Daily hub
            // (mirrors Sudoku's SudokuAppComposition.live() reminderTapRoute), pushing
            // `.daily` unless already on top.
            reminderTapRoute: { identifier, rootViewModel in
                guard identifier == ReminderKind.dailyReady.rawValue else { return }
                if rootViewModel.path.last != .daily {
                    rootViewModel.path.append(.daily)
                }
            }
        )

        // Wire the shared live stack once. The returned wired.view is the
        // live mount point after #572: GameRoot + shared GameHomeView + universal
        // ResumePill (#554) + ATT sheet + GC-signed-out alert, assembled by makeGameApp.
        let wired = makeGameAppWithDeps(config: config)
        let deps = wired.deps

        return MinesweeperAppComposition(
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

    /// Builds Minesweeper's `LiveRouteFactory` from the wired `GameDeps`. Shared
    /// by the `GameConfig.makeRouteFactory` closure.
    @MainActor
    private static func makeRouteFactory(
        deps: GameDeps,
        rootViewModel: GameRootViewModel<AppRoute>,
        savedGameStore: MinesweeperSavedGameStore,
        personalRecordStore: MinesweeperPersonalRecordStore
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
            personalRecordStore: personalRecordStore,
            onPresentBoard: {
                #if os(iOS)
                { [rootViewModel] route in rootViewModel.presentGame(route: route) }
                #else
                nil
                #endif
            }(),
            // #685: Settings Game Center row now shares the Home leaderboard
            // card's signed-out guard instead of calling
            // `GameCenterDashboard.present()` unconditionally.
            presentGameCenter: { [rootViewModel] in
                rootViewModel.presentGameCenterOrAlert { GameCenterDashboard.present() }
            }
        )
    }

}

/// Sentinel thrown by the `.live()` puzzle loader stub — MS has no
/// PuzzleProvider; its resume path (#455) goes through `MinesweeperPersistence`,
/// never through Sudoku-shaped `SavedGameStore.loadOrCreate`.
private struct MinesweeperLivePuzzleLoaderUnavailable: Error {}
