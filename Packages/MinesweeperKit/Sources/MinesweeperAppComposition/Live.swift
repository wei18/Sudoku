// Live + Preview composition for MinesweeperAppComposition.
//
// Mirrors Sudoku's split (`AppComposition/Live.swift` + `Preview.swift`)
// collapsed into one file — the Minesweeper bag is small enough to keep
// both factories adjacent until Game Center / additional surfaces grow.
//
// `.live()` wires:
//   - `Telemetry(sinks: [OSLogSink, NoOpTrackingSink])` — OSLog subsystem
//     `com.wei18.minesweeper`. `LiveErrorReporter(telemetry:)`.
//   - `LivePersistence(ckConfig: .minesweeper, ...)` (PR #257 namespace; the
//     puzzle-loader stub never fires) + the #455 `MinesweeperSavedGameStore`
//     over `PrivateCKGatewayFactory` (resume wiring in Live+Resume.swift).
//   - `LiveStoreKit2IAPClient(knownProductIds: [...])` — MS Remove Ads SKU.
//   - `LiveAdMobAdProvider` on iOS (DEBUG = Google universal test banner;
//     prod id swap on the v1 release checklist — `minesweeper-admob-ids`);
//     `NoopAdProvider` on macOS (the AdMob SDK is iOS-only). U15.
//   - `AdGate(store: persistence.monetizationStateStore(), funnel)` +
//     `MonetizationStateController(productId: minesweeperRemoveAdsProductId)`.
//   - `ToastController()` — mounted on MinesweeperRoot via `.toastOverlay`.
//
// `.preview()` wires fakes from MonetizationTesting + `FakePersistence`
// (PersistenceTesting, zero-IO — #261) so no Preview path can trap on a real
// CloudKit gateway. Mirrors Sudoku's AppComposition Preview.

internal import AdsAdMob
internal import Foundation
// #330 P2: `.live()` builds `LiveAudioSession` + `LiveHaptics` + `LiveSoundPlayer`
// and `AudioSettingsModel`; `.preview()` wires `NoopSoundPlaying`. `AVFoundation`
// stays inside GameAudioKit's Live files — composition sees only the seams.
internal import GameAudio
internal import GameCenterClient
internal import GameCenterTesting
// #313: `MinesweeperRootViewModel` (launch-bootstrap VM) lives in MinesweeperUI.
internal import MinesweeperPersistence
internal import MinesweeperUI
internal import IAPStoreKit2
internal import MonetizationCore
internal import MonetizationTesting
internal import MonetizationUI
internal import Persistence
internal import PersistenceTesting
internal import Reminders
internal import Telemetry
// refactor/settingskit-target (2026-06-09): `ReminderSettingsModel` /
// `ReminderPermissionModel` + the primer/section/denied copy types moved out of
// GameShellUI into SettingsUI; `MinesweeperReminderSettingsEntry` lives in
// MinesweeperUI. `.live()` builds the reminders entry here.
internal import SettingsUI

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

        // Audio stack (#330 P2). Mirrors the monetization / reminder wiring shape:
        // every framework-touching conformer is constructed here and only the
        // `SoundPlaying` seam leaves the composition root.
        //   - `LiveAudioSession.configureAmbient()` runs once at boot so game audio
        //     mixes with other apps (the user's podcast keeps playing).
        //   - `LiveSoundPlayer` reads sfx/music assets from `Bundle.main` by
        //     `soundKey`. P2 ships NO assets (P3 adds the zen-wood set), so every
        //     `play` / `playMusic` tolerates the missing file and no-ops (silent).
        //   - `AudioSettingsModel` persists mute / volumes / BGM / haptics in a
        //     device-local MS-namespaced `UserDefaults` pair, and pushes every
        //     change to the live player. Defaults per spec: BGM on, haptics on, not
        //     muted, volumes 0.7. Like reminders, the fire-time is device-local
        //     (NOT CloudKit-synced) — audio preference is a per-device setting.
        let audioSession = LiveAudioSession(subsystem: "com.wei18.minesweeper")
        audioSession.configureAmbient()
        let soundPlayer: any SoundPlaying = LiveSoundPlayer(
            session: audioSession,
            haptics: LiveHaptics(),
            subsystem: "com.wei18.minesweeper"
        )
        let audioDefaults = UserDefaults.standard
        let audioKeyPrefix = "com.wei18.minesweeper.audio."
        let audioSettings = MinesweeperAppComposition.makeAudioSettings(
            player: soundPlayer,
            defaults: audioDefaults,
            keyPrefix: audioKeyPrefix
        )

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
            // The user turned reminders off in-app — observe the on→off funnel.
            case let .cancelled(kind): telemetryEvent = .reminderCancelled(kind: kind)
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
                    disableTitle: "Turn off reminders",
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

        // #455 step 4: saved-game store over the public gateway factory
        // (same container/zone `LivePersistence.bootstrap()` provisions).
        let savedGameStore = MinesweeperSavedGameStore(
            gateway: PrivateCKGatewayFactory.live(config: .minesweeper),
            telemetry: telemetry
        )

        let routeFactory = LiveRouteFactory(
            monetizationController: monetizationController,
            adProvider: adProvider,
            adGate: adGate,
            persistence: persistence,
            gameCenter: gameCenter,
            errorReporter: errorReporter,
            // #284: shared toast — clear-cache feedback lands on it.
            toastController: toastController,
            makeReminderSettings: makeReminderSettings,
            // #330 P2: gameplay audio + the shared Sound settings section.
            soundPlayer: soundPlayer,
            audioSettings: audioSettings,
            savedGameStore: savedGameStore
        )

        // #313: launch-bootstrap VM (GC auth + persistence bootstrap); shares
        // the bag's funnel. Mirrors Sudoku's `AppComposition.live()`.
        let rootViewModel = MinesweeperRootViewModel(
            gameCenter: gameCenter,
            persistence: persistence,
            errorReporter: errorReporter,
            // #455 step 4: lights the Home resume pill (see Live+Resume.swift).
            fetchResume: makeFetchResume(store: savedGameStore)
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

    /// Preview / test wiring: empty-sinks `Telemetry`, fake IAP / AdGate
    /// store / AdProvider, `FakePersistence` (zero-IO — #261) — no Preview
    /// path can trap on a real CloudKit gateway (mirrors Sudoku's Preview).
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
            errorReporter: errorReporter,
            toastController: toastController,
            // #330 P2: preview audio is the silent Noop — zero-IO, never touches
            // AVFoundation / the system audio session. `audioSettings` stays nil so
            // the preview Settings screen is byte-identical (no Sound section).
            soundPlayer: NoopSoundPlaying()
        )

        // #313: preview launch-bootstrap VM over the fake GC client + fake
        // persistence — zero-IO.
        let rootViewModel = MinesweeperRootViewModel(
            gameCenter: gameCenter,
            persistence: persistence,
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

/// Sentinel thrown by the `.live()` puzzle loader stub — MS has no
/// PuzzleProvider; its resume path (#455) goes through `MinesweeperPersistence`,
/// never through Sudoku-shaped `SavedGameStore.loadOrCreate`.
private struct MinesweeperLivePuzzleLoaderUnavailable: Error {}
