// MakeGameApp — shared composition entry point for all games (#556 SDD-005 B).
//
// `makeGameApp(config:)` wires the entire game-agnostic live stack and returns
// a ready-to-mount SwiftUI `View`. The per-game details (Route, routeFactory,
// per-tab root content, savedGameStore, copy) arrive as closures on the
// `GameConfig`.
//
// Wires (in order):
//   1. Telemetry (OSLog + NoOpTracking) + MetricKit retainer
//   2. LiveErrorReporter
//   3. LiveGameCenterClient
//   4. LivePersistence (ckConfig + puzzleLoader from config)
//   5. Monetization stack: monetizationStateStore + AdGate + adProvider +
//      LiveStoreKit2IAPClient + ToastController + MonetizationStateController
//   6. Audio stack: LiveAudioSession + LiveSoundPlayer + LiveHaptics +
//      AudioSettingsModel (keyed under config.audio.keyPrefix)
//   7. ATTPrimerCoordinator (wired to ATTPresenter)
//   8. Reminder builders: LiveNotificationAuthorizer + LiveReminderScheduler +
//      ReminderSettingsStore + ReminderDelegateRetainer + builder closures
//   9. GameDeps assembled from all of the above
//   10. rootVM + routeFactory + GameRoot returned as a View
//
// GameShellUI stays zero-dep. GoogleMobileAds stays encapsulated behind
// AdsAdMob's live bridge. CKContainer stays lazy (PrivateCKGatewayFactory).

internal import Foundation
public import SwiftUI
internal import Telemetry
internal import GameCenterClient
internal import Persistence
public import GameShellUI
internal import MonetizationCore
internal import MonetizationUI
internal import AdsAdMob
internal import GameAudio
internal import SettingsUI
internal import Reminders

// MARK: - makeGameApp

/// Wires the full shared live stack for any game and returns a root `View`.
///
/// Call from `SudokuAppComposition.live()` (or any thin game-side shell):
/// build a `GameConfig<Route>` carrying per-game values and builder closures,
/// then pass it here. The returned view is ready to mount in `WindowGroup`.
@MainActor
public func makeGameApp<Route: Hashable & Sendable>(
    config: GameConfig<Route>
) -> AnyView {
    makeGameAppCore(config: config).view
}

// MARK: - makeGameAppWithDeps

/// Same as `makeGameApp(config:)` but also returns the wired `GameDeps` bag,
/// the `GameRootViewModel`, and the route factory. Use this from composition
/// roots that expose deps for test inspection (e.g. `SudokuAppComposition.live()`).
/// The view is `AnyView`-erased because the concrete type closes over deps.
@MainActor
public func makeGameAppWithDeps<Route: Hashable & Sendable>(
    config: GameConfig<Route>
) -> GameAppHandle<Route> {
    makeGameAppCore(config: config)
}

// MARK: - GameAppHandle

/// The wired result of `makeGameAppWithDeps`: the mounted root view plus the
/// `GameDeps` bag, root VM, and route factory a composition root re-exposes.
@MainActor
public struct GameAppHandle<Route: Hashable & Sendable> {
    public let view: AnyView
    public let deps: GameDeps
    public let rootViewModel: GameRootViewModel<Route>
    public let routeFactory: any RouteFactory<Route>
}

// MARK: - makeGameAppCore (internal)

