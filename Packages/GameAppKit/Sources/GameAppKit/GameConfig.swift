// GameConfig — per-game content bag + builder closures for makeGameApp (#556).
//
// SDD-005 Pillar B: `makeGameApp(config:)` wires the entire shared live stack
// (Telemetry + MetricKit + errorReporter + GameCenter + Persistence +
// monetization + audio + ATT + reminders) and then calls the per-game builder
// closures to produce the root view.
//
// `GameDeps` is the wired bag handed to per-game closures so they can build
// their specific route factory, home view, and resume mapping without knowing
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
    /// Builder for the Settings reminders entry. Called once per Settings mount.
    public let makeReminderSettings: @MainActor () -> ReminderSettingsEntry

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
        makeReminderSettings: @escaping @MainActor () -> ReminderSettingsEntry
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
        self.makeReminderSettings = makeReminderSettings
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

// MARK: - HomeModeContent

/// Per-game content for one `HomeMode` card in `GameHomeView`.
///
/// `subtitleKey` resolves from `Bundle.main` (the app's own catalog), exactly
/// as the prior per-game `HomeViewModel.subtitleKey` private extensions did.
/// `route` is the navigation push for Daily / Practice / Settings; `nil` means
/// the mode produces a side-effect rather than a push (Leaderboard → GC
/// dashboard), so `GameHomeViewModel.select(_:)` handles it specially.
public struct HomeModeContent<Route: Hashable & Sendable> {
    /// App-specific subtitle shown below the mode title on the Home card.
    public let subtitleKey: LocalizedStringKey
    /// Navigation push for this mode, or `nil` for the leaderboard side-effect.
    public let route: Route?

    public init(subtitleKey: LocalizedStringKey, route: Route? = nil) {
        self.subtitleKey = subtitleKey
        self.route = route
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
    /// Navigation bar / window title.
    public let title: LocalizedStringKey
    /// Sidebar / tab items for `RootShellView`.
    public let sidebarItems: [SidebarItem<Route>]
    /// Success tint forwarded to `GameRoot`'s `.toastOverlay`.
    public let successTint: Color
    /// Failure tint forwarded to `GameRoot`'s `.toastOverlay`.
    public let failureTint: Color
    /// Audio configuration: UserDefaults key prefix for this game.
    public let audio: AudioConfig
    /// Reminder content: subsystem + notification copy for this game.
    public let reminders: ReminderContentConfig
    /// Optional `SettingsNoticesConfig` — wired by each game's composition root
    /// (some games may not have a Notices section yet).
    public let settingsNotices: SettingsNoticesConfig?
    /// Per-mode home card content: subtitle copy + navigation route (or nil for
    /// leaderboard side-effect). `GameHomeView` builds its `HomeModeItem` array
    /// from this map. Missing modes fall back to an empty subtitle and no route.
    public let homeModes: [HomeMode: HomeModeContent<Route>]
    /// Presents the game's native Game Center leaderboard UI. Called by
    /// `GameHomeViewModel.select(.leaderboard)` when GC is authenticated. Each
    /// game supplies its own `GameCenterDashboard.present()` implementation since
    /// the GK controller is not shared. `nil` → no-op (games without a leaderboard
    /// surface, or during migration).
    public let presentLeaderboard: (@MainActor () -> Void)?

    // MARK: Builder closures

    /// Maps from the game's persisted state into a `ResumeCandidate` for the
    /// resume pill. `nil` if the game has no resume surface.
    public let fetchResume: (@MainActor (GameDeps) -> (() async throws -> ResumeCandidate<Route>?)?)?

    /// Builds the per-game `RouteFactory`. Called after `makeGameApp` wires the
    /// `GameDeps` bag so the factory can capture live seams without knowing them.
    public let makeRouteFactory: @MainActor (GameDeps, GameRootViewModel<Route>) -> any RouteFactory<Route>

    /// Builds the per-game home view, wrapped as `AnyView` for type erasure.
    /// Called once per root mount; captures the wired deps + rootVM.
    /// Superseded by the universal `GameHomeView` built from `homeModes` in
    /// `makeGameApp` (#557). Retained for API compatibility during migration of
    /// MS and 2048; `makeGameApp` ignores this once `homeModes` is non-empty.
    public let makeHome: @MainActor (GameDeps, GameRootViewModel<Route>) -> AnyView

    /// Deep-link a tapped reminder. The param is the notification identifier
    /// (equals `ReminderKind.rawValue`); the closure routes it on the root VM
    /// (e.g. Sudoku pushes `.daily`). `nil` → no tap routing (default).
    public let reminderTapRoute: (@MainActor (String, GameRootViewModel<Route>) -> Void)?

    public init(
        subsystem: String,
        ckConfig: PrivateCKConfig,
        removeAdsProductId: String,
        puzzleLoader: @escaping LivePersistence.PuzzleLoader,
        theme: any Theme,
        title: LocalizedStringKey,
        sidebarItems: [SidebarItem<Route>],
        successTint: Color,
        failureTint: Color,
        audio: AudioConfig,
        reminders: ReminderContentConfig,
        settingsNotices: SettingsNoticesConfig? = nil,
        homeModes: [HomeMode: HomeModeContent<Route>] = [:],
        presentLeaderboard: (@MainActor () -> Void)? = nil,
        fetchResume: (@MainActor (GameDeps) -> (() async throws -> ResumeCandidate<Route>?)?)? = nil,
        makeRouteFactory: @escaping @MainActor (GameDeps, GameRootViewModel<Route>) -> any RouteFactory<Route>,
        makeHome: @escaping @MainActor (GameDeps, GameRootViewModel<Route>) -> AnyView,
        reminderTapRoute: (@MainActor (String, GameRootViewModel<Route>) -> Void)? = nil
    ) {
        self.subsystem = subsystem
        self.ckConfig = ckConfig
        self.removeAdsProductId = removeAdsProductId
        self.puzzleLoader = puzzleLoader
        self.theme = theme
        self.title = title
        self.sidebarItems = sidebarItems
        self.successTint = successTint
        self.failureTint = failureTint
        self.audio = audio
        self.reminders = reminders
        self.settingsNotices = settingsNotices
        self.homeModes = homeModes
        self.presentLeaderboard = presentLeaderboard
        self.fetchResume = fetchResume
        self.makeRouteFactory = makeRouteFactory
        self.makeHome = makeHome
        self.reminderTapRoute = reminderTapRoute
    }
}
