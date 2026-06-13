// LiveRouteFactory — Sudoku's concrete `RouteFactory` (PR X2 split, 2026-06-01):
// the game-agnostic protocol moved to `GameShellKit/Sources/GameShellUI/RouteFactory.swift`.
// This file holds the Sudoku-specific implementation and its destination
// wiring; the protocol's `associatedtype Route` is bound to `AppRoute` here.
//
// Why the protocol seam exists: every time the App gained a new top-level
// dependency (Telemetry, PuzzleProvider, then v2's AdProvider / IAPClient /
// AdGate) the `RootView` constructor grew another parameter — by v2.3.2's
// interim wiring it would have reached 8 deps. The factory absorbs all of
// those into a single object, so `RootView.init` stays at two arguments
// (viewModel + routeFactory) regardless of how many collaborators the
// destination views ultimately need.

public import SwiftUI
public import MonetizationCore
public import MonetizationUI
public import GameCenterClient
public import Persistence
public import PuzzleStore
internal import SudokuEngine
public import Telemetry
public import GameShellUI
// refactor/settingskit-target: `SettingsNoticesConfig` moved out of GameShellUI
// into SettingsUI; it appears in `LiveRouteFactory.init`'s public signature.
public import SettingsUI
// #330 P2: the `SoundPlaying` seam (injected into the gameplay VM) +
// `AudioSettingsModel` (injected into Settings) both appear in this factory's
// public init signature. The seam only — no `AVFoundation`.
public import GameAudio
// SDD-003 Epic 1: `GameBoardRedirect` wraps board-route destinations when
// `onPresentBoard` is wired, so board views are presented as fullScreenCover
// modals instead of NavigationStack pushes.
public import GameAppKit

// MARK: - LiveRouteFactory

/// Production `RouteFactory`. Holds all protocol deps the destination Views
/// need; `view(for:)` switches over `AppRoute` and returns the matching
/// pre-configured `View + ViewModel` pair wrapped in `AnyView`.
public struct LiveRouteFactory: RouteFactory {
    private let puzzleProvider: any PuzzleProviderProtocol
    private let persistence: any PersistenceProtocol
    private let gameCenter: any GameCenterClient
    private let telemetry: Telemetry
    // M10 (issue #67): unified error funnel passed into VMs / loader views
    // that previously `try?`-swallowed CloudKit / Persistence errors.
    private let errorReporter: any ErrorReporter
    // v2 monetization deps. Currently consumed by destination views landing
    // in v2.3.4-6 (HomeView banner, BoardView banner, Settings IAP rows).
    // Stored here now so RootView's signature does not have to grow.
    private let adProvider: any AdProvider
    private let iapClient: any IAPClient
    private let adGate: AdGate
    // v2.3.6: optional so existing callers (route factory tests, snapshot
    // fixtures) keep working without constructing a controller. Live wiring
    // injects one so Settings renders the Remove Ads section.
    private let monetizationController: MonetizationStateController?
    // v2.4.6: optional toast surface forwarded to `SettingsViewModel` so the
    // clear-cache success can route through the same overlay as IAP results.
    private let toastController: ToastController?
    // #287 Phase 2: builds a fresh daily-ready primer coordinator for a Daily
    // completion mount. Injected as a closure (not the raw Reminders seams) so
    // ALL reminder wiring — Live conformers, copy, telemetry bridge — stays in
    // AppComposition; the factory only decides WHEN (Daily, not Practice). `nil`
    // in previews / tests → no primer, byte-identical Completion screens.
    private let makeDailyReminderPrimer: (@MainActor () -> ReminderPrimerCoordinator)?
    // #287: builds the Settings Reminders entry (shared `ReminderSettingsModel` +
    // Sudoku copy) per Settings mount. Injected as a closure (not the raw
    // Reminders seams) so ALL reminder wiring stays in AppComposition. `nil` in
    // previews / tests → no reminder section, byte-identical Settings screen.
    private let makeReminderSettings: (@MainActor () -> ReminderSettingsEntry)?
    // #331: app-injected Notices section config (acknowledgements deep-link,
    // copyright, optional privacy/support URLs). `nil` in previews / tests →
    // no Notices section, byte-identical Settings screen.
    private let settingsNotices: SettingsNoticesConfig?
    // #330 P2: the gameplay audio player, forwarded to `BoardLoaderView` →
    // `GameViewModel` so placements / mistakes / section-clears / wins fire
    // their cues. Defaults to `NoopSoundPlaying` so previews / tests stay silent.
    private let soundPlayer: any SoundPlaying
    // #330 P2: the Settings audio entry (volumes / mute / music / haptics).
    // `nil` in previews / tests → no audio section, byte-identical Settings.
    private let audioSettings: AudioSettingsModel?
    // SDD-003 Epic 1: closure that modal-presents a board route via
    // `GameRootViewModel.presentGame(route:)`. When non-nil, board routes
    // (`AppRoute.board`) return a `GameBoardRedirect` that pops the push entry
    // and fires this closure instead of building a `BoardLoaderView` inline.
    // `nil` (default) preserves the legacy push-navigation behavior for tests
    // and previews that don't wire a Root VM.
    private let onPresentBoard: (@MainActor (AppRoute) -> Void)?

