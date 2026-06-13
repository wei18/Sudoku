// LiveRouteFactory — Minesweeper's concrete `RouteFactory<AppRoute>`.
//
// Mirrors `SudokuKit.LiveRouteFactory` but slimmer — Standard tier still
// has no Persistence-VM / GameCenter wire. The factory exists for the same
// shape reason: keep `MinesweeperRoot.init` at one argument (the factory)
// even as destination construction grows.
//
// MS monetization wire Phase 3 (2026-06-03): factory now threads
// `MonetizationStateController` through so SettingsView can mount the
// shared `MonetizationUI` Purchases rows.
//
// #277: factory also threads `persistence` so the shared
// `SettingsStorageSection` "Clear cache" action wires to the same
// `PersistenceProtocol.latestInProgress()` → `deleteAbandoned(recordName:)`
// shape Sudoku's `SettingsViewModel` uses. Parity-only until MS save-flow
// lands (`latestInProgress()` returns nil today → the delete is a safe
// no-op), but it IS the real protocol method, not a fake button. Version is
// read from `Bundle.main` (CFBundleShortVersionString) at the callsite.
//
// #284: clear-cache now surfaces user feedback, mirroring Sudoku's
// `SettingsViewModel.clearCache()`. Success → a success toast on the shared
// `ToastController` (mounted on `MinesweeperRoot` via `.toastOverlay`); a
// thrown delete error → the existing `errorReporter` funnel PLUS a failure
// toast (Sudoku reports + shows success-anyway; MS shows the failure so the
// user isn't told "cleared" when it wasn't). The success path is cosmetic
// today — no MS save-flow → `latestInProgress()` returns nil → nothing to
// delete — but the error path is the real future-proofing.
//
// #448: the board destination's "New Game" CTA lives only in the Completion
// overlay (threaded via `onNewGame` → `popToNewGame` → `path.removeAll()`).
// The divergent in-play toolbar button was removed to restore parity with
// Sudoku's board route, which has no such toolbar item.

public import SwiftUI
public import GameCenterClient
public import GameShellUI
// SDD-003 Epic 1: `GameBoardRedirect` wraps board-route destinations when
// `onPresentBoard` is wired, so board views are presented as fullScreenCover
// modals instead of NavigationStack pushes.
public import GameAppKit
public import MinesweeperUI
public import MonetizationCore
public import MonetizationUI
public import MinesweeperPersistence
public import Persistence
public import Telemetry
// #330 P2: `SoundPlaying` is threaded into `MinesweeperBoardView` (gameplay audio)
// and `AudioSettingsModel` (in SettingsUI) into the Settings screen. Public
// because `SoundPlaying` appears in the public `init`.
public import GameAudio

internal import Foundation
// refactor/settingskit-target (2026-06-09): `SettingsNoticesConfig` moved out of
// GameShellUI into SettingsUI. Used only in the private `makeSettingsNotices()`,
// so the import is internal. #330 P2 also names `AudioSettingsModel` (SettingsUI).
public import SettingsUI

#if canImport(UIKit)
internal import UIKit
#endif

public struct LiveRouteFactory: RouteFactory {
    public typealias Route = AppRoute

