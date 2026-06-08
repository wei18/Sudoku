// Live + Preview composition for MinesweeperAppComposition.
//
// Mirrors Sudoku's split (`AppComposition/Live.swift` + `Preview.swift`)
// collapsed into one file — the Minesweeper bag is small enough to keep
// both factories adjacent until Game Center / additional surfaces grow.
//
// `.live()` wires:
//   - `Telemetry(sinks: [OSLogSink, NoOpTrackingSink])` — OSLog subsystem
//     `com.wei18.minesweeper`, category `Telemetry`. MetricKit sink
//     intentionally NOT installed yet.
//   - `LiveErrorReporter(telemetry:)`.
//   - `LivePersistence(ckConfig: .minesweeper, ...)` — puzzle loader is a
//     no-op stub; MS has no PuzzleProvider yet and no SavedGame flow
//     hits it. Wired via the `PrivateCKConfig.minesweeper` namespace from
//     PR #257 so the MS zone / subscription IDs never collide with Sudoku.
//   - `LiveStoreKit2IAPClient(knownProductIds: [...])` — MS Remove Ads SKU
//     from PR #258.
//   - `LiveAdMobAdProvider` on iOS (DEBUG = Google universal test banner,
//     Release = fatalError gate per Sudoku precedent until v1 release
//     checklist swaps in MS production banner id from project memory
//     `minesweeper-admob-ids`); `NoopAdProvider` on macOS (AdMob SDK is
//     iOS-only). Wired in U15 (2026-06-03).
//   - `AdGate(store: persistence.monetizationStateStore(),
//             onPersistenceError: telemetry funnel)`.
//   - `MonetizationStateController(productId: minesweeperRemoveAdsProductId,
//             ...)` — the parameterized init shipped with this PR so the
//             same controller drives MS's ASC product instead of Sudoku's.
//   - `ToastController()` — mounted on MinesweeperRoot via `.toastOverlay`
//     (wired in U15 / PR #263; surfaced through `composition.rootView`).
//
// `.preview()` wires fakes from MonetizationTesting + `FakePersistence`
// (PersistenceTesting, zero-IO — #261) so no Preview path can trap on a real
// CloudKit gateway. Mirrors Sudoku's AppComposition Preview.

internal import AdsAdMob
internal import Foundation
internal import GameCenterClient
internal import GameCenterTesting
// #313: `MinesweeperRootViewModel` (launch-bootstrap VM) lives in MinesweeperUI.
internal import MinesweeperUI
internal import IAPStoreKit2
internal import MonetizationCore
internal import MonetizationTesting
internal import MonetizationUI
internal import Persistence
internal import PersistenceTesting
internal import Reminders
internal import Telemetry
// #287: `ReminderSettingsModel` + the primer/section copy types live in
// GameShellUI; `MinesweeperReminderSettingsEntry` lives in MinesweeperUI.
internal import GameShellUI

extension MinesweeperAppComposition {

