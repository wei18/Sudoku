// Live composition — concrete impls for production. docs/v1/design.md §How.1.
//
// #556 SDD-005 Pillar B: the game-agnostic live wiring (Telemetry + MetricKit +
// errorReporter + GameCenter + Persistence + monetization + audio + ATT +
// reminders) now lives in `GameAppKit.makeGameApp`. `live()` builds a
// `GameConfig<AppRoute>` carrying ONLY the Sudoku-specific values + builder
// closures (puzzle loader, route factory, home, resume mapping, copy) and calls
// `makeGameAppWithDeps`, which returns the wired `GameDeps` bag + root VM +
// route factory. `AppComposition` is assembled from that bag so its public
// field shape (consumed by tests + the App target) is unchanged.
//
// Behaviour-preserving: every Sudoku string + default flows through the config,
// so the wired stack is byte-identical to the former hand-rolled wiring.

internal import Foundation
internal import GameAppKit
internal import GameCenterClient
internal import GameShellUI
internal import MonetizationCore
internal import MonetizationUI
internal import Persistence
internal import SudokuPersistence
internal import Reminders
internal import SettingsUI
internal import SudokuUI
internal import SwiftUI
internal import Telemetry

#if canImport(UIKit)
internal import UIKit
#endif

extension AppComposition {

    public static func live() -> AppComposition {
        // PuzzleStore (default generator, v1 version). Kept here because the
        // puzzle loader closure + the route factory both reference it.
        let puzzleStore = PuzzleStore()

        // Sudoku-specific identifiers (banner ad unit + ASC product IDs) are
        // declared here, NOT inside AppMonetizationKit, so the package can be
        // linked by a second app (Minesweeper) without baking Sudoku IDs into
        // its binary. See `meetings/2026-05-31_minesweeper-rfc.md` §5.2.
        let sudokuRemoveAdsProductID = "com.wei18.sudoku.iap.remove_ads"

        // Shared daily-ready notification payload — used both by the primer
        // (initial schedule) and the #321 Settings time picker (reschedule on
        // change) so re-scheduling never drifts the title/body.
        let dailyReadyContent = ReminderContent(
            title: "Today's Sudoku is ready",
            body: "Your daily puzzle is waiting — keep your streak going."
        )
        // Copy passed as `LocalizedStringKey` literals so the app bundle's
        // `Localizable.xcstrings` localizes them (ai-translated-localization
        // sweep adds the non-en locales).
        let primerCopy = ReminderPrimerCopy(
            title: "Never miss a Daily",
            lede: "We'll let you know the moment tomorrow's Daily Sudoku is ready.",
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
            message: "Notifications are turned off for Sudoku in Settings, so we can't tell you when the Daily is ready.",
            openSettingsCTA: "Open Settings",
            dismissCTA: "Not now",
            macOSGuidance: "Enable notifications in System Settings → Notifications → Sudoku."
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
            subsystem: "com.wei18.sudoku",
            ckConfig: .sudoku,
            removeAdsProductId: sudokuRemoveAdsProductID,
            puzzleLoader: { puzzleId in
                try await puzzleStore.puzzle(for: puzzleId)
            },
            theme: DefaultTheme(),
            title: "Sudoku",
            // Sudoku builds its sidebar from the live `HomeViewModel` inside
            // `RootView`; the shared `GameRoot` path is not the mounted surface
            // for Sudoku (see `rootView`), so an empty literal here is correct.
            sidebarItems: [],
            successTint: DefaultTheme().status.success.resolved,
            failureTint: DefaultTheme().status.error.resolved,
            audio: AudioConfig(keyPrefix: "com.wei18.sudoku.audio"),
            reminders: ReminderContentConfig(
                dailyReadyContent: dailyReadyContent,
                primerCopy: primerCopy,
                deniedCopy: deniedCopy,
                settingsCopy: settingsCopy
            ),
            settingsNotices: makeSettingsNotices(),
            // #455: map Sudoku's `SavedGameSummary` into the game-agnostic
            // `ResumeCandidate` (the only layer that knows the Sudoku type).
            // Strings match the former `ResumePill` rendering exactly so snapshot
            // baselines do not move ("Resume Easy", "3:21" for 201s).
            fetchResume: { deps in
                { [persistence = deps.persistence] in
                    guard let summary = try await persistence.latestInProgress() else { return nil }
                    return ResumeCandidate(
                        title: "Resume \(summary.difficulty.rawValue.capitalized)",
                        subtitle: AppComposition.elapsed(summary.elapsedSeconds),
                        route: .board(puzzleId: summary.puzzleId)
                    )
                }
            },
            makeRouteFactory: { deps, rootViewModel in
                AppComposition.makeRouteFactory(
                    deps: deps,
                    rootViewModel: rootViewModel,
                    puzzleStore: puzzleStore
                )
            },
            makeHome: { deps, rootViewModel in
                AnyView(
                    RootView(
                        viewModel: rootViewModel,
                        routeFactory: AppComposition.makeRouteFactory(
                            deps: deps,
                            rootViewModel: rootViewModel,
                            puzzleStore: puzzleStore
                        ),
                        adProvider: deps.adProvider,
                        adGate: deps.adGate,
                        monetizationController: deps.monetizationController,
                        toastController: deps.toastController,
                        attPrimer: deps.attPrimer
                    )
                )
            },
            // A tapped `dailyReady` reminder deep-links to the Daily hub
            // (flow S07→S09), pushing `.daily` unless already on top. Mirrors
            // the former `ReminderDelegateRetainer` tap routing exactly.
            reminderTapRoute: { identifier, rootViewModel in
                guard identifier == ReminderKind.dailyReady.rawValue else { return }
                if rootViewModel.path.last != .daily {
                    rootViewModel.path.append(.daily)
                }
            }
        )

        // Wire the shared live stack once. The returned `deps` bag + root VM +
        // route factory are the single source of truth — no second construction
        // (so `MonetizationStateController.startListeningForLifetimeOfApp()` runs
        // exactly once, inside `makeGameApp`).
        let wired = makeGameAppWithDeps(config: config)
        let deps = wired.deps

        return AppComposition(
            rootViewModel: wired.rootViewModel,
            routeFactory: wired.routeFactory,
            puzzleProvider: puzzleStore,
            persistence: deps.persistence,
            gameCenter: deps.gameCenter,
            telemetry: deps.telemetry,
            errorReporter: deps.errorReporter,
            adProvider: deps.adProvider,
            iapClient: deps.iapClient,
            adGate: deps.adGate,
            monetizationStateStore: deps.monetizationStateStore,
            monetizationController: deps.monetizationController,
            toastController: deps.toastController,
            attPrimer: deps.attPrimer
        )
    }

