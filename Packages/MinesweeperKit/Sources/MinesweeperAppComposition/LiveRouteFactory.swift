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
// #448: the divergent in-play toolbar "New Game" button was removed to restore
// parity with Sudoku's board route. #697: the `.completion` route's Close CTA
// now pops one level (`path.removeLast()`), mirroring Sudoku's completion
// Close instead of emptying the whole path back to Home.

public import SwiftUI
public import GameCenterClient
public import GameShellUI
// SDD-003 Epic 1: `GameBoardRedirect` wraps board-route destinations when
// `onPresentBoard` is wired, so board views are presented as fullScreenCover
// modals instead of NavigationStack pushes. `LastSelectionStore` backs the
// #720 G2 Practice-difficulty persistence below.
public import GameAppKit
public import MinesweeperUI
// #720 G2: `Difficulty` used to seed/persist the Practice hub's last-selected
// difficulty. Internal only — not part of this factory's public API surface.
internal import MinesweeperEngine
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
    // #572: builds the Settings Reminders entry per Settings mount. Injected as
    // a closure so ALL reminder wiring stays in composition. `nil` in previews /
    // tests → no reminder section, byte-identical Settings screen. Mirrors Sudoku's
    // `makeReminderSettings`. Type changed from `MinesweeperReminderSettingsEntry`
    // to the shared `ReminderSettingsEntry` (SettingsUI) as part of #572 cleanup.
    private let makeReminderSettings: (@MainActor () -> ReminderSettingsEntry)?
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
    // #699: personal-best store, threaded into every board (+ the
    // `.resumeBoard` loader) so a daily win records the personal best right
    // beside the GC submit. Optional so preview / test callsites stay
    // side-effect-free (mirrors `savedGameStore`'s optionality). MS-specific
    // (owner decision, #699) — not wired through the shared TelemetryKit sink.
    private let personalRecordStore: MinesweeperPersonalRecordStore?
    // SDD-003 Epic 1: closure that modal-presents a board route via
    // `GameRootViewModel.presentGame(route:)`. When non-nil, `.board` and
    // `.resumeBoard` routes return a `GameBoardRedirect` instead of building
    // the board view inline as a NavigationStack push destination.
    // `nil` (default) preserves legacy push behavior for tests / previews.
    private let onPresentBoard: (@MainActor (AppRoute) -> Void)?
    // #685: closure that auth-gates the Settings Game Center row through
    // `GameRootViewModel.presentGameCenterOrAlert`, mirroring `onPresentBoard`'s
    // shape. `nil` (default) preserves the old ungated `SettingsView` behavior
    // for tests / previews that don't wire a Root VM.
    private let presentGameCenter: (@MainActor () -> Void)?
    // #744: `presentInviteFriends` mirrors `presentGameCenter`'s shape;
    // `telemetry` fans out share/review/invite taps (unlike MS's game-outcome stores, #699).
    private let presentInviteFriends: (@MainActor () -> Void)?
    private let telemetry: Telemetry?

    public init(
        monetizationController: MonetizationStateController? = nil,
        adProvider: (any AdProvider)? = nil,
        adGate: AdGate? = nil,
        persistence: (any PersistenceProtocol)? = nil,
        gameCenter: (any GameCenterClient)? = nil,
        errorReporter: (any ErrorReporter)? = nil,
        toastController: ToastController? = nil,
        makeReminderSettings: (@MainActor () -> ReminderSettingsEntry)? = nil,
        soundPlayer: (any SoundPlaying)? = nil,
        audioSettings: AudioSettingsModel? = nil,
        savedGameStore: MinesweeperSavedGameStore? = nil,
        personalRecordStore: MinesweeperPersonalRecordStore? = nil,
        onPresentBoard: (@MainActor (AppRoute) -> Void)? = nil,
        presentGameCenter: (@MainActor () -> Void)? = nil,
        presentInviteFriends: (@MainActor () -> Void)? = nil,
        telemetry: Telemetry? = nil
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
        self.personalRecordStore = personalRecordStore
        self.onPresentBoard = onPresentBoard
        self.presentGameCenter = presentGameCenter
        self.presentInviteFriends = presentInviteFriends
        self.telemetry = telemetry
    }

    @MainActor
    // The route→view switch reads as one cohesive mapping; extracting a helper
    // per case would obscure the route table (7 cases post-SDD-003 Epic 8).
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
            // #720 G2: remember the player's last-picked Practice difficulty
            // across launches instead of always resetting to Beginner.
            let difficultyStore = LastSelectionStore(
                key: "com.wei18.minesweeper.practice.lastDifficulty",
                fallback: Difficulty.beginner.rawValue
            )
            return AnyView(
                MinesweeperPracticeHubView(
                    path: path ?? .constant([]),
                    initialDifficulty: Difficulty(rawValue: difficultyStore.load()) ?? .beginner,
                    onDifficultyChanged: { difficultyStore.save($0.rawValue) },
                    banner: { bannerSlot() }
                )
            )
        case .board(let difficulty, let seed, let mode):
            // SDD-003 Epic 1 / #491 / #559: two-context contract delegated to
            // shared `boardDestination` helper in GameAppKit.
            return boardDestination(
                route: route,
                path: path,
                onPresentBoard: onPresentBoard
            ) {
                AnyView(
                    MinesweeperBoardView(
                        difficulty: difficulty,
                        seed: seed,
                        mode: mode,
                        adProvider: self.adProvider,
                        adGate: self.adGate,
                        gameCenter: self.gameCenter,
                        errorReporter: self.errorReporter,
                        // #330 P2: gameplay audio. nil (preview / test) → silent Noop.
                        soundPlayer: self.soundPlayer ?? NoopSoundPlaying(),
                        // #652: Play Again — dismiss current board and present a new
                        // practice board at the same difficulty with a fresh seed.
                        // Only wired when `onPresentBoard` is available AND this is a
                        // practice board: a daily is one-per-day, so Play Again would
                        // silently hand back a practice board (it draws mode: .practice).
                        onPlayAgain: mode == .practice
                            ? onPresentBoard.map { presenter in
                                { @MainActor difficulty in
                                    let seed = UInt64.random(in: .min ... .max)
                                    presenter(.board(difficulty: difficulty, seed: seed, mode: .practice))
                                }
                            }
                            : nil,
                        // #455 step 4: persistence seam. The save's identity is
                        // derived ONCE here (today's date for a daily, a singleton
                        // slot per practice difficulty) — see the store's
                        // recordName helpers for the scheme rationale.
                        store: self.savedGameStore,
                        recordName: MinesweeperSavedGameStore.recordName(mode: mode, difficulty: difficulty),
                        personalRecordStore: self.personalRecordStore
                    )
                )
            }
        case .resumeBoard(let recordName, let mode):
            // #455 step 4 / #491 / #559: same two-context contract as `.board`,
            // delegated to shared `boardDestination` helper.
            // Without a store (preview / test) the loader falls back to EmptyView.
            return boardDestination(
                route: route,
                path: path,
                onPresentBoard: onPresentBoard
            ) {
                guard let savedGameStore = self.savedGameStore else { return AnyView(EmptyView()) }
                return AnyView(
                    MinesweeperBoardLoaderView(
                        recordName: recordName,
                        mode: mode,
                        store: savedGameStore,
                        adProvider: self.adProvider,
                        adGate: self.adGate,
                        gameCenter: self.gameCenter,
                        errorReporter: self.errorReporter,
                        soundPlayer: self.soundPlayer ?? NoopSoundPlaying(),
                        personalRecordStore: self.personalRecordStore
                    )
                )
            }
        case .replayDailyBoard(let difficulty, let seed):
            // Epic 8 (SDD-003) / #491 / #559: unscored free replay after a failed
            // daily. Built WITHOUT store/recordName (no persistence side-effects)
            // and WITHOUT gameCenter (mode == .practice guards GC submit).
            // Two-context contract delegated to shared `boardDestination` helper.
            return boardDestination(
                route: route,
                path: path,
                onPresentBoard: onPresentBoard
            ) {
                AnyView(
                    MinesweeperBoardView(
                        difficulty: difficulty,
                        seed: seed,
                        mode: .practice,
                        adProvider: self.adProvider,
                        adGate: self.adGate,
                        gameCenter: nil,
                        errorReporter: self.errorReporter,
                        soundPlayer: self.soundPlayer ?? NoopSoundPlaying()
                        // store: nil, recordName: nil — intentionally omitted so no
                        // save is written and the Failed record stays intact.
                        // personalRecordStore: nil — ALSO intentional: #705 widened
                        // practice-mode personal-record writes, so wiring a store
                        // here would record unscored daily replays as practice PBs
                        // (the replay reuses the daily seed, so each replayed board
                        // would mint a stable practice-{base32(seed)} dedup id).
                    )
                )
            }

        case .completion(let difficulty, _):
            // #386: re-viewing an already-solved daily. Build the same
            // `MinesweeperCompletionView` the live board overlay uses, but
            // standalone (no board behind it) and seeded as a WIN — a solved
            // daily is, by definition, won. MS has no stored elapsed (#284), so
            // the hero OMITS the time row entirely (`showsElapsedTime: false`);
            // the player's real ranked time shows in the leaderboard slice. New
            // Game pops to the picker; no Retry (replaying the same daily is the
            // dead-replay #386 avoids).
            // #697: Close pops one level (mirrors Sudoku's LiveRouteFactory
            // completion Close: `closePath?.wrappedValue.removeLast()`) instead of
            // emptying the whole path back to Home. Retry removed at this
            // injection site.
            // Wrap in the shared scaffold so this pushed-route re-view matches the
            // centred-card layout of the in-board overlay (the card is intrinsic;
            // the scaffold owns bg / centring / Close).
            let closePath = path
            return AnyView(
                CompletionOverlayScaffold(
                    onClose: { closePath?.wrappedValue.removeLast() },
                    card: {
                        MinesweeperCompletionView(
                            viewModel: MinesweeperCompletionViewModel(
                                didWin: true,
                                elapsedSeconds: 0,
                                leaderboardId: MinesweeperLeaderboardID.daily(for: difficulty)
                            ),
                            onClose: nil,
                            showsElapsedTime: false
                        )
                    }
                )
            )
        case .settings:
            let version = (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "1.0.0"
            let appStoreID = Bundle.main.object(forInfoDictionaryKey: "AppStoreID") as? String // #744
            let persistence = self.persistence
            let errorReporter = self.errorReporter
            let toastController = self.toastController
            let telemetry = self.telemetry
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
                    presentGameCenter: presentGameCenter,
                    appStoreID: appStoreID,
                    presentInviteFriends: presentInviteFriends,
                    telemetryEmit: { event in Task { await telemetry?.observe(event) } },
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