    public init(
        puzzleProvider: any PuzzleProviderProtocol,
        persistence: any PersistenceProtocol,
        gameCenter: any GameCenterClient,
        telemetry: Telemetry,
        errorReporter: any ErrorReporter = NoopErrorReporter(),
        adProvider: any AdProvider,
        iapClient: any IAPClient,
        adGate: AdGate,
        monetizationController: MonetizationStateController? = nil,
        toastController: ToastController? = nil,
        makeDailyReminderPrimer: (@MainActor () -> ReminderPrimerCoordinator)? = nil,
        makeReminderSettings: (@MainActor () -> ReminderSettingsEntry)? = nil,
        settingsNotices: SettingsNoticesConfig? = nil,
        soundPlayer: any SoundPlaying = NoopSoundPlaying(),
        audioSettings: AudioSettingsModel? = nil,
        onPresentBoard: (@MainActor (AppRoute) -> Void)? = nil
    ) {
        self.puzzleProvider = puzzleProvider
        self.persistence = persistence
        self.gameCenter = gameCenter
        self.telemetry = telemetry
        self.errorReporter = errorReporter
        self.adProvider = adProvider
        self.iapClient = iapClient
        self.adGate = adGate
        self.monetizationController = monetizationController
        self.toastController = toastController
        self.makeDailyReminderPrimer = makeDailyReminderPrimer
        self.makeReminderSettings = makeReminderSettings
        self.settingsNotices = settingsNotices
        self.soundPlayer = soundPlayer
        self.audioSettings = audioSettings
        self.onPresentBoard = onPresentBoard
    }

    /// A puzzleId is a Daily unless it carries the practice prefix — same
    /// encoding `BoardLoaderView.identity(from:)` relies on. The reminder primer
    /// is offered only after a Daily solve (proposal §5.1; flow S02).
    private static func isDaily(puzzleId: String) -> Bool {
        !puzzleId.hasPrefix("practice-")
    }

    /// Leaderboard id this `puzzleId` submits to, or `nil` when it has none.
    /// Issue #381: the Completion screen must post to the board matching the
    /// solved difficulty, not always daily-easy. Practice puzzles have no
    /// leaderboard (`LeaderboardKind` has no practice case) → `nil`.
    ///
    /// Mirrors `PuzzleIdentity`'s encoding: every id ends with the
    /// `Difficulty.rawValue` suffix (`-easy` / `-medium` / `-hard`); Daily ids
    /// have no `practice-` prefix. Only Daily ids resolve to a board.
    static func leaderboardId(forPuzzleId puzzleId: String) -> String? {
        guard isDaily(puzzleId: puzzleId) else { return nil }
        let kind: LeaderboardKind
        switch puzzleId {
        case let id where id.hasSuffix("-\(Difficulty.easy.rawValue)"):
            kind = .dailyEasy
        case let id where id.hasSuffix("-\(Difficulty.medium.rawValue)"):
            kind = .dailyMedium
        case let id where id.hasSuffix("-\(Difficulty.hard.rawValue)"):
            kind = .dailyHard
        default:
            return nil
        }
        return LeaderboardIDs.id(for: kind)
    }