@MainActor
private func makeGameAppCore<Route: Hashable & Sendable>(
    config: GameConfig<Route>
) -> GameAppHandle<Route> {
    // 1. Telemetry fan-out: OSLog + NoOp tracking + DeferredSink for late-bound
    //    completion sinks (e.g. GameCenterSink — #579 phase 2). MetricKit
    //    projects its diagnostic payloads BACK INTO this same Telemetry
    //    instance via the process-wide retained sink below.
    let completionSink = DeferredSink()
    let telemetry = Telemetry(sinks: [
        OSLogSink(subsystem: config.subsystem, category: "Telemetry"),
        NoopTrackingSink(),
        completionSink
    ])
    LiveMetricKitRetainer.install(downstream: telemetry)

    // 2. Unified error funnel. All VM / loader catch sites that previously
    //    `try?`-swallowed errors now route through this reporter.
    let errorReporter: any ErrorReporter = LiveErrorReporter(telemetry: telemetry)

    // 3. Game Center client. #580 live seams; #935 batch 4 uitest fake gate.
    let gameCenter: any GameCenterClient = resolveGameCenterClient(makeLive: LiveGameCenterClient(
        authDriver: GKAuthDriver(errorReporter: errorReporter),
        submitScoreHook: GKScoreSubmitter.live,
        reportAchievementHook: GKAchievementReporter.live
    ))

    // 4. Persistence. The puzzle loader closure routes through the game's own
    //    PuzzleStore (or throws a sentinel for games with no puzzle concept).
    let livePersistence = LivePersistence(
        telemetry: telemetry,
        ckConfig: config.ckConfig,
        puzzleLoader: config.puzzleLoader
    )
    // #935 batch 5: uitest-arg-gated fake swap (clear-cache failure, N19).
    let persistence: any PersistenceProtocol = resolvePersistence(fallback: livePersistence)

    // 5. Monetization stack.
    let monetizationStateStore = livePersistence.monetizationStateStore()

    // #931: uitest-arg-gated fake swap, see MakeGameApp+UITestOverrides.swift.
    let adGateStore = resolveAdGateStore(fallback: monetizationStateStore)

    let adGate = AdGate(
        store: adGateStore,
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

    // AdMob SDK ships iOS-only binaries; macOS wires the NoopAdProvider.
    // Banner ad unit ID comes from Info.plist `GADBannerUnitID`, substituted
    // at build time from xcconfig (build-time-secret-injection skill).
    // `resolveAdProvider` (#931) only invokes this when the fake arg is absent.
    let adProvider: any AdProvider = resolveAdProvider {
        #if os(iOS)
        guard
            let bannerAdUnitID = Bundle.main
                .object(forInfoDictionaryKey: "GADBannerUnitID") as? String,
            !bannerAdUnitID.isEmpty,
            !bannerAdUnitID.hasPrefix("$(")
        else {
            preconditionFailure(
                "GADBannerUnitID missing or unresolved — check"
                    + " Tuist/AdMob.xcconfig exists locally or that XCC env"
                    + " vars are set for Release builds."
            )
        }
        return LiveAdMobAdProvider(bannerAdUnitID: bannerAdUnitID)
        #else
        return NoopAdProvider()
        #endif
    }

    // #935 batch 5: uitest-arg-gated fake swap, see MakeGameApp+Helpers.swift
    // / MakeGameApp+UITestOverrides.swift.
    let iapClient: any IAPClient = makeIAPClient(
        removeAdsProductId: config.removeAdsProductId,
        telemetry: telemetry
    )

    let toastController = ToastController()

    let monetizationController = MonetizationStateController(
        iapClient: iapClient,
        stateStore: monetizationStateStore,
        adGate: adGate,
        toastController: toastController,
        productId: config.removeAdsProductId
    )
    monetizationController.startListeningForLifetimeOfApp()

    // 6. Audio stack. LiveAudioSession configured for ambient mix-with-others;
    //    LiveSoundPlayer wraps it + the haptics seam. Settings model seeds the
    //    running player from persisted UserDefaults values on first construction.
    let audioSession = LiveAudioSession(subsystem: config.subsystem)
    audioSession.configureAmbient()
    let soundPlayer = LiveSoundPlayer(
        session: audioSession,
        haptics: LiveHaptics(),
        subsystem: config.subsystem
    )
    let audioSettings = makeAudioSettings(
        player: soundPlayer,
        keyPrefix: config.audio.keyPrefix
    )
    soundPlayer.setSFXVolume(Float(audioSettings.sfxVolume))
    soundPlayer.setMusicVolume(Float(audioSettings.musicVolume))
    soundPlayer.setMuted(audioSettings.isMuted)
    soundPlayer.setMusicEnabled(audioSettings.musicEnabled)
    soundPlayer.setHapticsEnabled(audioSettings.hapticsEnabled)

    // 7. ATT pre-prompt coordinator (#935 batch 5: uitest-arg-gated fake
    //    swap, see MakeGameApp+Helpers.swift / +UITestOverrides.swift).
    let attPrimer = makeATTPrimerCoordinator()

    // 8. Reminder wiring.
    let emit: @Sendable (TelemetryEvent) -> Void = { [telemetry] event in
        Task { await telemetry.observe(event) }
    }
    // #931: uitest-arg-gated fake swap, see MakeGameApp+UITestOverrides.swift.
    // `reminderScheduler` is never faked.
    let reminderAuthorizer = resolveReminderAuthorizer(
        fallback: LiveNotificationAuthorizer(subsystem: config.subsystem)
    )
    let reminderScheduler = LiveReminderScheduler(subsystem: config.subsystem)

    // Persisted daily-ready fire time + isScheduled flag. See
    // `ReminderPersistence` (MakeGameApp+Helpers.swift) for key shape + defaults.
    let reminderPersistence = makeReminderPersistence(subsystem: config.subsystem)
    let getFireTime = reminderPersistence.getFireTime
    let setFireTime = reminderPersistence.setFireTime
    let getIsScheduled = reminderPersistence.getIsScheduled
    let setIsScheduled = reminderPersistence.setIsScheduled

    let dailyReadyContent = config.reminders.dailyReadyContent

    // 9. Assemble GameDeps (minus rootVM — closures receive it separately).
    //    reminder builder closures capture the shared seams constructed above.
    let primerCopy = config.reminders.primerCopy
    let deniedCopy = config.reminders.deniedCopy

    let makeDailyReminderPrimer: @MainActor () -> ReminderPrimerCoordinator = {
        ReminderPrimerCoordinator(
            permissionModel: ReminderPermissionModel(authorizer: reminderAuthorizer),
            scheduler: reminderScheduler,
            getFireTime: getFireTime,
            content: dailyReadyContent,
            primerCopy: primerCopy,
            deniedCopy: deniedCopy,
            emit: emit
        )
    }

    let reminderEmit: @Sendable (ReminderSettingsModel.Event) -> Void = { [telemetry] event in
        let telemetryEvent: TelemetryEvent?
        switch event {
        case let .scheduled(kind): telemetryEvent = .reminderScheduled(kind: kind)
        case let .primerAccepted(kind): telemetryEvent = .reminderPrimerAccepted(kind: kind)
        case let .primerDeclined(kind): telemetryEvent = .reminderPrimerDeclined(kind: kind)
        case let .cancelled(kind): telemetryEvent = .reminderCancelled(kind: kind)
        }
        guard let telemetryEvent else { return }
        Task { await telemetry.observe(telemetryEvent) }
    }

    let settingsCopy = config.reminders.settingsCopy
    // #909: built ONCE (not a per-render factory closure) so every
    // `.settings` destination render — including the ones SwiftUI triggers by
    // re-invoking the `.navigationDestination` builder on an unrelated
    // ancestor re-render, not just the initial Settings mount — reuses the
    // SAME `ReminderSettingsModel` instance. See `GameConfig.reminderSettings`
    // doc for the dismiss-on-first-tap bug this fixes.
    let reminderSettings = ReminderSettingsEntry(
        model: ReminderSettingsModel(
            permissionModel: ReminderPermissionModel(authorizer: reminderAuthorizer),
            scheduler: reminderScheduler,
            kind: .dailyReady,
            content: dailyReadyContent,
            getFireTime: getFireTime,
            setFireTime: { time in setFireTime(time.hour, time.minute) },
            getIsScheduled: getIsScheduled,
            setIsScheduled: setIsScheduled,
            emit: reminderEmit
        ),
        copy: settingsCopy,
        primerCopy: primerCopy,
        deniedCopy: deniedCopy
    )

    let deps = GameDeps(
        telemetry: telemetry,
        errorReporter: errorReporter,
        gameCenter: gameCenter,
        persistence: persistence,
        adProvider: adProvider,
        adGate: adGate,
        monetizationStateStore: monetizationStateStore,
        iapClient: iapClient,
        monetizationController: monetizationController,
        toastController: toastController,
        soundPlayer: soundPlayer,
        audioSettings: audioSettings,
        attPrimer: attPrimer,
        makeDailyReminderPrimer: makeDailyReminderPrimer,
        reminderSettings: reminderSettings
    )

    // 10. RootVM + route factory + root view.
    let fetchResumeClosure: (() async throws -> ResumeCandidate<Route>?)? = config.fetchResume?(deps)
    let rootViewModel = GameRootViewModel<Route>(
        gameCenter: gameCenter,
        persistence: persistence,
        errorReporter: errorReporter,
        fetchResume: fetchResumeClosure
    )

    // #579 phase 2: late-bind real completion sinks into the DeferredSink now
    // that rootVM is available (the GameCenterSink authStateProvider reads it).
    // Empty downstream when the game does not supply makeCompletionSinks (MS/2048).
    completionSink.setDownstream(config.makeCompletionSinks?(deps, rootViewModel) ?? [])

    // Install the reminder delegate after rootVM exists (tap routing mutates
    // rootVM navigation state). The `onTap` closure captures rootVM by reference (stable
    // @Observable identity) and forwards to the per-game `reminderTapRoute`
    // closure. The delegate stays alive for the process lifetime via the
    // retainer's static storage. `nil` reminderTapRoute → no-op (games with no
    // reminder deep-link).
    GameReminderDelegateRetainer.install(
        onTap: { [rootViewModel] identifier in
            config.reminderTapRoute?(identifier, rootViewModel)
        },
        emit: emit
    )

    let routeFactory = config.makeRouteFactory(deps, rootViewModel)

    // #1020: per-tab root content. The game builds each tab's screen; the Today
    // tab is additionally wrapped in the shared `TodayTabHost`, which carries
    // the resume pill, the themed banner slot, and — riding that slot's first
    // load — the ATT primer anchor (C-33, re-anchored from the retired
    // HOME view's banner slot). The other two tabs get the game's content
    // unwrapped.
    //
    // `chromedTabRoots` runs this builder exactly ONCE per tab, at composition
    // time, then attaches the shared Settings gear to every tab root (§2.1 /
    // §3.7 — with HOME retired this is the app's only Settings entry point).
    // `RootShellView` calls the returned closure on every body evaluation, so
    // building lazily here would re-run `config.makeTabRoot` per render and
    // rebuild the game's hub view models under the player — the #918 bug shape.
    // See the helpers' docs for the full contract.
    let tabRoot = chromedTabRoots(
        rootViewModel: rootViewModel,
        settingsRoute: config.settingsRoute
    ) { tab in
        let content = config.makeTabRoot(tab, deps, rootViewModel)
        guard tab == .today else { return content }
        return AnyView(
            TodayTabHost(
                rootViewModel: rootViewModel,
                adProvider: adProvider,
                adGate: adGate,
                attPrimer: attPrimer,
                content: { content }
            )
        )
    }

    let gameRoot = GameRoot(
        viewModel: rootViewModel,
        routeFactory: routeFactory,
        toastController: toastController,
        successTint: config.successTint,
        failureTint: config.failureTint,
        infoTint: config.infoTint,
        tabRoot: tabRoot
    )
    .environment(\.theme, config.theme)
    // v2.3.7 boot sequence: UMP consent → AdMob SDK init, concurrent with
    // first-frame rendering. `.onAppear { Task { … } }` not `.task { … }`: this is
    // an app-root composition bootstrap, the position where the #361 Xcode 26 `.task`
    // lowering linked an opaque descriptor undefined in the arm64 device Release
    // archive. (Scoped to the app-root, NOT a blanket `.task` ban — leaf-view
    // one-shot `.task` verifies link-clean; see #607.) #361
    .onAppear { Task {
        await bootMonetization(adProvider: adProvider, telemetry: telemetry)
    } }

    // #557: universal theme-tinted ATT primer sheet applied on the returned
    // GameRoot view. Extracted to `MakeGameApp+Modifiers.swift` to keep this
    // file under the 400-line ceiling. #685: the GC-signed-out alert moved
    // into `GameRoot.body` itself (see that file's header for why).
    let view = gameRoot.universalRootModifiers(
        theme: config.theme,
        attPrimer: attPrimer
    )

    return GameAppHandle(
        view: AnyView(view),
        deps: deps,
        rootViewModel: rootViewModel,
        routeFactory: routeFactory
    )
}
