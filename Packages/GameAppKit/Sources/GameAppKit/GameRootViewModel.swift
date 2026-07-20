// GameRootViewModel — game-agnostic app-launch bootstrap coordinator (#448 step 1a).
//
// Per docs/v1/design.md §How.5.4 (VM ownership / @Observable @MainActor). Owns the
// auth handshake (`GameCenterClient.authenticate`) and the resume-candidate
// fetch (the injected `fetchResume` closure). Both are kicked off in
// `bootstrap()` from the View's `.task`.
//
// Errors from either fetch are swallowed into degraded states — Root should
// never block Home (docs/v1/design.md §How.5.1: "Bootstrap never blocks Home").
//
// Generalized out of `SudokuUI.RootViewModel` (and the byte-identical
// `MinesweeperUI.MinesweeperRootViewModel`): the only game-specific bits are
// the `path` element type — a per-app `Route` enum — and how a resume
// candidate is produced. Both are injected: `Route` as the generic parameter,
// the resume mapping as the `fetchResume` closure. The closure maps each
// game's own persisted state into the game-agnostic `ResumeCandidate<Route>`
// DTO (#455), so this VM is no longer coupled to any Sudoku-typed persistence.
// Games that have no resume surface omit `fetchResume` (it defaults to nil) to
// skip the fetch and no-op `resumeTapped()`.
//
// SDD-003 Epic 1: adds modal game presentation (`presentGame` / `dismissGame`).
// Board routes that previously pushed onto `path` now use `presentGame(route:)`
// from the per-game RouteFactory or hub VMs; `GameRoot` presents them as a
// `fullScreenCover`. The leave flow is now owned by the unified PauseOverlayView
// inside each board — the former ✕ button + `requestLeave` / `cancelLeave` /
// `confirmLeave` / `isShowingLeaveConfirmation` cycle has been removed.

public import Foundation
public import GameCenterClient
public import Persistence
public import SwiftUI
public import Telemetry

@MainActor
@Observable
public final class GameRootViewModel<Route: Hashable & Sendable> {

    public private(set) var authState: GameCenterAuthState = .unknown
    public private(set) var resumeCandidate: ResumeCandidate<Route>?
    public private(set) var hasBootstrapped: Bool = false
    public var path: [Route] = []

    // MARK: - Epic 1: Modal game presentation (SDD-003)

    /// The route currently presented as a fullScreenCover game modal.
    /// Set by `presentGame(route:)`; cleared by `dismissGame()`.
    public private(set) var activeGameRoute: Route?

    /// Drives the `.fullScreenCover(isPresented:)` binding in `GameRoot`.
    /// Separate from `activeGameRoute` so SwiftUI can animate the dismiss before
    /// the route is cleared.
    public private(set) var isGamePresented: Bool = false

    /// Increments every time a game session tears down — the iOS modal
    /// dismiss (`dismissGame()`) or the macOS `path`-pop teardown (via
    /// `gameSessionDidTearDown()`, called from `GameRoot`'s path-shrink
    /// branch). Injected into the environment (`\.gameSessionTeardownCount`)
    /// so route views (e.g. the Daily hubs) can `.onChange` it to re-run a
    /// refresh instead of relying on `.onAppear`, which does not re-fire when
    /// a `fullScreenCover` dismisses (#761: sim-verified — no re-fire on the
    /// real Close → Leave flow, only on the board's own transient open/close).
    public private(set) var sessionTeardownCount: Int = 0

    // MARK: - Game Center signed-out alert (#513 fix)

    /// `true` while the "Sign in to Game Center" alert is visible.
    /// Set by `HomeViewModel` / `MinesweeperHomeViewModel` (via injected binding)
    /// when the leaderboard card is tapped with GC signed out.
    /// Lives here (stable shared object) — not on the per-render HomeViewModel —
    /// so the SwiftUI `.alert` binding survives re-renders.
    public var showGameCenterSignedOutAlert: Bool = false

    private let gameCenter: any GameCenterClient
    private let persistence: any PersistenceProtocol
    private let errorReporter: any ErrorReporter
    private let fetchResume: (() async throws -> ResumeCandidate<Route>?)?

    public init(
        gameCenter: any GameCenterClient,
        persistence: any PersistenceProtocol,
        errorReporter: any ErrorReporter = NoopErrorReporter(),
        fetchResume: (() async throws -> ResumeCandidate<Route>?)? = nil
    ) {
        self.gameCenter = gameCenter
        self.persistence = persistence
        self.errorReporter = errorReporter
        self.fetchResume = fetchResume
    }

