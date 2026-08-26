// GameConfig — per-game content bag + builder closures for makeGameApp (#556).
//
// SDD-005 Pillar B: `makeGameApp(config:)` wires the entire shared live stack
// (Telemetry + MetricKit + errorReporter + GameCenter + Persistence +
// monetization + audio + ATT + reminders) and then calls the per-game builder
// closures to produce the root view.
//
// `GameDeps` is the wired bag handed to per-game closures so they can build
// their specific route factory, tab roots, and resume mapping without knowing
// the internals of any live seam.
//
// `GameConfig<Route>` carries only the per-game *content* (subsystem, ckConfig,
// removeAdsProductId, theme, etc.) plus the builder closures that produce
// per-game objects from the wired deps.
//
// Dep direction (GameShellKit stays zero-dep; all deps are allowed here):
//   GameAppKit  ←  Persistence · GameCenter · Telemetry · MonetizationUI ·
//                  AdsAdMob · IAPStoreKit2 · GameAudio · SettingsUI · Reminders

internal import Foundation
public import SwiftUI
public import GameCenterClient
public import Persistence
public import Telemetry
public import GameShellUI
public import MonetizationCore
public import MonetizationUI
public import GameAudio
public import SettingsUI
public import Reminders

// MARK: - GameDeps

/// The fully-wired dependency bag produced by `makeGameApp` and handed to the
/// per-game builder closures. All properties are game-agnostic protocol seams or
/// shared coordinators — the concrete live types never cross this boundary.
@MainActor
public struct GameDeps {
    public let telemetry: Telemetry
    public let errorReporter: any ErrorReporter
    public let gameCenter: any GameCenterClient
    public let persistence: any PersistenceProtocol
    public let adProvider: any AdProvider
    public let adGate: AdGate
    public let monetizationStateStore: any AdGateStateStore
    public let iapClient: any IAPClient
    public let monetizationController: MonetizationStateController
    public let toastController: ToastController
    /// Universal audio seam: the wired `LiveSoundPlayer` on live runs, a Noop
    /// or Fake on preview / tests.
    public let soundPlayer: any SoundPlaying
    /// Shared `@Observable` audio settings model; both the Settings screen and
    /// the board views mutate the same instance.
    public let audioSettings: AudioSettingsModel
    /// Universal ATT pre-prompt coordinator. Wired to `ATTPresenter` on live;
    /// callers call `maybePresentOnAdContext()` from the banner gate.
    public let attPrimer: ATTPrimerCoordinator
    /// Builder for the daily-reminder primer coordinator. Called once per
    /// Daily-completion mount; each invocation produces a fresh coordinator
    /// with the same wired authorizer/scheduler/store underneath.
    public let makeDailyReminderPrimer: @MainActor () -> ReminderPrimerCoordinator
    /// The Settings reminders entry, built ONCE at composition time (#909).
    /// A factory closure here previously minted a fresh `ReminderSettingsModel`
    /// (with `isPrimerPresented` reset to `false`) on every invocation — but
    /// the `.settings` case lives inside a `.navigationDestination` builder
    /// closure, which SwiftUI re-invokes on every ancestor re-render, not just
    /// once per Settings mount. A concurrent bootstrap `.task` re-rendering an
    /// ancestor right after the user tapped "Daily reminder" replaced the
    /// just-flipped model with a fresh one, so the primer sheet's binding read
    /// `false` and dismissed itself immediately. A stable, eagerly-built value
    /// guarantees every `.settings` render reuses the same model instance.
    public let reminderSettings: ReminderSettingsEntry

    public init(
        telemetry: Telemetry,
        errorReporter: any ErrorReporter,
        gameCenter: any GameCenterClient,
        persistence: any PersistenceProtocol,
        adProvider: any AdProvider,
        adGate: AdGate,
        monetizationStateStore: any AdGateStateStore,
        iapClient: any IAPClient,
        monetizationController: MonetizationStateController,
        toastController: ToastController,
        soundPlayer: any SoundPlaying,
        audioSettings: AudioSettingsModel,
        attPrimer: ATTPrimerCoordinator,
        makeDailyReminderPrimer: @escaping @MainActor () -> ReminderPrimerCoordinator,
        reminderSettings: ReminderSettingsEntry
    ) {
        self.telemetry = telemetry
        self.errorReporter = errorReporter
        self.gameCenter = gameCenter
        self.persistence = persistence
        self.adProvider = adProvider
        self.adGate = adGate
        self.monetizationStateStore = monetizationStateStore
        self.iapClient = iapClient
        self.monetizationController = monetizationController
        self.toastController = toastController
        self.soundPlayer = soundPlayer
        self.audioSettings = audioSettings
        self.attPrimer = attPrimer
        self.makeDailyReminderPrimer = makeDailyReminderPrimer
        self.reminderSettings = reminderSettings
    }
}