    /// Builds Sudoku's `LiveRouteFactory` from the wired `GameDeps`. Shared by
    /// the `GameConfig.makeRouteFactory` + `makeHome` closures so both produce a
    /// factory wired to the same live seams. The reminder builder closures come
    /// straight off the deps bag (assembled once inside `makeGameApp`).
    @MainActor
    private static func makeRouteFactory(
        deps: GameDeps,
        rootViewModel: GameRootViewModel<AppRoute>,
        puzzleStore: PuzzleStore
    ) -> any RouteFactory<AppRoute> {
        LiveRouteFactory(
            puzzleProvider: puzzleStore,
            persistence: deps.persistence,
            gameCenter: deps.gameCenter,
            telemetry: deps.telemetry,
            errorReporter: deps.errorReporter,
            adProvider: deps.adProvider,
            iapClient: deps.iapClient,
            adGate: deps.adGate,
            monetizationController: deps.monetizationController,
            toastController: deps.toastController,
            makeDailyReminderPrimer: deps.makeDailyReminderPrimer,
            makeReminderSettings: deps.makeReminderSettings,
            settingsNotices: makeSettingsNotices(),
            soundPlayer: deps.soundPlayer,
            audioSettings: deps.audioSettings,
            // SDD-003 Epic 1: wire board routes to the modal presentation path.
            // iOS-only: `.fullScreenCover` is gated `#if os(iOS)` in GameRoot.
            onPresentBoard: {
                #if os(iOS)
                { [rootViewModel] route in rootViewModel.presentGame(route: route) }
                #else
                nil
                #endif
            }()
        )
    }

    /// #331: builds the Sudoku Notices section config. Acknowledgements
    /// deep-links to the app's iOS Settings page (where LicensePlist's
    /// `Settings.bundle` surfaces); omitted on macOS (no deep-link). Copyright
    /// is derived locally. Privacy/support URLs intentionally unwired pending a
    /// canonical public URL (see the #331 meeting note).
    @MainActor
    private static func makeSettingsNotices() -> SettingsNoticesConfig {
        let year = Calendar.current.component(.year, from: Date())
        var onAcknowledgements: (@MainActor () -> Void)?
        #if canImport(UIKit)
        onAcknowledgements = {
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
        }
        #endif
        return SettingsNoticesConfig(
            onAcknowledgements: onAcknowledgements,
            copyright: "© \(year) Wei"
        )
    }

}