    private let monetizationController: MonetizationStateController?
    // #277: threaded so the SettingsView "Clear cache" action can delete the
    // active in-progress saved game via `PersistenceProtocol`. Optional so the
    // existing nil-persistence callsites (previews) keep compiling — when nil,
    // SettingsView gets an empty clear-cache closure.
    private let persistence: (any PersistenceProtocol)?
    // U15 (2026-06-03): threaded into `MinesweeperBoardView` so it can mount
    // a `BannerSlotView` mirror below the grid. Optional so the existing
    // Phase 3 callsite (no monetization) keeps compiling; production wires
    // both, previews pass nil.
    private let adProvider: (any AdProvider)?
    private let adGate: AdGate?
    // #291: threaded into `MinesweeperBoardView` so its `MinesweeperGameViewModel`
    // can submit a best-time to the difficulty's leaderboard on win. Optional so
    // preview callsites (no GC) keep compiling — when nil, submit-on-win no-ops.
    private let gameCenter: (any GameCenterClient)?
    private let errorReporter: (any ErrorReporter)?
    // #284: optional toast surface forwarded into the clear-cache action so
    // success / failure feedback lands on the same bottom overlay as IAP
    // results (mounted on `MinesweeperRoot` via `.toastOverlay`). Optional so
    // preview / test callsites that pass no controller keep compiling — when
    // nil, clear-cache still runs (and still reports errors) but shows no toast.
    private let toastController: ToastController?
    // #287: builds the Settings Reminders entry (shared `ReminderSettingsModel` +
    // MS copy) per Settings mount. Injected as a closure (not the raw Reminders
    // seams) so ALL reminder wiring stays in `.live()`. `nil` in previews / tests
    // → no reminder section, byte-identical Settings screen. Mirrors Sudoku's
    // `makeReminderSettings`.
    private let makeReminderSettings: (@MainActor () -> MinesweeperReminderSettingsEntry)?
    // #330 P2: gameplay-audio player, threaded into every `MinesweeperBoardView`
    // so the VM fires sfx + haptics and the board starts BGM. Optional so
    // preview / test callsites stay silent — when nil, the board defaults to
    // `NoopSoundPlaying`.
    private let soundPlayer: (any SoundPlaying)?
    // #330 P2: the shared Settings audio model (mute / volumes / BGM / haptics),
    // built once at the composition root over the Live player + UserDefaults.
    // Optional so preview / test Settings stay byte-identical (no Sound section).
    private let audioSettings: AudioSettingsModel?
    // #455 step 4: saved-game store, threaded into every board so the VM can
    // persist (pause / background / terminal) and into the `.resumeBoard`
    // loader. Optional so preview / test callsites stay persistence-free.
    private let savedGameStore: MinesweeperSavedGameStore?
    // SDD-003 Epic 1: closure that modal-presents a board route via
    // `GameRootViewModel.presentGame(route:)`. When non-nil, `.board` and
    // `.resumeBoard` routes return a `GameBoardRedirect` instead of building
    // the board view inline as a NavigationStack push destination.
    // `nil` (default) preserves legacy push behavior for tests / previews.
    private let onPresentBoard: (@MainActor (AppRoute) -> Void)?

    public init(
        monetizationController: MonetizationStateController? = nil,
        adProvider: (any AdProvider)? = nil,
        adGate: AdGate? = nil,
        persistence: (any PersistenceProtocol)? = nil,
        gameCenter: (any GameCenterClient)? = nil,
        errorReporter: (any ErrorReporter)? = nil,
        toastController: ToastController? = nil,
        makeReminderSettings: (@MainActor () -> MinesweeperReminderSettingsEntry)? = nil,
        soundPlayer: (any SoundPlaying)? = nil,
        audioSettings: AudioSettingsModel? = nil,
        savedGameStore: MinesweeperSavedGameStore? = nil,
        onPresentBoard: (@MainActor (AppRoute) -> Void)? = nil
    ) {
        self.monetizationController = monetizationController
        self.adProvider = adProvider
        self.adGate = adGate
        self.persistence = persistence
        self.gameCenter = gameCenter
        self.errorReporter = errorReporter
        self.toastController = toastController
        self.makeReminderSettings = makeReminderSettings
        self.soundPlayer = soundPlayer
        self.audioSettings = audioSettings
        self.savedGameStore = savedGameStore
        self.onPresentBoard = onPresentBoard
    }

