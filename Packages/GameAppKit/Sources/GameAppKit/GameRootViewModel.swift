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
// SDD-003 Epic 1+2: adds modal game presentation (`presentGame` / `dismissGame`)
// and leave-confirmation state (`requestLeave` / `cancelLeave` / `confirmLeave`).
// Board routes that previously pushed onto `path` now use `presentGame(route:)`
// from the per-game RouteFactory or hub VMs; `GameRoot` presents them as a
// `fullScreenCover`. The `[X]` close button calls `requestLeave()` → dialog →
// `confirmLeave()` dismisses.
//
// SDD-003 Epic 2/3 rider (flush-before-leave): the board's `onDisappear` runs a
// bare `Task` which races with the 500ms debounce window. `confirmLeave()` now
// awaits an optional `onBeforeLeave` closure first so callers can inject a
// `flush()` / `persistCurrentState()` call before the modal tears down.
// Tradeoff: GameShellKit zero-dep rule requires the flush to be injected here
// rather than called directly — each game wires its own closure at construction
// time. If a game omits it, the existing `onDisappear` bare-Task remains the
// sole save point (same behaviour as before this rider).

public import Foundation
public import GameCenterClient
public import Persistence
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
    /// Set by `presentGame(route:)`; cleared by `dismissGame()` / `confirmLeave()`.
    public private(set) var activeGameRoute: Route?

    /// Drives the `.fullScreenCover(isPresented:)` binding in `GameRoot`.
    /// Separate from `activeGameRoute` so SwiftUI can animate the dismiss before
    /// the route is cleared.
    public private(set) var isGamePresented: Bool = false

    // MARK: - Game Center signed-out alert (#513 fix)

    /// `true` while the "Sign in to Game Center" alert is visible.
    /// Set by `HomeViewModel` / `MinesweeperHomeViewModel` (via injected binding)
    /// when the leaderboard card is tapped with GC signed out.
    /// Lives here (stable shared object) — not on the per-render HomeViewModel —
    /// so the SwiftUI `.alert` binding survives re-renders.
    public var showGameCenterSignedOutAlert: Bool = false

    // MARK: - Epic 2: Leave confirmation (SDD-003)

    /// `true` while the "Leave Game?" confirmation dialog is showing.
    /// Set by `requestLeave()`; cleared by `cancelLeave()` / `confirmLeave()`.
    public private(set) var isShowingLeaveConfirmation: Bool = false

    private let gameCenter: any GameCenterClient
    private let persistence: any PersistenceProtocol
    private let errorReporter: any ErrorReporter
    private let fetchResume: (() async throws -> ResumeCandidate<Route>?)?
    /// Called at the start of `confirmLeave()` before the modal is dismissed.
    /// Games inject a flush here so the last debounce window is reliably flushed
    /// even when the player confirms Leave within 500ms of the last move.
    /// `nil` → no pre-dismiss flush (same behaviour as before this rider).
    private let onBeforeLeave: (() async -> Void)?

    public init(
        gameCenter: any GameCenterClient,
        persistence: any PersistenceProtocol,
        errorReporter: any ErrorReporter = NoopErrorReporter(),
        fetchResume: (() async throws -> ResumeCandidate<Route>?)? = nil,
        onBeforeLeave: (() async -> Void)? = nil
    ) {
        self.gameCenter = gameCenter
        self.persistence = persistence
        self.errorReporter = errorReporter
        self.fetchResume = fetchResume
        self.onBeforeLeave = onBeforeLeave
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

    // MARK: - Epic 1: Modal presentation (SDD-003)

    /// Present a game board as a fullScreenCover modal. Called from per-app
    /// hub VMs (DailyHub / PracticeHub) when the player taps a board card.
    /// Replaces the former `path.append(boardRoute)` pattern.
    public func presentGame(route: Route) {
        activeGameRoute = route
        isGamePresented = true
    }

    /// Dismiss the modal game. Called by SwiftUI's `isPresented` binding setter
    /// (interactive dismiss — disabled for fullScreenCover, so this is only
    /// called by `confirmLeave()`). Safe to call when nothing is presented.
    public func dismissGame() {
        isGamePresented = false
        activeGameRoute = nil
    }

    // MARK: - Epic 2: Leave confirmation (SDD-003)

    /// Show the "Leave Game?" confirmation. Called by the `[X]` close button
    /// inside the modal board. Timer is unaffected — the game VM stays live.
    public func requestLeave() {
        isShowingLeaveConfirmation = true
    }

    /// User chose Cancel. Hide the confirmation; the game continues unchanged.
    public func cancelLeave() {
        isShowingLeaveConfirmation = false
    }

    /// User chose Leave. If `onBeforeLeave` is wired, awaits it first in a Task
    /// (SDD-003 rider: prevents the 500ms debounce window from being dropped on
    /// a fast Leave), then dismisses the modal. When no flush is injected the
    /// dismiss is synchronous — same behaviour as before this rider — so the
    /// existing test contract holds for nil-closure callers.
    /// The board's `.onDisappear` bare Task still fires afterward as a safety net.
    public func confirmLeave() {
        isShowingLeaveConfirmation = false
        if let onBeforeLeave {
            Task {
                await onBeforeLeave()
                dismissGame()
            }
        } else {
            dismissGame()
        }
    }
}
