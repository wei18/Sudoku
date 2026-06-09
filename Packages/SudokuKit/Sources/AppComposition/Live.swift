// swiftlint:disable file_length
// (Composition root: crossed 400 lines once #287 reminders + #417 ATT wiring
//  both landed here. A composition root legitimately aggregates every live impl;
//  splitting it would scatter the single boot wiring. Matches the ASCClient /
//  MetadataConfig file_length precedent.)
//
// Live composition — concrete impls for production. docs/v1/design.md §How.1.
//
// Wires:
//   - LiveGameCenterClient(authDriver: GKAuthDriver())
//   - LivePersistence(...) bound to a PuzzleStore puzzle loader
//   - PuzzleStore() — default LivePuzzleGenerating
//   - Telemetry(sinks: [OSLogSink, NoOpTrackingSink, MetricKitSink])
//   - LiveAdMobAdProvider(bannerAdUnitID:) / LiveStoreKit2IAPClient(knownProductIds:) (v2.3.2)
//   - AdGate(store: LivePersistence.monetizationStateStore()) (v2.3.2)
//   - LiveRouteFactory composing all of the above (v2.3.3)

internal import AdsAdMob
internal import Foundation
internal import GameCenterClient
internal import GameShellUI
internal import IAPStoreKit2
internal import MonetizationCore
internal import MonetizationUI
internal import Persistence
internal import PuzzleStore
internal import Reminders
// refactor/settingskit-target: `ReminderSettingsModel` / `ReminderPermissionModel`
// + the primer/section/denied copy types + `SettingsNoticesConfig` moved out of
// GameShellUI into SettingsUI; `.live()` builds the reminders entry + notices here.
internal import SettingsUI
internal import SudokuUI
internal import SwiftUI
internal import Telemetry

#if canImport(UIKit)
internal import UIKit
#endif

extension AppComposition {