    @MainActor
    // The route→view switch reads as one cohesive mapping; extracting a helper
    // per case would obscure the route table (7 cases post-SDD-003 Epic 8).
    // swiftlint:disable:next cyclomatic_complexity
    public func view(for route: AppRoute, path: Binding<[AppRoute]>?) -> AnyView {
        switch route {
        case .daily:
            // #290: date-seeded daily trio + completion overlay. The hub VM
            // pulls the three boards from `LiveMinesweeperDailyProvider`
            // (pure, deterministic per UTC day), marks completed cards via
            // `PersistenceProtocol.fetchCompletedDailyIds`, and marks failed
            // cards via `MinesweeperSavedGameStore.fetchFailedDailyIds`
            // (Epic 8 / SDD-003).
            return AnyView(
                MinesweeperDailyHubView(
                    viewModel: MinesweeperDailyHubViewModel(
                        path: path ?? .constant([]),
                        provider: LiveMinesweeperDailyProvider(),
                        persistence: persistence,
                        savedGameStore: savedGameStore
                    ),
                    banner: { bannerSlot() }
                )
            )
        case .practice:
            // Was unreachable (no AppRoute case). Now reachable from Home.
            return AnyView(
                MinesweeperPracticeHubView(
                    path: path ?? .constant([]),
                    banner: { bannerSlot() }
                )
            )
        case .board(let difficulty, let seed, let mode):
            // SDD-003 Epic 1 / #491: two-context contract (mirrors SudokuKit):
            //   push context  (path != nil): redirect → modal via onPresentBoard.
            //   modal context (path == nil): GameRoot builds modal content here;
            //     the redirect must NOT fire or the modal is blank (Color.clear).
            if let onPresentBoard, path != nil {
                return AnyView(
                    GameBoardRedirect(
                        route: route,
                        path: path,
                        onPresent: onPresentBoard
                    )
                )
            }
            return AnyView(
                MinesweeperBoardView(
                    difficulty: difficulty,
                    seed: seed,
                    mode: mode,
                    adProvider: adProvider,
                    adGate: adGate,
                    gameCenter: gameCenter,
                    errorReporter: errorReporter,
                    // #330 P2: gameplay audio. nil (preview / test) → silent Noop.
                    soundPlayer: soundPlayer ?? NoopSoundPlaying(),
                    // #292: the Completion overlay's "New Game" CTA pops the
                    // stack back to the difficulty picker.
                    onNewGame: { Self.popToNewGame(path: path) },
                    // #455 step 4: persistence seam. The save's identity is
                    // derived ONCE here (today's date for a daily, a singleton
                    // slot per practice difficulty) — see the store's
                    // recordName helpers for the scheme rationale.
                    store: savedGameStore,
                    recordName: MinesweeperSavedGameStore.recordName(mode: mode, difficulty: difficulty)
                )
            )
        case .resumeBoard(let recordName, let mode):
            // #455 step 4: restore a persisted board. Loader fetches the
            // snapshot + rebuilds the exact board; without a store (preview /
            // test factories) the route is unreachable — fetchResume is only
            // wired in `.live()` — so an empty view is an honest fallback.
            // SDD-003 Epic 1 / #491: same two-context contract as `.board`:
            //   push context  (path != nil): redirect → modal.
            //   modal context (path == nil): return real loader, not redirect.
            if let onPresentBoard, path != nil {
                return AnyView(
                    GameBoardRedirect(
                        route: route,
                        path: path,
                        onPresent: onPresentBoard
                    )
                )
            }
            guard let savedGameStore else { return AnyView(EmptyView()) }
            return AnyView(
                MinesweeperBoardLoaderView(
                    recordName: recordName,
                    mode: mode,
                    store: savedGameStore,
                    adProvider: adProvider,
                    adGate: adGate,
                    gameCenter: gameCenter,
                    errorReporter: errorReporter,
                    soundPlayer: soundPlayer ?? NoopSoundPlaying(),
                    onNewGame: { Self.popToNewGame(path: path) }
                )
            )
        case .replayDailyBoard(let difficulty, let seed):
            // Epic 8 (SDD-003): unscored free replay after a failed daily. The
            // board is built WITHOUT a `store` or `recordName` (no persistence
            // side-effects) and WITHOUT `gameCenter` scoring (the `mode` is
            // `.practice` so the GC daily-submit guard in MinesweeperGameViewModel
            // fires). The Failed record from the first attempt is untouched.
            // #491: same two-context contract — redirect only in push context.
            if let onPresentBoard, path != nil {
                return AnyView(
                    GameBoardRedirect(
                        route: .replayDailyBoard(difficulty: difficulty, seed: seed),
                        path: path,
                        onPresent: onPresentBoard
                    )
                )
            }
            return AnyView(
                MinesweeperBoardView(
                    difficulty: difficulty,
                    seed: seed,
                    mode: .practice,
                    adProvider: adProvider,
                    adGate: adGate,
                    gameCenter: nil,
                    errorReporter: errorReporter,
                    soundPlayer: soundPlayer ?? NoopSoundPlaying(),
                    onNewGame: { Self.popToNewGame(path: path) }
                    // store: nil, recordName: nil — intentionally omitted so no
                    // save is written and the Failed record stays intact.
                )
            )

        case .completion(let difficulty, _):
            // #386: re-viewing an already-solved daily. Build the same
            // `MinesweeperCompletionView` the live board overlay uses, but
            // standalone (no board behind it) and seeded as a WIN — a solved
            // daily is, by definition, won. MS has no stored elapsed (#284), so
            // the hero OMITS the time row entirely (`showsElapsedTime: false`);
            // the player's real ranked time shows in the leaderboard slice. New
            // Game pops to the picker; no Retry (replaying the same daily is the
            // dead-replay #386 avoids).
            // SDD-003 Epic 4: Close pops back to the hub (same as the old
            // New Game CTA). Retry removed at this injection site.
            return AnyView(
                MinesweeperCompletionView(
                    viewModel: MinesweeperCompletionViewModel(
                        didWin: true,
                        elapsedSeconds: 0,
                        leaderboardId: MinesweeperLeaderboardID.daily(for: difficulty),
                        gameCenter: gameCenter
                    ),
                    onClose: { Self.popToNewGame(path: path) },
                    showsElapsedTime: false
                )
            )
        case .settings:
            let version = (Bundle.main
                .object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)
                ?? "1.0.0"
            let persistence = self.persistence
            let errorReporter = self.errorReporter
            let toastController = self.toastController
            return AnyView(
                SettingsView(
                    version: version,
                    clearCache: {
                        await Self.clearCache(
                            persistence: persistence,
                            errorReporter: errorReporter,
                            toastController: toastController
                        )
                    },
                    monetizationController: monetizationController,
                    notices: Self.makeSettingsNotices(),
                    reminderSettings: makeReminderSettings?(),
                    // #330 P2: the shared Sound section (nil in preview/test → no
                    // section, byte-identical screen).
                    audioSettings: audioSettings,
                    banner: { bannerSlot() }
                )
            )
        }
    }

    // MARK: - Banner helper

    /// Epic 5: banner slot for non-Home, non-Board screens. The cast from
    /// `AdProvider` → `BannerViewProviding` follows the §9.1 pattern (keeps
    /// MinesweeperAppComposition off GoogleMobileAds). When adProvider / adGate
    /// are nil (preview / test), the slot itself is not created — the caller
    /// passes EmptyView via the `banner: {}` default instead.
    @MainActor
    // Uses BannerSlotView's system-default colors, which today coincide with
    // Sudoku's themedBanner() values. If MS adopts per-theme accents, pass
    // theme tokens here like Sudoku's RouteFactory.themedBanner() (#468 Epic 5
    // theming note) so hub/settings banners match the themed Home banner.
    private func bannerSlot() -> some View {
        if let adProvider, let adGate {
            AnyView(
                BannerSlotView(
                    adProvider: adProvider,
                    adGate: adGate,
                    bannerHost: adProvider as? any BannerViewProviding
                )
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            )
        } else {
            AnyView(EmptyView())
        }
    }

    /// #331: builds the MS Notices section config. Mirrors Sudoku — the
}