// MARK: - AudioConfig

/// Per-game audio configuration: the UserDefaults key prefix and default values.
/// `makeGameApp` uses this to build `AudioSettingsModel` with the game-scoped keys
/// (so Sudoku and Minesweeper never share a UserDefaults namespace).
public struct AudioConfig: Sendable {
    /// UserDefaults key prefix, e.g. `"com.wei18.sudoku.audio"`. All per-game
    /// audio keys are derived by appending `.musicVolume`, `.sfxVolume`, etc.
    public let keyPrefix: String

    public init(keyPrefix: String) {
        self.keyPrefix = keyPrefix
    }
}

// MARK: - ReminderContentConfig

/// Per-game reminder content: notification payload + primer / denied / settings
/// sheet copy. Carries the SettingsUI / Reminders copy value types directly so
/// `makeGameApp` passes the game's exact `LocalizedStringKey` literals through
/// to the coordinators / sections (byte-identical to each game's prior wiring).
///
/// `@MainActor`-only (not `Sendable`): the copy types hold `LocalizedStringKey`
/// and are only ever read on `@MainActor` inside `makeGameApp`, mirroring the
/// MainActor-only copy types in SettingsUI.
@MainActor
public struct ReminderContentConfig {
    /// Daily-ready notification payload (title / body), used by both the primer
    /// (initial schedule) and the Settings time picker (reschedule).
    public let dailyReadyContent: ReminderContent
    /// Primer sheet copy (shared by the post-Daily primer + Settings section).
    public let primerCopy: ReminderPrimerCopy
    /// Denied-state explainer copy.
    public let deniedCopy: ReminderDeniedCopy
    /// Settings reminders-section copy.
    public let settingsCopy: ReminderSettingsCopy

    public init(
        dailyReadyContent: ReminderContent,
        primerCopy: ReminderPrimerCopy,
        deniedCopy: ReminderDeniedCopy,
        settingsCopy: ReminderSettingsCopy
    ) {
        self.dailyReadyContent = dailyReadyContent
        self.primerCopy = primerCopy
        self.deniedCopy = deniedCopy
        self.settingsCopy = settingsCopy
    }
}

// MARK: - GameConfig

/// Per-game content bag + builder closures for `makeGameApp(config:)`.
///
/// The builder closures receive the wired `GameDeps` bag (and the root VM
/// when needed) after `makeGameApp` has assembled the live stack, so they can
/// build game-specific objects (RouteFactory, Home, SavedGameStore) without
/// knowing any concrete live type.
@MainActor
public struct GameConfig<Route: Hashable & Sendable> {
    // MARK: Values

    /// OSLog subsystem string, e.g. `"com.wei18.sudoku"`.
    public let subsystem: String
    /// CloudKit zone + subscription config. Each game owns its namespace.
    public let ckConfig: PrivateCKConfig
    /// StoreKit 2 product ID for the "Remove Ads" IAP.
    public let removeAdsProductId: String
    /// Puzzle loader closure injected into `LivePersistence`. Games that have
    /// no puzzle concept throw a sentinel error here (see Game2048 pattern).
    public let puzzleLoader: LivePersistence.PuzzleLoader
    /// Game-specific `Theme` value injected via `\.theme` environment key.
    public let theme: any Theme
    /// Success tint forwarded to `GameRoot`'s `.toastOverlay`.
    public let successTint: Color
    /// Failure tint forwarded to `GameRoot`'s `.toastOverlay`.
    public let failureTint: Color
    /// #950: informational (neither success nor failure) tint forwarded to
    /// `GameRoot`'s `.toastOverlay` — e.g. "Restore Purchases" completing
    /// with nothing entitled.
    public let infoTint: Color
    /// Audio configuration: UserDefaults key prefix for this game.
    public let audio: AudioConfig
    /// Reminder content: subsystem + notification copy for this game.
    public let reminders: ReminderContentConfig
    /// #1020: the route each tab's trailing toolbar gear pushes.
    ///
    /// design.md §2.1 / §3.7 put a Settings gear at the top-right of EVERY tab
    /// ("每 tab 右上齒輪") — with HOME retired, its Settings card was the app's
    /// only entry point, so this is now the sole one on iPhone. Required (no
    /// default): every game has a Settings screen, and a game that silently
    /// shipped without the gear would be unreachable, not merely degraded.
    public let settingsRoute: Route