    public static func live() -> AppComposition {
        // Telemetry fan-out: OSLog + NoOp tracking. MetricKit projects its
        // diagnostic payloads BACK INTO this same Telemetry instance via the
        // process-wide retained sink below.
        let telemetry = Telemetry(sinks: [
            OSLogSink(subsystem: "com.wei18.sudoku", category: "Telemetry"),
            NoOpTrackingSink()
        ])
        LiveMetricKitRetainer.install(downstream: telemetry)

        // M10 (issue #67): unified error funnel. All VM / loader catch sites
        // that previously `try?`-swallowed CloudKit / Persistence errors now
        // route through this reporter, which fans into the same Telemetry
        // facade as every other event (so OSLog + future tracking sinks both
        // see the failure) and retains a bounded ring buffer of the most
        // recent 20 reports for future diagnostic surfaces.
        let errorReporter: any ErrorReporter = LiveErrorReporter(telemetry: telemetry)

        // PuzzleStore (default generator, v1 version).
        let puzzleStore = PuzzleStore()

        // Persistence facade. The puzzle loader closure routes through the
        // same PuzzleStore so SavedGameStore can re-derive a Puzzle from a
        // stored puzzleId (no Puzzle blob in CloudKit).
        let persistence = LivePersistence(
            telemetry: telemetry,
            ckConfig: .sudoku,
            puzzleLoader: { puzzleId in
                try await puzzleStore.puzzle(for: puzzleId)
            }
        )

        // Game Center client.
        let gameCenter = LiveGameCenterClient(authDriver: GKAuthDriver())

        // v2 monetization deps.
        let monetizationStateStore = persistence.monetizationStateStore()
        // Route AdGate's CloudKit save failures into the same Telemetry
        // facade other subsystems use. `AdGate` doesn't depend on Telemetry
        // directly — the host injects the sink so MonetizationCore stays
        // observability-stack-free (M2 from v2-audit-code-polish).
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
        // AdMob SDK ships iOS-only binaries — see AppMonetizationKit/Package.swift
        // gating. On macOS we wire the `NoopAdProvider` (status always
        // `.suppressed`, BannerSlotView collapses to EmptyView); on iOS we use
        // the live AdMob-backed provider as before.
        //
        // Sudoku-specific identifiers (banner ad unit + ASC product IDs) are
        // declared here, NOT inside AppMonetizationKit, so the package can be
        // linked by a second app (Minesweeper) without baking Sudoku IDs into
        // its binary. See `meetings/2026-05-31_minesweeper-rfc.md` §5.2.
        //
        let sudokuRemoveAdsProductID = "com.wei18.sudoku.iap.remove_ads"

        #if os(iOS)
        // Banner ad unit ID via Info.plist `GADBannerUnitID` key, substituted
        // at build time from `Tuist/AdMob.xcconfig` (gitignored; .example
        // committed). XCC writes the xcconfig from per-workflow env vars;
        // local builds use the .example sandbox values. Replaces the old
        // DEBUG-vs-Release fatalError gate with smoke-test (key presence —
        // `AppCompositionTests/InfoPlistAdMobKeysTests`) + runtime guard
        // below (catches missing-key + empty + unresolved-`$()` token
        // before AdMob SDK init).
        guard
            let sudokuBannerAdUnitID = Bundle.main
                .object(forInfoDictionaryKey: "GADBannerUnitID") as? String,
            !sudokuBannerAdUnitID.isEmpty,
            !sudokuBannerAdUnitID.hasPrefix("$(")
        else {
            preconditionFailure(
                "GADBannerUnitID missing or unresolved — check"
                    + " Tuist/AdMob.xcconfig exists locally or that XCC env"
                    + " vars are set for Release builds."
            )
        }
        let adProvider: any AdProvider = LiveAdMobAdProvider(bannerAdUnitID: sudokuBannerAdUnitID)
        #else
        let adProvider: any AdProvider = NoopAdProvider()
        #endif
        // `LiveStoreKit2IAPClient` reports catalog-desync (post-purchase
        // refetch returns empty) through the same Telemetry channel so the
        // M3 placeholder substitution doesn't silently mask a backend issue.
        let iapClient: any IAPClient = LiveStoreKit2IAPClient(
            knownProductIds: [sudokuRemoveAdsProductID],
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

        // v2.3.6: shared @Observable controller for Settings + HomeView's
        // Remove Ads surfaces. Constructed eagerly so both views observe the
        // same instance; `.bootstrap()` is invoked lazily inside each View's
        // `.task` modifier.
        // v2.4.5: shared toast surface. Constructed before the controller so
        // we can inject it; RootView mounts the same instance as a bottom
        // overlay.
        let toastController = ToastController()

        let monetizationController = MonetizationStateController(
            iapClient: iapClient,
            stateStore: monetizationStateStore,
            adGate: adGate,
            toastController: toastController
        )
        // Fix B (RCA 2026-05-25): bootstrap() no longer auto-subscribes
        // to `purchaseUpdates()`. Production opts in here, exactly once,
        // for the lifetime of the app. Tests opt in per-test + tear down
        // via `FakeIAPClient.finishUpdates()`.
        monetizationController.startListeningForLifetimeOfApp()

        let rootViewModel = RootViewModel(
            gameCenter: gameCenter,
            persistence: persistence,
            errorReporter: errorReporter
        )

        // #371 / #195: ATT pre-prompt coordinator. The two ATT touch points are
        // injected here (the only layer that depends on AdsAdMob — SudokuUI must
        // not, per foundations.md §9.1). `ATTPresenter.requestIfNeeded()` is
        // idempotent (only prompts when `.notDetermined`); `currentStatus()`
        // backs the "should we even offer?" check via the public outcome enum.
        // The boot sequence no longer calls ATT — this coordinator owns it,
        // triggered from BannerSlotView when the ad gate opens (post-Home,
        // first ad-relevant moment).
        let attPrimer = ATTPrimerCoordinator(
            isNotDetermined: { await ATTPresenter.currentStatus() == .notDetermined },
            requestSystemPrompt: { _ = await ATTPresenter.requestIfNeeded() }
        )

        // #287 Phase 2: reminder wiring. RemindersKit's Live conformers +
        // `UNUserNotificationCenter` stay confined to this composition layer.
        // `emit` bridges the (non-async) coordinator/delegate callbacks into the
        // `Telemetry` actor's async `observe`.
        let emit: @Sendable (TelemetryEvent) -> Void = { [telemetry] event in
            Task { await telemetry.observe(event) }
        }
        let reminderAuthorizer = LiveNotificationAuthorizer(subsystem: "com.wei18.sudoku")
        let reminderScheduler = LiveReminderScheduler(subsystem: "com.wei18.sudoku")
        let reminderSettingsStore = ReminderSettingsStore()

        // Foreground-presentation + tap routing. A tapped `dailyReady` reminder
        // deep-links to the Daily hub (flow S07→S09). Routing mutates the same
        // `rootViewModel.path` the sidebar uses.
        ReminderDelegateRetainer.install(
            onTap: { identifier in
                if identifier == ReminderKind.dailyReady.rawValue {
                    if rootViewModel.path.last != .daily {
                        rootViewModel.path.append(.daily)
                    }
                }
            },
            emit: emit
        )

        // Shared daily-ready notification payload — used both by the primer
        // (initial schedule) and the #321 Settings time picker (reschedule on
        // change) so re-scheduling never drifts the title/body.
        let dailyReadyContent = ReminderContent(
            title: "Today's Sudoku is ready",
            body: "Your daily puzzle is waiting — keep your streak going."
        )

        // Builds a fresh daily-ready primer coordinator per Daily-completion
        // mount. Copy is passed as `LocalizedStringKey` literals so the app
        // bundle's `Localizable.xcstrings` localizes them (ai-translated-localization
        // sweep adds the non-en locales). Body softened to "default 9 AM,
        // adjustable in Settings" per the persisted-time seam (#321).
        let makeDailyReminderPrimer: @MainActor () -> ReminderPrimerCoordinator = {
            ReminderPrimerCoordinator(
                permissionModel: ReminderPermissionModel(authorizer: reminderAuthorizer),
                scheduler: reminderScheduler,
                settingsStore: reminderSettingsStore,
                content: dailyReadyContent,
                primerCopy: ReminderPrimerCopy(
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
                ),
                deniedCopy: ReminderDeniedCopy(
                    title: "Reminders are off",
                    message: "Notifications are turned off for Sudoku in Settings, so we can't tell you when the Daily is ready.",
                    openSettingsCTA: "Open Settings",
                    dismissCTA: "Not now",
                    macOSGuidance: "Enable notifications in System Settings → Notifications → Sudoku."
                ),
                emit: emit
            )
        }

        // #287: builds the Settings Reminders entry per Settings mount — the
        // shared `ReminderSettingsModel` (enable / prime permission / fire-time)
        // + the Sudoku-localized copy. Reads/writes the SAME `reminderSettingsStore`
        // the post-Daily primer uses (via get/set closures), so a time change here
        // is honored by the next primer schedule and vice-versa. `reminderEmit`
        // bridges the model's decoupled `Event` to the `Telemetry` facade.
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
        let makeReminderSettings: @MainActor () -> ReminderSettingsEntry = {
            let model = ReminderSettingsModel(
                permissionModel: ReminderPermissionModel(authorizer: reminderAuthorizer),
                scheduler: reminderScheduler,
                kind: .dailyReady,
                content: dailyReadyContent,
                getFireTime: {
                    let time = reminderSettingsStore.dailyReadyFireTime
                    return (hour: time.hour, minute: time.minute)
                },
                setFireTime: { time in
                    reminderSettingsStore.dailyReadyFireTime = ReminderFireTime(
                        hour: time.hour,
                        minute: time.minute
                    )
                },
                emit: reminderEmit
            )
            return ReminderSettingsEntry(
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
                    lede: "We'll let you know the moment tomorrow's Daily Sudoku is ready.",
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
                    message: "Notifications are turned off for Sudoku in Settings, so we can't tell you when the Daily is ready.",
                    openSettingsCTA: "Open Settings",
                    dismissCTA: "Not now",
                    macOSGuidance: "Enable notifications in System Settings → Notifications → Sudoku."
                )
            )
        }

        // #331: Notices / 宣告 section config. Acknowledgements live in the
        // LicensePlist-generated `Settings.bundle` (iOS Settings.app → Sudoku →
        // Acknowledgements), so the in-app row deep-links to the app's own iOS
        // Settings page. On macOS there is no such deep-link → omit the row.
        // Privacy-policy / support URLs are not wired yet (no canonical public
        // URL committed to the repo — see meetings/2026-06-09_331-settingskit.md);
        // copyright is derived locally, no fabrication.
        let settingsNotices = makeSettingsNotices()

        let routeFactory = LiveRouteFactory(
            puzzleProvider: puzzleStore,
            persistence: persistence,
            gameCenter: gameCenter,
            telemetry: telemetry,
            errorReporter: errorReporter,
            adProvider: adProvider,
            iapClient: iapClient,
            adGate: adGate,
            monetizationController: monetizationController,
            toastController: toastController,
            makeDailyReminderPrimer: makeDailyReminderPrimer,
            makeReminderSettings: makeReminderSettings,
            settingsNotices: settingsNotices
        )

        return AppComposition(
            rootViewModel: rootViewModel,
            routeFactory: routeFactory,
            puzzleProvider: puzzleStore,
            persistence: persistence,
            gameCenter: gameCenter,
            telemetry: telemetry,
            errorReporter: errorReporter,
            adProvider: adProvider,
            iapClient: iapClient,
            adGate: adGate,
            monetizationStateStore: monetizationStateStore,
            monetizationController: monetizationController,
            toastController: toastController,
            attPrimer: attPrimer
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

/// Process-wide retainer for `MetricKitSink` — MXMetricManager's subscriber
/// list holds a weak reference, so we must keep the sink alive ourselves
/// for the lifetime of the App. Installation is idempotent.
private enum LiveMetricKitRetainer {
    nonisolated(unsafe) private static var sink: MetricKitSink?
    private static let lock = NSLock()

    static func install(downstream: Telemetry) {
        lock.lock()
        defer { lock.unlock() }
        guard sink == nil else { return }
        let metricSink = MetricKitSink(downstream: downstream)
        // Skip system registration in test environments — MXMetricManager
        // is unavailable outside a properly entitled app bundle and would
        // crash the test process. Detection: swift-testing / XCTest sets
        // `XCTestConfigurationFilePath`.
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil {
            metricSink.startReceivingSystemReports()
        }
        sink = metricSink
    }
}
