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
}