    /// Idempotent: only the first call performs IO; subsequent calls return
    /// immediately so View `.task` re-entries (size-class changes etc.) do
    /// not re-trigger GameKit auth.
    public func bootstrap() async {
        guard !hasBootstrapped else { return }
        hasBootstrapped = true

        // Issue #196: CloudKit zone + subscription provisioning. Must run
        // before any resume read below — fresh iCloud accounts otherwise
        // hit zoneNotFound (CKError 26) on every read/write. Failures are
        // funneled through `errorReporter`; bootstrap is idempotent, so a
        // transient failure (e.g. no iCloud account) will retry next launch
        // and must not block Root per design.md §How.5.1.
        do {
            try await persistence.bootstrap()
        } catch {
            await errorReporter.report(
                UserFacingError.classify(error),
                underlying: error,
                source: "GameRootViewModel.bootstrap.persistence"
            )
        }

        do {
            self.authState = try await gameCenter.authenticate()
        } catch {
            // M10 (issue #67): authentication failure must still degrade to
            // `.unauthenticated` per design.md §How.6.1 principle 1 (never
            // block bootstrap), but the underlying error now travels through
            // the funnel so OSLog / telemetry record what actually went wrong
            // instead of silently masking to "unauthenticated".
            self.authState = .unauthenticated
            await errorReporter.report(
                .gameCenterUnauthenticated,
                underlying: error,
                source: "GameRootViewModel.bootstrap.authenticate"
            )
        }

        // #455: resume is supported iff a `fetchResume` closure was injected.
        // The closure owns its game's mapping into `ResumeCandidate`; this VM
        // owns the single error funnel. A nil result is valid (no in-flight
        // game) — only catch + route the *failure*, not the absence of data.
        guard let fetchResume else { return }
        do {
            self.resumeCandidate = try await fetchResume()
        } catch {
            self.resumeCandidate = nil
            await errorReporter.report(
                UserFacingError.classify(error),
                underlying: error,
                source: "GameRootViewModel.bootstrap.resume"
            )
        }
    }

    public func resumeTapped() {
        guard let candidate = resumeCandidate else { return }
        path.append(candidate.route)
    }

    /// Re-run the resume-candidate fetch outside `bootstrap()`'s one-shot
    /// gate (#675). `bootstrap()` only fetches once per launch, so returning
    /// Home after a game ends (completed via `markCompleted`, or abandoned)
    /// left a stale pill on screen until the next relaunch. Call this
    /// whenever a game session tears down — the modal dismiss (`dismissGame`)
    /// on iOS, and a `path` pop on macOS's push navigation. A nil result is
    /// valid (no in-flight game left) and clears any stale candidate; only a
    /// thrown error is funneled, mirroring `bootstrap()`.
    public func refreshResumeCandidate() async {
        guard let fetchResume else { return }
        do {
            self.resumeCandidate = try await fetchResume()
        } catch {
            self.resumeCandidate = nil
            await errorReporter.report(
                UserFacingError.classify(error),
                underlying: error,
                source: "GameRootViewModel.refreshResumeCandidate"
            )
        }
    }

    // MARK: - Epic 1: Modal presentation (SDD-003)

    /// Present a game board as a fullScreenCover modal. Called from per-app
    /// hub VMs (DailyHub / PracticeHub) when the player taps a board card.
    /// Replaces the former `path.append(boardRoute)` pattern.
    public func presentGame(route: Route) {
        activeGameRoute = route
        isGamePresented = true
    }

    /// Dismiss the modal game. Called by SwiftUI's `isPresented` binding setter
    /// (interactive dismiss — disabled for fullScreenCover, so in practice this
    /// fires when the board's `dismiss()` environment action collapses the cover).
    /// Safe to call when nothing is presented.
    ///
    /// - Parameter persistJoin: #823 — the shared `TerminalPersistJoin` the
    ///   dismissing board registered its in-flight terminal-persist task
    ///   with (if any). Threaded straight into `gameSessionDidTearDown` so
    ///   the `sessionTeardownCount` bump — NOT this call, which stays
    ///   synchronous/instant — can wait for a slow CloudKit save to land.
    ///   `nil` (the default) preserves the original unconditional-bump
    ///   behavior for callers that don't have a join point.
    public func dismissGame(persistJoin: TerminalPersistJoin? = nil) {
        isGamePresented = false
        activeGameRoute = nil
        // #675: the just-torn-down session may have just completed (marked
        // via `markCompleted`) or been abandoned — refresh so Home stops
        // offering a stale pill until the next launch.
        Task { await refreshResumeCandidate() }
        gameSessionDidTearDown(persistJoin: persistJoin)
    }

