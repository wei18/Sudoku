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
        // #935 batch 3: DEBUG-only fault injection for the daily re-view
        // completion route (N13) — see `resolveDailyOverlayReading`. A no-op
        // pass-through outside DEBUG / without the matching launch arg, so
        // this is `savedGameStore` itself in every production launch.
        let dailyOverlayReading = resolveDailyOverlayReading(live: savedGameStore)

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
            successTint: MinesweeperTheme().status.success.resolved,
            failureTint: MinesweeperTheme().status.error.resolved,
            // #950: reuses the same "attention, not error" tint already used
            // by loading/hub indicators (MinesweeperBoardLoaderView, MinesweeperDailyHubView).
            infoTint: MinesweeperTheme().status.warning.resolved,
            audio: AudioConfig(keyPrefix: "com.wei18.minesweeper.audio"),
            reminders: ReminderContentConfig(
                dailyReadyContent: dailyReadyContent,
                primerCopy: primerCopy,
                deniedCopy: deniedCopy,
                settingsCopy: settingsCopy
            ),
            // #1020: pushed by the shared trailing gear on every tab root
            // (`TabRootChrome`) — Settings lands inside the initiating tab.
            settingsRoute: .settings,
            // #1020: per-tab root content — Today / Practice / Progress
            // replace the retired HOME mode-card config entirely
            // (`sidebarAdaptable` generates its own chrome from `AppTab`, so
            // there is no mode-card list or sidebar array left to configure).
            // The bulk of this lives in `Live+TabRoots.swift` (kept out of
            // this file to stay under SwiftLint's 400-line ceiling).
            makeTabRoot: { tab, deps, rootViewModel in
                MinesweeperAppComposition.makeTabRoot(
                    tab: tab,
                    persistence: deps.persistence,
                    errorReporter: deps.errorReporter,
                    telemetry: deps.telemetry,
                    adProvider: deps.adProvider,
                    adGate: deps.adGate,
                    savedGameStore: savedGameStore,
                    dailyOverlayReading: dailyOverlayReading,
                    personalRecordStore: personalRecordStore,
                    rootViewModel: rootViewModel
                )
            },
            // #455 / #572: map MinesweeperSavedGameSummary into the game-agnostic
            // ResumeCandidate. Strings match the former ResumePill rendering exactly
            // so snapshot baselines do not move.
            // #1017: also build a `BoardPreview` from the already-fetched
            // `stateBlob` (no new CloudKit fetch). A malformed/missing blob
            // degrades to `boardPreview == nil` — never blocks resume.
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
                        ),
                        boardPreview: MinesweeperBoardPreviewMapper.make(stateBlob: summary.stateBlob)
                    )
                }
            },
            makeRouteFactory: { deps, rootViewModel in
                MinesweeperAppComposition.makeRouteFactory(
                    deps: deps,
                    rootViewModel: rootViewModel,
                    savedGameStore: savedGameStore,
                    dailyOverlayReading: dailyOverlayReading,
                    personalRecordStore: personalRecordStore
                )
            },
            // A tapped `dailyReady` reminder deep-links to the Today tab
            // (mirrors Sudoku's SudokuAppComposition.live() reminderTapRoute).
            // #1020: Today's Daily hub is a tab identity now, not a pushed
            // route — land on its root by selecting the tab and popping any
            // stack on top of it back to that root.
            reminderTapRoute: { identifier, rootViewModel in
                guard identifier == ReminderKind.dailyReady.rawValue else { return }
                rootViewModel.selectedTab = .today
                rootViewModel.popToRoot(of: .today)
            }
        )

        // Wire the shared live stack once. The returned wired.view is the
        // live mount point: GameRoot + the #1020 `sidebarAdaptable` 3-tab
        // shell (Today/Practice/Progress) + universal ResumePill (#554) + ATT
        // sheet + GC-signed-out alert, assembled by makeGameApp.
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

    /// Builds Minesweeper's `LiveRouteFactory` from the wired `GameDeps`. Called
    /// from the `GameConfig.makeRouteFactory` closure so pushed destinations
    /// (Board / Completion / ResumeBoard / Settings) are wired to the same live
    /// seams as the tab roots `Live+TabRoots.swift` builds.
    @MainActor
    private static func makeRouteFactory(
        deps: GameDeps,
        rootViewModel: GameRootViewModel<AppRoute>,
        savedGameStore: MinesweeperSavedGameStore,
        dailyOverlayReading: (any MinesweeperDailyOverlayReading)?,
        personalRecordStore: MinesweeperPersonalRecordStore
    ) -> any RouteFactory<AppRoute> {
        // #968: macOS has zero ads to remove (Google ships no macOS AdMob/UMP
        // xcframework slice — D-v2-03), so Settings must not offer "Remove
        // Ads" / "Restore Purchases" there (Guideline 2.1 / 3.1.1 — the IAP
        // would visibly do nothing). `SettingsView` already renders the whole
        // Purchases section only when its `monetizationController` param is
        // non-nil, so passing `nil` into `LiveRouteFactory` on macOS is the
        // entire fix; `deps.monetizationController` itself stays wired
        // unconditionally (unchanged plumbing).
        let settingsMonetizationController: MonetizationStateController? = {
            #if os(iOS)
            deps.monetizationController
            #else
            nil
            #endif
        }()
        return LiveRouteFactory(
            monetizationController: settingsMonetizationController,
            adProvider: deps.adProvider,
            adGate: deps.adGate,
            persistence: deps.persistence,
            gameCenter: deps.gameCenter,
            errorReporter: deps.errorReporter,
            toastController: deps.toastController,
            reminderSettings: deps.reminderSettings,
            // #814: Daily-win reminder primer builder off the shared deps bag
            // (mirrors Sudoku's makeRouteFactory wiring).
            makeDailyReminderPrimer: deps.makeDailyReminderPrimer,
            soundPlayer: deps.soundPlayer,
            audioSettings: deps.audioSettings,
            savedGameStore: savedGameStore,
            dailyOverlayReading: dailyOverlayReading,
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
            },
            // #744: shareAppTapped / writeReviewTapped / inviteFriendsTapped —
            // simple UI-tap events, not the Sudoku-shaped game-outcome events
            // #699 scoped MS OUT of (see `telemetry` field's doc comment).
            // #773: also fans out the Statistics screen-viewed event.
            telemetry: deps.telemetry,
            // Dormant since the #983 follow-up removed its only reader (the
            // reverted `.dailyRank` route) — see `LiveRouteFactory`'s
            // `currentAuthState` doc comment. Mirrors Sudoku's `makeRouteFactory`.
            currentAuthState: { [rootViewModel] in rootViewModel.authState }
        )
    }

}

/// Sentinel thrown by the `.live()` puzzle loader stub — MS has no
/// PuzzleProvider; its resume path (#455) goes through `MinesweeperPersistence`,
/// never through Sudoku-shaped `SavedGameStore.loadOrCreate`.
private struct MinesweeperLivePuzzleLoaderUnavailable: Error {}
