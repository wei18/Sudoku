// LiveRouteFactory — Sudoku's concrete `RouteFactory` (PR X2 split, 2026-06-01):
// the game-agnostic protocol moved to `GameShellKit/Sources/GameShellUI/RouteFactory.swift`.
// This file holds the Sudoku-specific implementation and its destination
// wiring; the protocol's `associatedtype Route` is bound to `AppRoute` here.
//
// #639 (SDD-006 §2): relocated from `SudokuUI/Navigation/RouteFactory.swift` into
// SudokuAppComposition so the factory lives in the composition module, matching
// the 2048/MS canonical shape (UI module stays composition-free). The Daily /
// leaderboard-id statics it used to host moved to `SudokuLeaderboardRouting` in
// SudokuUI (the module SudokuUI's board completion also needs them), so this
// file no longer creates a UI→composition cycle.
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
public import SudokuPersistence
public import Telemetry
public import GameShellUI
// #639: the factory now lives in SudokuAppComposition, so it imports SudokuUI
// for the destination views / view models / `AppRoute` (in the public init +
// `view(for:)` signature) + `SudokuLeaderboardRouting`. SudokuAppComposition → UI is
// the correct (one-way) dependency direction.
public import SudokuUI
// refactor/settingskit-target: `SettingsNoticesConfig` moved out of GameShellUI
// into SettingsUI; it appears in `LiveRouteFactory.init`'s public signature.
public import SettingsUI
// #330 P2: the `SoundPlaying` seam (injected into the gameplay VM) +
// `AudioSettingsModel` (injected into Settings) both appear in this factory's
// public init signature. The seam only — no `AVFoundation`.
public import GameAudio
// SDD-003 Epic 1: `boardDestination`/`GameBoardRedirect` wrap board-route
// destinations when `onPresentBoard` is wired, so board views are presented
// as fullScreenCover modals instead of NavigationStack pushes. Internal
// only — no GameAppKit type appears in this factory's public API surface.
internal import GameAppKit
// `GeneratorVersion.v1.rawValue` seeds the `.settings` case's Generator row
// label. Internal only — not part of this factory's public API surface.
internal import SudokuEngine

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
    // SudokuAppComposition; the factory only decides WHEN (Daily, not Practice). `nil`
    // in previews / tests → no primer, byte-identical Completion screens.
    private let makeDailyReminderPrimer: (@MainActor () -> ReminderPrimerCoordinator)?
    // #287/#909: the Settings Reminders entry (shared `ReminderSettingsModel` +
    // Sudoku copy), built ONCE at composition time and reused for every
    // `.settings` render — `view(for:)` is re-invoked by SwiftUI's
    // `.navigationDestination` builder on every ancestor re-render, not just
    // once per Settings mount, so a factory closure here used to hand back a
    // fresh model (and dismiss the primer sheet the instant a concurrent
    // bootstrap `.task` re-rendered an ancestor). `nil` in previews / tests →
    // no reminder section, byte-identical Settings screen.
    private let reminderSettings: ReminderSettingsEntry?
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
    // #685: closure that auth-gates the Settings Game Center row through
    // `GameRootViewModel.presentGameCenterOrAlert`, mirroring `onPresentBoard`'s
    // shape. `nil` (default) preserves the old ungated `SettingsView` behavior
    // for tests / previews that don't wire a Root VM.
    private let presentGameCenter: (@MainActor () -> Void)?
    // #744: closure that auth-gates the Settings Game Center "Invite Friends"
    // row, mirroring `presentGameCenter`'s shape exactly (built the same way
    // at the `live()` call site — wraps `GameCenterDashboard.triggerFriending()`
    // in `presentGameCenterOrAlert`). `nil` (default) keeps the row absent for
    // tests / previews that don't wire a Root VM.
    private let presentInviteFriends: (@MainActor () -> Void)?
    // #983 introduced this alongside the now-reverted `.dailyRank` route (see
    // #983 follow-up); no route currently reads it. Left wired (dormant, not
    // deleted) — `presentGameCenter`'s capture shape is identical and it is
    // cheap to re-attach if a future in-app auth-state consumer needs it.
    private let currentAuthState: (@MainActor () -> GameCenterAuthState)?

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
        reminderSettings: ReminderSettingsEntry? = nil,
        settingsNotices: SettingsNoticesConfig? = nil,
        soundPlayer: any SoundPlaying = NoopSoundPlaying(),
        audioSettings: AudioSettingsModel? = nil,
        onPresentBoard: (@MainActor (AppRoute) -> Void)? = nil,
        presentGameCenter: (@MainActor () -> Void)? = nil,
        presentInviteFriends: (@MainActor () -> Void)? = nil,
        currentAuthState: (@MainActor () -> GameCenterAuthState)? = nil
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
        self.reminderSettings = reminderSettings
        self.settingsNotices = settingsNotices
        self.soundPlayer = soundPlayer
        self.audioSettings = audioSettings
        self.onPresentBoard = onPresentBoard
        self.presentGameCenter = presentGameCenter
        self.presentInviteFriends = presentInviteFriends
        self.currentAuthState = currentAuthState
    }

    @MainActor
    public func view(for route: AppRoute, path: Binding<[AppRoute]>?) -> AnyView {
        switch route {
        case .board(let puzzleId):
            // SDD-003 Epic 1 / #491 / #559: two-context contract delegated to
            // the shared `boardDestination` helper in GameAppKit.
            //   push context  (path != nil): redirect → fullScreenCover modal.
            //   modal context (path == nil): fall through to real board view.
            // Legacy push path (onPresentBoard == nil) falls through to inline.
            return boardDestination(
                route: route,
                path: path,
                onPresentBoard: onPresentBoard
            ) {
                AnyView(
                    BoardLoaderView(
                        puzzleId: puzzleId,
                        puzzleProvider: puzzleProvider,
                        persistence: persistence,
                        errorReporter: errorReporter,
                        adProvider: adProvider,
                        adGate: adGate,
                        soundPlayer: soundPlayer,
                        path: path,
                        telemetry: telemetry,
                        // #610: thread GC + reminder primer into BoardView so
                        // the Completion overlay has everything it needs when
                        // the board is presented as a modal (path == nil).
                        gameCenter: gameCenter,
                        makeDailyReminderPrimer: makeDailyReminderPrimer,
                        // #652: Play Again — draw a fresh practice puzzle at the
                        // same difficulty and present it as a new modal. Only wired
                        // when `onPresentBoard` is available (modal presentation
                        // mode). Legacy push path (nil) → Close-only. Daily boards
                        // are intentionally Close-only: a daily is one-per-day, so
                        // "Play Again" would silently hand back a *practice* puzzle.
                        onPlayAgain: SudokuLeaderboardRouting.isDaily(puzzleId: puzzleId)
                            ? nil
                            : onPresentBoard.map { presenter in
                                { @MainActor difficulty in
                                    let provider = self.puzzleProvider
                                    Task { @MainActor in
                                        guard let envelope = try? await provider.fetchPracticePool(difficulty: difficulty) else { return }
                                        presenter(.board(puzzleId: envelope.identity.puzzleId))
                                    }
                                }
                            },
                        // #1023: resolve the Daily "more today?" CTA row —
                        // Daily-only (mirrors the `onPlayAgain` gate above, which
                        // excludes Daily for the opposite reason: Daily never
                        // gets "Play Again", only "Next"/"See you tomorrow").
                        fetchDailyProgress: SudokuLeaderboardRouting.isDaily(puzzleId: puzzleId)
                            ? Self.makeFetchDailyProgress(
                                currentPuzzleId: puzzleId,
                                puzzleProvider: puzzleProvider,
                                persistence: persistence
                            )
                            : nil,
                        onDailyNext: onPresentBoard.map { presenter in
                            { (nextPuzzleId: String) in
                                presenter(.board(puzzleId: nextPuzzleId))
                            }
                        },
                        // #1023 Phase B: streak ritual — live overlay ONLY,
                        // this is the ONE `.liveSolve` daily-win path; the
                        // pushed `.completion` review route below never gets
                        // this provider (design.md §3.5: `review` plays no
                        // ritual).
                        fetchStreakAdvance: SudokuLeaderboardRouting.isDaily(puzzleId: puzzleId)
                            ? Self.makeFetchStreakAdvance(
                                currentPuzzleId: puzzleId,
                                persistence: persistence
                            )
                            : nil
                    )
                )
            }
        case .completion(let puzzleId, let elapsedSeconds, let mistakeCount):
            // #287 Phase 2: offer the daily-ready primer ONLY on a Daily solve
            // (flow S02). Practice solves pass `reminderPrimer: nil` → no change.
            let reminderPrimer = SudokuLeaderboardRouting.isDaily(puzzleId: puzzleId)
                ? makeDailyReminderPrimer?()
                : nil
            // SDD-003 Epic 4: Close pops the last route entry so the player
            // returns to the board (which is already dismissed) or the Hub.
            let closePath = path
            // #1023: `.review` — this route is ONLY ever pushed by
            // `DailyHubViewModel.openCompleted` (re-viewing an already-
            // completed Daily), so it's always Daily-context; no ritual, no
            // haptic. Same CTA-row resolution as the live overlay / the
            // `.completedRedirect` loader state, via the shared
            // `CompletedRedirectSurface`.
            return AnyView(
                CompletedRedirectSurface(
                    completionViewModel: CompletionViewModel(
                        puzzleId: puzzleId,
                        elapsedSeconds: elapsedSeconds,
                        mistakeCount: mistakeCount,
                        leaderboardId: SudokuLeaderboardRouting.leaderboardId(forPuzzleId: puzzleId)
                    ),
                    reminderPrimer: reminderPrimer,
                    fetchDailyProgress: SudokuLeaderboardRouting.isDaily(puzzleId: puzzleId)
                        ? Self.makeFetchDailyProgress(
                            currentPuzzleId: puzzleId,
                            puzzleProvider: puzzleProvider,
                            persistence: persistence
                        )
                        : nil,
                    onDailyNext: onPresentBoard.map { presenter in
                        { (nextPuzzleId: String) in
                            presenter(.board(puzzleId: nextPuzzleId))
                        }
                    },
                    onClose: { closePath?.wrappedValue.removeLast() }
                )
            )
        case .settings:
            let appVersion = (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "1.0.0"
            // #744: this app's numeric App Store Connect id — same
            // Bundle.main read pattern as `appVersion` above. `SettingsScreen`
            // hides Share App / Write a Review when this is nil/unresolved.
            let appStoreID = Bundle.main.object(forInfoDictionaryKey: "AppStoreID") as? String
            let telemetry = self.telemetry
            return AnyView(
                SettingsView(
                    viewModel: SettingsViewModel(
                        // #832: the shared VM took over the Generator row via a
                        // plain label (GameAppKit must not depend on
                        // SudokuEngine's `GeneratorVersion`) — always `.v1`,
                        // matching the prior default-`.v1` VM field exactly.
                        generatorVersionLabel: GeneratorVersion.v1.rawValue,
                        appVersion: appVersion,
                        persistence: persistence,
                        errorReporter: errorReporter,
                        toastController: toastController
                    ),
                    monetizationController: monetizationController,
                    reminderSettings: reminderSettings,
                    notices: settingsNotices,
                    audioSettings: audioSettings,
                    presentGameCenter: presentGameCenter,
                    appStoreID: appStoreID,
                    presentInviteFriends: presentInviteFriends,
                    telemetryEmit: { event in
                        Task { await telemetry.observe(event) }
                    },
                    banner: { Self.themedBanner(adProvider: adProvider, adGate: adGate) }
                )
            )
        }
    }

    // MARK: - Daily "more today?" resolution (#1023)

    /// Shared by the `.board` (live overlay) and `.completion` (pushed
    /// review) cases — both need the SAME "is another difficulty still open
    /// today" answer. `puzzleProvider.fetchDailyTrio` is in-memory-cached
    /// (`PuzzleStore` doc), so this is a cheap cache hit in the common case
    /// (the player just came from the Daily hub, which already fetched the
    /// trio to render the cards). Picks the first trio entry that is neither
    /// the puzzle just finished nor already completed, in trio order.
    @MainActor
    static func makeFetchDailyProgress(
        currentPuzzleId: String,
        puzzleProvider: any PuzzleProviderProtocol,
        persistence: any PersistenceProtocol
    ) -> @MainActor () async -> DailyCompletionProgress {
        {
            let today = Date()
            guard let trio = try? await puzzleProvider.fetchDailyTrio(date: today) else { return .allDone }
            let completedIds = (try? await persistence.fetchCompletedDailyIds(for: today)) ?? []
            guard let next = trio.first(where: {
                $0.identity.puzzleId != currentPuzzleId && !completedIds.contains($0.identity.puzzleId)
            }) else {
                return .allDone
            }
            return .moreToday(difficulty: next.identity.difficulty, puzzleId: next.identity.puzzleId)
        }
    }

    // MARK: - Banner helper

    /// Epic 5: themed `BannerSlotView` for all non-Board screens. Same theme
    /// tokens across Today/Practice/Settings — no per-screen override. Board
    /// never calls this; it owns its own `themedBanner` method.
    /// The cast from `AdProvider` → `BannerViewProviding` follows the same
    /// pattern as BoardView (§9.1: keeps SudokuUI off AdsAdMob).
    ///
    /// #851: `backgroundColor` was `Color.secondary.opacity(0.12)` — a
    /// translucent SYSTEM-GRAY tint left over from before #688 gave
    /// `BannerSlotView` a themed default. Composited over the app's actual
    /// warm-dark page background (`DefaultTheme.surface.background.dark`,
    /// 0x15171A) it painted a visibly lighter 50pt rounded band across the
    /// bottom of Today/Practice/Settings whenever the ad gate opened —
    /// exactly the "faint horizontal banding" reported. `LiveRouteFactory` is
    /// a plain struct (not a `View`), so it cannot read `@Environment(\.theme)`
    /// like `BoardView.themedBanner` does; `DefaultTheme()` is the same
    /// concrete theme the app injects into the environment everywhere else,
    /// so resolving it directly here yields an identical color.
    ///
    /// #1020: `static` (not an instance method) so `Live+TabRoots.swift`'s
    /// Today/Practice tab-root builder — which has no `LiveRouteFactory`
    /// instance to call through, only the wired `GameDeps` bag — can reuse
    /// the exact same banner instead of re-deriving it.
    @MainActor
    static func themedBanner(adProvider: any AdProvider, adGate: AdGate) -> some View {
        BannerSlotView(
            adProvider: adProvider,
            adGate: adGate,
            bannerHost: adProvider as? any BannerViewProviding,
            backgroundColor: DefaultTheme().surface.background.resolved,
            progressTint: .accentColor,
            captionColor: .secondary,
            dismissTint: Color.secondary.opacity(0.7)
        )
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}
