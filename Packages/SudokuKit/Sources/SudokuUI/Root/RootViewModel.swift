// RootViewModel — coordinates app-launch bootstrap.
//
// Per docs/v1/design.md §How.5.4 (VM ownership / @Observable @MainActor). Owns the
// auth handshake (`GameCenterClient.authenticate`) and the resume-candidate
// fetch (`PersistenceProtocol.latestInProgress`). Both are kicked off in
// `bootstrap()` from the View's `.task`.
//
// Errors from either fetch are swallowed into degraded states — Root should
// never block Home (docs/v1/design.md §How.5.1: "Bootstrap never blocks Home").

public import Foundation
public import GameCenterClient
public import Persistence
public import Telemetry

@MainActor
@Observable
public final class RootViewModel {

    public private(set) var authState: GameCenterAuthState = .unknown
    public private(set) var resumeCandidate: SavedGameSummary?
    public private(set) var hasBootstrapped: Bool = false
    public var path: [AppRoute] = []

    private let gameCenter: any GameCenterClient
    private let persistence: any PersistenceProtocol
    private let errorReporter: any ErrorReporter

    public init(
        gameCenter: any GameCenterClient,
        persistence: any PersistenceProtocol,
        errorReporter: any ErrorReporter = NoopErrorReporter()
    ) {
        self.gameCenter = gameCenter
        self.persistence = persistence
        self.errorReporter = errorReporter
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
                source: "RootViewModel.bootstrap.persistence"
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
                source: "RootViewModel.bootstrap.authenticate"
            )
        }

        // M10 (issue #67): replace `try?` swallow with funnel report. nil
        // resume candidate remains valid (no in-flight game); only catch +
        // route the *failure* — not the absence of data.
        do {
            self.resumeCandidate = try await persistence.latestInProgress()
        } catch {
            self.resumeCandidate = nil
            await errorReporter.report(
                UserFacingError.classify(error),
                underlying: error,
                source: "RootViewModel.bootstrap.latestInProgress"
            )
        }
    }

    public func resumeTapped() {
        guard let candidate = resumeCandidate else { return }
        path.append(.board(puzzleId: candidate.puzzleId))
    }
}