    /// Signals that a game session just ended. Called by `dismissGame()` (iOS
    /// fullScreenCover close) and by `handlePathShrink()` (the `path`-shrink
    /// path — on macOS a board's Leave / completion Close pops `path` directly
    /// instead of going through `dismissGame()`; see `GameRoot.shellContent`).
    /// Bumps `sessionTeardownCount` so environment-observing views (e.g. the
    /// Daily hubs, #761) can react without depending on `.onAppear` re-firing.
    ///
    /// #912: the iOS board-OPEN false-positive that used to reach this method —
    /// `GameBoardRedirect` popping its synthetic path entry at open shrinks
    /// `path` exactly like a genuine close — is now filtered out one level up in
    /// `handlePathShrink` (its `!isGamePresented` guard), so this method is only
    /// invoked on genuine session ends. Consumers should still stay
    /// idempotent/cheap (like the hubs' guarded `refresh()`), but no longer see
    /// a spurious bump at board open.
    ///
    /// - Parameter persistJoin: #823 — when supplied, the bump is deferred
    ///   into an unstructured `Task` that first awaits
    ///   `persistJoin.awaitPending()` (bounded — see `TerminalPersistJoin`),
    ///   closing the race where this bump (and the hub refresh it drives)
    ///   could run before a terminal-transition CloudKit save had landed.
    ///   `nil` (the default) preserves the original synchronous bump, so
    ///   existing callers/tests that have no join point are unaffected.
    public func gameSessionDidTearDown(persistJoin: TerminalPersistJoin? = nil) {
        guard let persistJoin else {
            sessionTeardownCount += 1
            return
        }
        Task {
            await persistJoin.awaitPending()
            sessionTeardownCount += 1
        }
    }

    /// #912: called from `GameRoot`'s `path`-shrink branch instead of that
    /// branch unconditionally firing `refreshResumeCandidate()` +
    /// `gameSessionDidTearDown()` on every shrink. Filters out the specific
    /// false-positive `gameSessionDidTearDown()`'s own doc already names: on
    /// iOS, `GameBoardRedirect` pops its synthetic push entry once at board
    /// OPEN (immediately before presenting the fullScreenCover) — that pop
    /// shrinks `path` exactly like a genuine close does, over-approximating
    /// "a session ended" into also meaning "a session just started".
    ///
    /// Distinguishing signal: `GameBoardRedirect` now calls `onPresent`
    /// (→ `presentGame(route:)`, which flips `isGamePresented` to `true`)
    /// BEFORE popping its path entry, so by the time this method runs for
    /// that synthetic pop, `isGamePresented` is already `true` — a state no
    /// genuine close can be in (a real close only pops `path` on macOS,
    /// which never presents a fullScreenCover at all; on iOS a real close
    /// goes through `dismissGame()`, a completely separate call path from
    /// this one). So `isGamePresented == true` here means "this shrink is
    /// the board-OPEN redirect pop", not "a session ended", and the refresh
    /// + teardown bump are skipped.
    public func handlePathShrink(persistJoin: TerminalPersistJoin? = nil) {
        guard !isGamePresented else { return }
        Task { await refreshResumeCandidate() }
        gameSessionDidTearDown(persistJoin: persistJoin)
    }

    // MARK: - Game Center signed-out guard (#685)

    /// Shared auth-gate for every Game Center entry point: presents when
    /// authenticated, otherwise raises `showGameCenterSignedOutAlert`. Both
    /// the Home leaderboard card (`GameHomeViewModel.select(.leaderboard)`)
    /// and the Settings Game Center row route through this single guard so
    /// the signed-out fallback can't drift between the two entry points
    /// (#685: the Settings row previously had no guard at all).
    @MainActor
    public func presentGameCenterOrAlert(present: () -> Void) {
        if case .authenticated = authState {
            present()
        } else {
            showGameCenterSignedOutAlert = true
        }
    }
}

// MARK: - EnvironmentKey (#761)

private struct GameSessionTeardownCountKey: EnvironmentKey {
    static let defaultValue: Int = 0
}

public extension EnvironmentValues {
    /// `GameRootViewModel.sessionTeardownCount`, injected by `GameRoot` so any
    /// route view can `.onChange` it to react to a game session ending — the
    /// explicit signal Daily hub refresh (#761) rides instead of `.onAppear`,
    /// which does not re-fire when a `fullScreenCover` dismisses.
    var gameSessionTeardownCount: Int {
        get { self[GameSessionTeardownCountKey.self] }
        set { self[GameSessionTeardownCountKey.self] = newValue }
    }
}