    @MainActor
    public func view(for route: AppRoute, path: Binding<[AppRoute]>?) -> AnyView {
        switch route {
        case .home:
            // `.home` is never pushed (root content renders HomeView). Keep
            // the switch exhaustive without forcing destination views to model
            // the un-pushable case.
            return AnyView(EmptyView())
        case .daily:
            return AnyView(
                DailyHubView(
                    viewModel: DailyHubViewModel(
                        provider: puzzleProvider,
                        persistence: persistence,
                        errorReporter: errorReporter,
                        path: path
                    ),
                    banner: { themedBanner() }
                )
            )
        case .practice:
            return AnyView(
                PracticeHubView(
                    viewModel: PracticeHubViewModel(provider: puzzleProvider, path: path),
                    banner: { themedBanner() }
                )
            )
        case .board:
            // SDD-003 Epic 1 / #491: two-context contract for board routes:
            //   push context  (path != nil): return `GameBoardRedirect`, which pops the
            //     push entry and fires `onPresentBoard` → fullScreenCover modal.
            //   modal context (path == nil): GameRoot calls `view(for:path:nil)` to
            //     build the modal content; the redirect must NOT fire here or the
            //     modal renders Color.clear (blank screen). Fall through to the real
            //     board view.
            // Legacy push path (onPresentBoard == nil) is kept for tests / previews.
            if let onPresentBoard, path != nil {
                return AnyView(
                    GameBoardRedirect(
                        route: route,
                        path: path,
                        onPresent: onPresentBoard
                    )
                )
            }
            guard case .board(let puzzleId) = route else { return AnyView(EmptyView()) }
            return AnyView(
                BoardLoaderView(
                    puzzleId: puzzleId,
                    puzzleProvider: puzzleProvider,
                    persistence: persistence,
                    errorReporter: errorReporter,
                    adProvider: adProvider,
                    adGate: adGate,
                    soundPlayer: soundPlayer,
                    path: path
                )
            )
        case .completion(let puzzleId, let elapsedSeconds, let mistakeCount):
            // #287 Phase 2: offer the daily-ready primer ONLY on a Daily solve
            // (flow S02). Practice solves pass `reminderPrimer: nil` → no change.
            let reminderPrimer = Self.isDaily(puzzleId: puzzleId)
                ? makeDailyReminderPrimer?()
                : nil
            // SDD-003 Epic 4: Close pops the last route entry so the player
            // returns to the board (which is already dismissed) or the Hub.
            let closePath = path
            return AnyView(
                CompletionView(
                    viewModel: CompletionViewModel(
                        puzzleId: puzzleId,
                        elapsedSeconds: elapsedSeconds,
                        mistakeCount: mistakeCount,
                        leaderboardId: Self.leaderboardId(forPuzzleId: puzzleId),
                        gameCenter: gameCenter
                    ),
                    reminderPrimer: reminderPrimer,
                    onClose: closePath.map { pathBinding in { pathBinding.wrappedValue.removeLast() } }
                )
            )
        case .settings:
            return AnyView(
                SettingsView(
                    viewModel: SettingsViewModel(
                        persistence: persistence,
                        errorReporter: errorReporter,
                        toastController: toastController
                    ),
                    monetizationController: monetizationController,
                    reminderSettings: makeReminderSettings?(),
                    notices: settingsNotices,
                    audioSettings: audioSettings,
                    banner: { themedBanner() }
                )
            )
        }
    }

    // MARK: - Banner helper

    /// Epic 5: themed `BannerSlotView` for all non-Home, non-Board screens.
    /// Same theme tokens as HomeView's `bannerSlot` — no per-screen override.
    /// Board never calls this; it owns its own `themedBanner` method.
    /// The cast from `AdProvider` → `BannerViewProviding` follows the same
    /// pattern as HomeView and BoardView (§9.1: keeps SudokuUI off AdsAdMob).
    @MainActor
    private func themedBanner() -> some View {
        BannerSlotView(
            adProvider: adProvider,
            adGate: adGate,
            bannerHost: adProvider as? any BannerViewProviding,
            backgroundColor: Color.secondary.opacity(0.12),
            progressTint: .accentColor,
            captionColor: .secondary,
            dismissTint: Color.secondary.opacity(0.7)
        )
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}
