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
// The board destination is wrapped with a "New Game" toolbar Button that
// pops back to the picker (`popToNewGame` → `path.removeAll()`). Wrapping at
// this site (instead of editing `MinesweeperBoardView`) keeps the merged MVP
// file's public API untouched.

public import SwiftUI
public import GameCenterClient
public import GameShellUI
public import MinesweeperUI
public import MonetizationCore
public import MonetizationUI
public import Persistence
public import Telemetry

internal import Foundation
// refactor/settingskit-target (2026-06-09): `SettingsNoticesConfig` moved out of
// GameShellUI into SettingsUI. Used only in the private `makeSettingsNotices()`,
// so the import is internal.
internal import SettingsUI

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

    public init(
        monetizationController: MonetizationStateController? = nil,
        adProvider: (any AdProvider)? = nil,
        adGate: AdGate? = nil,
        persistence: (any PersistenceProtocol)? = nil,
        gameCenter: (any GameCenterClient)? = nil,
        errorReporter: (any ErrorReporter)? = nil,
        toastController: ToastController? = nil,
        makeReminderSettings: (@MainActor () -> MinesweeperReminderSettingsEntry)? = nil
    ) {
        self.monetizationController = monetizationController
        self.adProvider = adProvider
        self.adGate = adGate
        self.persistence = persistence
        self.gameCenter = gameCenter
        self.errorReporter = errorReporter
        self.toastController = toastController
        self.makeReminderSettings = makeReminderSettings
    }

    @MainActor
    public func view(for route: AppRoute, path: Binding<[AppRoute]>?) -> AnyView {
        switch route {
        case .newGame:
            // Difficulty picker — was the old root content; now a destination
            // pushed from the Home "New Game" card / sidebar (#288 / #289).
            return AnyView(NewGameView(path: path ?? .constant([])))
        case .daily:
            // #290: date-seeded daily trio + completion overlay. The hub VM
            // pulls the three boards from `LiveMinesweeperDailyProvider`
            // (pure, deterministic per UTC day) and marks completed cards via
            // `PersistenceProtocol.fetchCompletedDailyIds` (parity-only until
            // MS daily save-flow lands — returns [] today).
            return AnyView(
                MinesweeperDailyHubView(
                    viewModel: MinesweeperDailyHubViewModel(
                        path: path ?? .constant([]),
                        provider: LiveMinesweeperDailyProvider(),
                        persistence: persistence
                    )
                )
            )
        case .practice:
            // Was unreachable (no AppRoute case). Now reachable from Home.
            return AnyView(MinesweeperPracticeHubView(path: path ?? .constant([])))
        case .board(let difficulty, let seed, let mode):
            return AnyView(
                MinesweeperBoardView(
                    difficulty: difficulty,
                    seed: seed,
                    mode: mode,
                    adProvider: adProvider,
                    adGate: adGate,
                    gameCenter: gameCenter,
                    errorReporter: errorReporter,
                    // #292: the Completion overlay's "New Game" CTA pops the
                    // stack back to the difficulty picker — same target as the
                    // in-play toolbar button below.
                    onNewGame: { Self.popToNewGame(path: path) }
                )
                    .toolbar {
                        ToolbarItem(placement: .primaryAction) {
                            Button("New Game", systemImage: "plus.circle") {
                                // Pop everything off the stack — root content
                                // (NewGameView) becomes visible again so the
                                // user can pick a fresh difficulty + seed.
                                Self.popToNewGame(path: path)
                            }
                            .accessibilityIdentifier("minesweeper.board.newGame")
                        }
                    }
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
            return AnyView(
                MinesweeperCompletionView(
                    viewModel: MinesweeperCompletionViewModel(
                        didWin: true,
                        elapsedSeconds: 0,
                        leaderboardId: MinesweeperLeaderboardID.daily(for: difficulty),
                        gameCenter: gameCenter
                    ),
                    onNewGame: { Self.popToNewGame(path: path) },
                    onRetry: nil,
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
                    reminderSettings: makeReminderSettings?()
                )
            )
        }
    }

    /// #331: builds the MS Notices section config. Mirrors Sudoku — the
    /// acknowledgements row deep-links to the app's iOS Settings page where
    /// LicensePlist's `Settings.bundle` surfaces (omitted on macOS, no
    /// deep-link); copyright derived locally; privacy/support URLs unwired
    /// pending a canonical public URL (see #331 meeting note).
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

    /// Deletes the active in-progress saved game, mirroring Sudoku's
    /// `SettingsViewModel.clearCache()`, and surfaces user feedback (#284).
    ///
    /// On success → a success toast ("Cache cleared"). On a thrown delete
    /// error → the error funnels through `errorReporter` (same channel Sudoku
    /// uses) AND a failure toast tells the user it didn't clear. Parity-only
    /// until MS save-flow lands: `latestInProgress()` returns nil today so the
    /// delete is a safe no-op and the success path is cosmetic, but it
    /// exercises the real `PersistenceProtocol` path and the error path is the
    /// real future-proofing.
    ///
    /// `internal` (not `private`) so `LiveRouteFactoryTests` can drive the
    /// success / failure branches directly with a fake persistence — there is
    /// no MS Settings ViewModel to host the logic (the Sudoku home).
    @MainActor
    static func clearCache(
        persistence: (any PersistenceProtocol)?,
        errorReporter: (any ErrorReporter)?,
        toastController: ToastController?
    ) async {
        guard let persistence else { return }
        do {
            if let candidate = try await persistence.latestInProgress() {
                try await persistence.deleteAbandoned(recordName: candidate.recordName)
            }
            // Localized via the app catalog (Bundle.main) — `Toast.message` is a
            // plain String rendered verbatim by `Text`, so the lookup happens
            // here, not at the view layer.
            toastController?.show(
                Toast(
                    style: .success,
                    message: String(localized: "Cache cleared", bundle: .main)
                )
            )
        } catch {
            await errorReporter?.report(
                UserFacingError.classify(error),
                underlying: error,
                source: "LiveRouteFactory.clearCache"
            )
            toastController?.show(
                Toast(
                    style: .failure,
                    message: String(localized: "Couldn't clear cache", bundle: .main)
                )
            )
        }
    }

    /// Empties the navigation path so the root content (NewGameView) becomes
    /// visible again. Safe against any path depth, empty path, and nil
    /// binding. Extracted for unit testing — see `LiveRouteFactoryTests`.
    @MainActor
    internal static func popToNewGame(path: Binding<[AppRoute]>?) {
        path?.wrappedValue.removeAll()
    }
}
