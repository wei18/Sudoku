// GameRootViewModel — game-agnostic app-launch bootstrap coordinator (#448 step 1a).
//
// Per docs/v1/design.md §How.5.4 (VM ownership / @Observable @MainActor). Owns the
// auth handshake (`GameCenterClient.authenticate`) and the resume-candidate
// fetch (`PersistenceProtocol.latestInProgress`). Both are kicked off in
// `bootstrap()` from the View's `.task`.
//
// Errors from either fetch are swallowed into degraded states — Root should
// never block Home (docs/v1/design.md §How.5.1: "Bootstrap never blocks Home").
//
// Generalized out of `SudokuUI.RootViewModel` (and the byte-identical
// `MinesweeperUI.MinesweeperRootViewModel`): the only game-specific bits are
// the `path` element type — a per-app `Route` enum — and how `resumeTapped()`
// builds a board route from a `SavedGameSummary`. Both are injected: `Route`
// as the generic parameter, the resume mapping as the `resumeRoute` closure.
// Games that have no resume surface omit `resumeRoute` (it defaults to nil) to
// skip the `latestInProgress()` fetch and no-op `resumeTapped()` — the closure
// presence alone (`resumeRoute != nil`) implies resume is supported.

public import Foundation
public import GameCenterClient
public import Persistence
public import Telemetry

@MainActor
@Observable
public final class GameRootViewModel<Route: Hashable> {

    public private(set) var authState: GameCenterAuthState = .unknown
    public private(set) var resumeCandidate: SavedGameSummary?
    public private(set) var hasBootstrapped: Bool = false
    public var path: [Route] = []

    private let gameCenter: any GameCenterClient
    private let persistence: any PersistenceProtocol
    private let errorReporter: any ErrorReporter
    private let resumeRoute: ((SavedGameSummary) -> Route)?

    /// Resume is supported iff a `resumeRoute` mapping was supplied. Games with
    /// no resume surface (e.g. Minesweeper, which can't build its board route
    /// from a `SavedGameSummary` yet) omit the closure → this is false.
    private var supportsResume: Bool { resumeRoute != nil }

    public init(
        gameCenter: any GameCenterClient,
        persistence: any PersistenceProtocol,
        errorReporter: any ErrorReporter = NoopErrorReporter(),
        resumeRoute: ((SavedGameSummary) -> Route)? = nil
    ) {
        self.gameCenter = gameCenter
        self.persistence = persistence
        self.errorReporter = errorReporter
        self.resumeRoute = resumeRoute
    }

    /// Idempotent: only the first call performs IO; subsequent calls return
    /// immediately so View `.task` re-entries (size-class changes etc.) do
    /// not re-trigger GameKit auth.
    public func bootstrap() async {
        guard !hasBootstrapped else { return }
        hasBootstrapped = true

        // Issue #196: CloudKit zone + subscription provisioning. Must run
        // before `latestInProgress()` below — fresh iCloud accounts otherwise
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

        // M10 (issue #67): replace `try?` swallow with funnel report. nil
        // resume candidate remains valid (no in-flight game); only catch +
        // route the *failure* — not the absence of data.
        guard supportsResume else { return }
        do {
            self.resumeCandidate = try await persistence.latestInProgress()
        } catch {
            self.resumeCandidate = nil
            await errorReporter.report(
                UserFacingError.classify(error),
                underlying: error,
                source: "GameRootViewModel.bootstrap.latestInProgress"
            )
        }
    }

    public func resumeTapped() {
        guard let resumeRoute, let candidate = resumeCandidate else { return }
        path.append(resumeRoute(candidate))
    }
}
