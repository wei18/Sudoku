// Live composition — concrete impls for production. docs/v1/design.md §How.1.
//
// #556 SDD-005 Pillar B: the game-agnostic live wiring (Telemetry + MetricKit +
// errorReporter + GameCenter + Persistence + monetization + audio + ATT +
// reminders) now lives in `GameAppKit.makeGameApp`. `live()` builds a
// `GameConfig<AppRoute>` carrying ONLY the Sudoku-specific values + builder
// closures (puzzle loader, route factory, home, resume mapping, copy) and calls
// `makeGameAppWithDeps`, which returns the wired `GameDeps` bag + root VM +
// route factory. `SudokuAppComposition` is assembled from that bag so its public
// field shape (consumed by tests + the App target) is unchanged.
//
// Behaviour-preserving: every Sudoku string + default flows through the config,
// so the wired stack is byte-identical to the former hand-rolled wiring.

internal import Foundation
internal import GameAppKit
internal import GameCenterClient
internal import GameShellUI
internal import MonetizationUI
internal import Persistence
internal import SudokuPersistence
internal import Reminders
internal import SettingsUI
internal import SudokuUI
internal import SwiftUI

#if canImport(UIKit)
internal import UIKit
#endif

extension SudokuAppComposition {

    public static func live() -> SudokuAppComposition {
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
            // #557: sidebarItems derived by makeGameApp from homeModes.modeItems —
            // no longer set here. The empty literal is kept for the makeHome fallback
            // path (MS / 2048 before their migration).
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
            // #557 SDD-005 Pillar C: per-mode subtitle copy + route mapping.
            // Byte-identical to the former `HomeViewModel.subtitleKey` literals
            // so snapshot baselines do not move.
            homeModes: [
                .daily: HomeModeContent(subtitleKey: "3 puzzles today", route: .daily),
                .practice: HomeModeContent(subtitleKey: "Mixed difficulty pool", route: .practice),
                .leaderboard: HomeModeContent(subtitleKey: "Global / friends"),
                .settings: HomeModeContent(subtitleKey: "Account / language", route: .settings)
            ],
            // Sudoku's Game Center dashboard presenter. Injected here (not inside
            // GameAppKit) so GameAppKit stays free of the GK dependency.
            presentLeaderboard: { GameCenterDashboard.present() },
            // #773: Home's secondary-weight Statistics entry pushes this route.
            statsRoute: .stats,
            // #455: map Sudoku's `SavedGameSummary` into the game-agnostic
            // `ResumeCandidate` (the only layer that knows the Sudoku type).
            // Strings match the former `ResumePill` rendering exactly so snapshot
            // baselines do not move ("Resume Easy", "3:21" for 201s).
            fetchResume: { deps in
                { [persistence = deps.persistence] in
                    guard let summary = try await persistence.latestInProgress() else { return nil }
                    return ResumeCandidate(
                        title: ResumeTitle.make(
                            difficultyKey: summary.difficulty.rawValue.capitalized
                        ),
                        subtitle: ResumeTitle.elapsed(summary.elapsedSeconds),
                        route: .board(puzzleId: summary.puzzleId)
                    )
                }
            },
            makeRouteFactory: { deps, rootViewModel in
                SudokuAppComposition.makeRouteFactory(
                    deps: deps,
                    rootViewModel: rootViewModel,
                    puzzleStore: puzzleStore
                )
            },
            // makeHome is superseded by the universal GameHomeView built from
            // homeModes in makeGameApp (#557). Kept for API stability; ignored
            // by makeGameApp when homeModes is non-empty.
            makeHome: { _, _ in AnyView(EmptyView()) },
            // A tapped `dailyReady` reminder deep-links to the Daily hub
            // (flow S07→S09), pushing `.daily` unless already on top. Mirrors
            // the former `ReminderDelegateRetainer` tap routing exactly.
            reminderTapRoute: { identifier, rootViewModel in
                guard identifier == ReminderKind.dailyReady.rawValue else { return }
                if rootViewModel.path.last != .daily {
                    rootViewModel.path.append(.daily)
                }
            },
            // #579 phase 2: wire GameCenterSink as a late-bound completion sink.
            // SubmitGuards seeded empty (see impl-notes §Decisions: within-session
            // dedup holds; a once-per-launch re-submit of an already-submitted
            // daily is harmless for best-score leaderboards).
            // Known limitation (#579): a completion landing in the sub-second
            // before boot `authenticate()` resolves sees `authState == .unknown`
            // and no-ops (no retry — §How.3.4 forbids an offline queue). The
            // window is practically unreachable (a solve takes far longer).
            // `[weak rootViewModel]` avoids the sink → rootVM → persistence →
            // telemetry → sink retain cycle (both ends are process-lifetime, so
            // benign, but the weak ref keeps the graph clean).
            // Order matters (#578 CR): DeferredSink forwards to sinks in array
            // order, so PersonalRecordSink must WRITE the new completedCount
            // BEFORE GameCenterSink's AchievementEvaluator READS it — otherwise
            // count achievements (practice.complete_10/100, hard.master) fire one
            // completion late.
            makeCompletionSinks: { deps, rootViewModel in
                [
                    PersonalRecordSink(
                        persistence: deps.persistence,
                        errorReporter: deps.errorReporter
                    ),
                    GameCenterSink(
                        client: deps.gameCenter,
                        guards: SubmitGuards(),
                        achievements: AchievementEvaluator(persistence: deps.persistence),
                        authStateProvider: { [weak rootViewModel] in
                            await MainActor.run { rootViewModel?.authState ?? .unknown }
                        },
                        errorReporter: deps.errorReporter
                    )
                ]
            }
        )

        // Wire the shared live stack once. The returned `wired.view` is the
        // live mount point after #557: GameRoot + shared GameHomeView + universal
        // ResumePill + ATT sheet + GC-signed-out alert, assembled by makeGameApp.
        // `MonetizationStateController.startListeningForLifetimeOfApp()` runs
        // exactly once inside makeGameApp.
        let wired = makeGameAppWithDeps(config: config)
        let deps = wired.deps

        return SudokuAppComposition(
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
            attPrimer: deps.attPrimer,
            wiredView: wired.view
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
            }(),
            // #685: Settings Game Center row now shares the Home leaderboard
            // card's signed-out guard instead of calling
            // `GameCenterDashboard.present()` unconditionally.
            presentGameCenter: { [rootViewModel] in
                rootViewModel.presentGameCenterOrAlert { GameCenterDashboard.present() }
            },
            // #744: same signed-out guard as `presentGameCenter` above, wrapping
            // the iOS 26+/macOS 26+ "invite friends" sheet instead of the
            // dashboard. The `#available` check lives here (not just in
            // `SettingsScreen`'s row-render gate) as a second, self-documenting
            // guard at the call boundary — `GameCenterDashboard.triggerFriending()`
            // itself is `@available(iOS 26.0, macOS 26.0, *)`.
            presentInviteFriends: { [rootViewModel] in
                rootViewModel.presentGameCenterOrAlert {
                    if #available(iOS 26.0, macOS 26.0, *) {
                        GameCenterDashboard.triggerFriending()
                    }
                }
            }
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