    // MARK: Builder closures

    /// #1020: the per-game root content for each of the three tabs
    /// (`Today` / `Practice` / `Progress`), erased to `AnyView`. Called once per
    /// tab per root mount with the wired deps + root VM, so each game can build
    /// its own daily hub / practice hub / statistics screen without GameAppKit
    /// naming any of them.
    ///
    /// `.today`'s content is additionally wrapped by `TodayTabHost` (resume pill
    /// + banner slot + the C-33 ATT anchor), so a game supplies only the middle
    /// of that sandwich.
    ///
    /// Replaces the retired home-modes / make-home / sidebar-items trio: with
    /// `sidebarAdaptable` generating its own chrome from `AppTab`, there is no
    /// mode-card list or sidebar array left to configure.
    public let makeTabRoot: @MainActor (AppTab, GameDeps, GameRootViewModel<Route>) -> AnyView

    /// Maps from the game's persisted state into a `ResumeCandidate` for the
    /// resume pill. `nil` if the game has no resume surface.
    public let fetchResume: (@MainActor (GameDeps) -> (() async throws -> ResumeCandidate<Route>?)?)?

    /// Builds the per-game `RouteFactory`. Called after `makeGameApp` wires the
    /// `GameDeps` bag so the factory can capture live seams without knowing them.
    public let makeRouteFactory: @MainActor (GameDeps, GameRootViewModel<Route>) -> any RouteFactory<Route>

    /// Deep-link a tapped reminder. The param is the notification identifier
    /// (equals `ReminderKind.rawValue`); the closure routes it on the root VM.
    /// #1020: the daily-ready reminder's landing surface is now a tab identity,
    /// so a game routes it by setting `selectedTab` (and, if needed, that tab's
    /// path) rather than pushing a `.daily` route. `nil` → no tap routing
    /// (default).
    public let reminderTapRoute: (@MainActor (String, GameRootViewModel<Route>) -> Void)?

    /// #579 phase 2: late-bound completion sinks (e.g. GameCenterSink) injected
    /// into the live DeferredSink after rootVM is built. Called once at
    /// composition time from makeGameApp. `nil` → empty downstream (Games that
    /// don't yet use the shared pipeline — MS, 2048 — leave this nil).
    public let makeCompletionSinks: (@MainActor @Sendable (GameDeps, GameRootViewModel<Route>) -> [any TelemetrySink])?

    public init(
        subsystem: String,
        ckConfig: PrivateCKConfig,
        removeAdsProductId: String,
        puzzleLoader: @escaping LivePersistence.PuzzleLoader,
        theme: any Theme,
        successTint: Color,
        failureTint: Color,
        infoTint: Color,
        audio: AudioConfig,
        reminders: ReminderContentConfig,
        settingsRoute: Route,
        makeTabRoot: @escaping @MainActor (AppTab, GameDeps, GameRootViewModel<Route>) -> AnyView,
        fetchResume: (@MainActor (GameDeps) -> (() async throws -> ResumeCandidate<Route>?)?)? = nil,
        makeRouteFactory: @escaping @MainActor (GameDeps, GameRootViewModel<Route>) -> any RouteFactory<Route>,
        reminderTapRoute: (@MainActor (String, GameRootViewModel<Route>) -> Void)? = nil,
        makeCompletionSinks: (@MainActor @Sendable (GameDeps, GameRootViewModel<Route>) -> [any TelemetrySink])? = nil
    ) {
        self.subsystem = subsystem
        self.ckConfig = ckConfig
        self.removeAdsProductId = removeAdsProductId
        self.puzzleLoader = puzzleLoader
        self.theme = theme
        self.successTint = successTint
        self.failureTint = failureTint
        self.infoTint = infoTint
        self.audio = audio
        self.reminders = reminders
        self.settingsRoute = settingsRoute
        self.makeTabRoot = makeTabRoot
        self.fetchResume = fetchResume
        self.makeRouteFactory = makeRouteFactory
        self.reminderTapRoute = reminderTapRoute
        self.makeCompletionSinks = makeCompletionSinks
    }
}