    /// Production wiring.
    public static func live() -> MinesweeperAppComposition {
        let telemetry = Telemetry(sinks: [
            OSLogSink(subsystem: "com.wei18.minesweeper", category: "Telemetry"),
            NoOpTrackingSink()
        ])
        let errorReporter: any ErrorReporter = LiveErrorReporter(telemetry: telemetry)

        // Game Center client (#291). Shared GameCenterKit seam — GameKit is
        // fully encapsulated inside `LiveGameCenterClient` / `GKAuthDriver`.
        // The board VM submits a best-time on win; the Home Leaderboard card
        // presents the native dashboard. Mirrors Sudoku's `AppComposition.Live`.
        let gameCenter: any GameCenterClient = LiveGameCenterClient(authDriver: GKAuthDriver())

        // Persistence. Puzzle loader is a no-op stub — MS has no
        // PuzzleProvider yet and SavedGameStore.fetch never fires for MS
        // until the save-flow lands (separate dispatch). Throwing on call
        // makes the absence loud if something does call into it.
        let persistence = LivePersistence(
            telemetry: telemetry,
            ckConfig: .minesweeper,
            puzzleLoader: { _ in
                throw MinesweeperLivePuzzleLoaderUnavailable()
            }
        )

        // Monetization state store + AdGate. Same Telemetry funnel shape as
        // Sudoku — `AdGate` doesn't depend on Telemetry directly; we inject
        // the sink via `onPersistenceError`.
        let monetizationStateStore = persistence.monetizationStateStore()
        let adGate = AdGate(
            store: monetizationStateStore,
            onPersistenceError: { [telemetry] error in
                Task {
                    await telemetry.observe(
                        .errorOccurred(
                            source: "AdGate",
                            code: "save_failed",
                            message: String(describing: error)
                        )
                    )
                }
            }
        )

        // AdProvider: live AdMob on iOS, Noop on macOS (AdMob SDK ships an
        // iOS-only xcframework — see AppMonetizationKit/Package.swift gating).
        // Mirrors Sudoku's `Live.swift` shape exactly. MS-specific identifiers
        // live here (banner ad unit), NOT inside AppMonetizationKit, so the
        // package can be linked by Sudoku without baking MS IDs into its
        // binary (and vice-versa). The DEBUG-gate keeps debug builds on
        // Google's universal test banner so real-device verification never
        // accidentally serves production creatives. Release builds use MS's
        // production banner unit registered with the AdMob console.
        #if os(iOS)
        // Banner ad unit ID via Info.plist `GADBannerUnitID` key, substituted
        // at build time from `Tuist/AdMob.xcconfig` (gitignored; .example
        // committed). XCC writes the xcconfig from per-workflow env vars;
        // local builds use the .example sandbox values. Replaces the old
        // DEBUG-vs-Release fatalError gate with smoke-test (key presence —
        // `MinesweeperUITests/InfoPlistAdMobKeysTests`) + runtime guard
        // below (catches missing-key + empty + unresolved-`$()` token
        // before AdMob SDK init).
        guard
            let minesweeperBannerAdUnitID = Bundle.main
                .object(forInfoDictionaryKey: "GADBannerUnitID") as? String,
            !minesweeperBannerAdUnitID.isEmpty,
            !minesweeperBannerAdUnitID.hasPrefix("$(")
        else {
            preconditionFailure(
                "GADBannerUnitID missing or unresolved — check"
                    + " Tuist/AdMob.xcconfig exists locally or that XCC env"
                    + " vars are set for Release builds."
            )
        }
        let adProvider: any AdProvider = LiveAdMobAdProvider(bannerAdUnitID: minesweeperBannerAdUnitID)
        #else
        let adProvider: any AdProvider = NoopAdProvider()
        #endif

        // IAP client. Telemetry-funnels catalog desync into the same channel
        // Sudoku uses so the M3 placeholder substitution doesn't silently
        // mask backend issues.
        let iapClient: any IAPClient = LiveStoreKit2IAPClient(
            knownProductIds: [minesweeperRemoveAdsProductId],
            onCatalogDesync: { [telemetry] productId in
                Task {
                    await telemetry.observe(
                        .errorOccurred(
                            source: "LiveStoreKit2IAPClient",
                            code: "catalog_desync_post_purchase",
                            message: "post-purchase refetch returned empty for productId=\(productId)"
                        )
                    )
                }
            }
        )

        let toastController = ToastController()

        let monetizationController = MonetizationStateController(
            iapClient: iapClient,
            stateStore: monetizationStateStore,
            adGate: adGate,
            toastController: toastController,
            productId: minesweeperRemoveAdsProductId
        )
        // Mirror Sudoku: opt in to lifetime-of-app purchaseUpdates() exactly
        // once at composition.
        monetizationController.startListeningForLifetimeOfApp()

        // #287: reminder wiring — mirrors Sudoku's AppComposition. RemindersKit's
        // Live conformers + `UNUserNotificationCenter` stay confined here. The
        // Settings Reminders entry is the user-initiated permission-priming path
        // (MS has no post-Daily primer flow). The fire-time persists in a
        // device-local `UserDefaults` pair under an MS-namespaced key prefix
        // (`com.wei18.minesweeper.reminder.*`) — a reminder fires on the device
        // that scheduled it, so it is NOT CloudKit-synced. `reminderEmit` bridges
        // the model's decoupled `Event` to the `Telemetry` facade.
        let reminderAuthorizer = LiveNotificationAuthorizer(subsystem: "com.wei18.minesweeper")
        let reminderScheduler = LiveReminderScheduler(subsystem: "com.wei18.minesweeper")
        let reminderEmit: @Sendable (ReminderSettingsModel.Event) -> Void = { [telemetry] event in
            let telemetryEvent: TelemetryEvent?
            switch event {
            case let .scheduled(kind): telemetryEvent = .reminderScheduled(kind: kind)
            case let .primerAccepted(kind): telemetryEvent = .reminderPrimerAccepted(kind: kind)
            case let .primerDeclined(kind): telemetryEvent = .reminderPrimerDeclined(kind: kind)
            case .cancelled: telemetryEvent = nil
            }
            guard let telemetryEvent else { return }
            Task { await telemetry.observe(telemetryEvent) }
        }
        let reminderDefaults = UserDefaults.standard
        let reminderHourKey = "com.wei18.minesweeper.reminder.dailyReadyHour"
        let reminderMinuteKey = "com.wei18.minesweeper.reminder.dailyReadyMinute"
        let reminderContent = ReminderContent(
            title: "Today's Minesweeper is ready",
            body: "Your daily boards are waiting — keep your streak going."
        )
        let makeReminderSettings: @MainActor () -> MinesweeperReminderSettingsEntry = {
            let model = ReminderSettingsModel(
                permissionModel: ReminderPermissionModel(authorizer: reminderAuthorizer),
                scheduler: reminderScheduler,
                kind: .dailyReady,
                content: reminderContent,
                getFireTime: {
                    // Missing key → 9:00 AM default (UserDefaults.integer returns 0
                    // for absent keys, indistinguishable from midnight — gate on
                    // presence). Mirrors Sudoku's ReminderSettingsStore default.
                    guard reminderDefaults.object(forKey: reminderHourKey) != nil else {
                        return (hour: 9, minute: 0)
                    }
                    return (
                        hour: reminderDefaults.integer(forKey: reminderHourKey),
                        minute: reminderDefaults.integer(forKey: reminderMinuteKey)
                    )
                },
                setFireTime: { time in
                    reminderDefaults.set(time.hour, forKey: reminderHourKey)
                    reminderDefaults.set(time.minute, forKey: reminderMinuteKey)
                },
                emit: reminderEmit
            )
            return MinesweeperReminderSettingsEntry(
                model: model,
                copy: ReminderSettingsCopy(
                    sectionTitle: "Reminders",
                    enableTitle: "Daily reminder",
                    enableCTA: "Turn On",
                    enabledTitle: "Daily reminder",
                    enabledStatus: "On",
                    timeTitle: "Time",
                    deniedTitle: "Notifications are off",
                    deniedCTA: "Fix"
                ),
                primerCopy: ReminderPrimerCopy(
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
                ),
                deniedCopy: ReminderDeniedCopy(
                    title: "Reminders are off",
                    message: "Notifications are turned off for Minesweeper in Settings, so we can't tell you when the Daily is ready.",
                    openSettingsCTA: "Open Settings",
                    dismissCTA: "Not now",
                    macOSGuidance: "Enable notifications in System Settings → Notifications → Minesweeper."
                )
            )
        }

        let routeFactory = LiveRouteFactory(
            monetizationController: monetizationController,
            adProvider: adProvider,
            adGate: adGate,
            persistence: persistence,
            gameCenter: gameCenter,
            errorReporter: errorReporter,
            makeReminderSettings: makeReminderSettings
        )

        // #313: launch-bootstrap VM owning the GC auth handshake. Shares the
        // bag's `gameCenter` + `errorReporter` so failures funnel through the
        // same OSLog channel. Mirrors Sudoku's `AppComposition.live()`.
        let rootViewModel = MinesweeperRootViewModel(
            gameCenter: gameCenter,
            errorReporter: errorReporter
        )

        return MinesweeperAppComposition(
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

    /// Preview / test wiring. Empty-sinks `Telemetry`, fake IAP / AdGate
    /// store / AdProvider, and `FakePersistence` (zero-IO — #261). Mirrors
    /// Sudoku's `AppComposition` Preview, which also wires a fake persistence
    /// so no Preview path can trap on a real CloudKit gateway.
    public static func preview() -> MinesweeperAppComposition {
        let telemetry = Telemetry(sinks: [])
        let errorReporter: any ErrorReporter = NoopErrorReporter()

        // #291: fake GC client — zero-IO, never touches GameKit.
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
            productId: minesweeperRemoveAdsProductId
        )

        let routeFactory = LiveRouteFactory(
            monetizationController: monetizationController,
            adProvider: adProvider,
            adGate: adGate,
            persistence: persistence,
            gameCenter: gameCenter,
            errorReporter: errorReporter
        )

        // #313: preview launch-bootstrap VM over the fake GC client — zero-IO.
        let rootViewModel = MinesweeperRootViewModel(
            gameCenter: gameCenter,
            errorReporter: errorReporter
        )

        return MinesweeperAppComposition(
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

/// Sentinel thrown by the `.live()` puzzle loader stub. MS
/// has no PuzzleProvider yet; the loader closure only ever fires if
/// `SavedGameStore.fetch(...)` walks a saved record back through it, which
/// can't happen until MS save-flow lands (separate dispatch).
private struct MinesweeperLivePuzzleLoaderUnavailable: Error {}
