// MinesweeperRootViewModel — coordinates Minesweeper app-launch bootstrap.
//
// Mirrors `SudokuUI.RootViewModel` (issue #313): owns the launch-time
// CloudKit-zone provisioning (`PersistenceProtocol.bootstrap`) + Game Center
// auth handshake (`GameCenterClient.authenticate`), both kicked off from
// `MinesweeperRoot`'s `.task`. The resume-candidate fetch
// (`latestInProgress()`) is NOT mirrored — Minesweeper has no saved-game /
// resume flow yet (issue #448 item ①, out of scope here).
//
// Errors from either fetch are swallowed and funneled through `ErrorReporter`
// — both bootstrap and GC auth are optional and Root must never block
// gameplay (mirrors Sudoku's RootViewModel bootstrap exactly).

public import GameCenterClient
public import Persistence
public import Telemetry
public import SwiftUI

@MainActor
@Observable
public final class MinesweeperRootViewModel {

    public private(set) var authState: GameCenterAuthState = .unknown
    public private(set) var hasBootstrapped: Bool = false

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
    /// not re-trigger GameKit auth. Mirrors `SudokuUI.RootViewModel.bootstrap`.
    public func bootstrap() async {
        guard !hasBootstrapped else { return }
        hasBootstrapped = true

        // Issue #448: CloudKit zone provisioning. Must run so AdGate's
        // `LiveMonetizationStateStore.loadState()` can seed the first-launch
        // record (fresh iCloud accounts otherwise hit zoneNotFound, and AdGate
        // conservatively suppresses the Home banner). Failures funnel through
        // `errorReporter`; bootstrap is idempotent + non-blocking, so a
        // transient failure retries next launch and must not block Root.
        // Mirrors `RootViewModel.bootstrap.persistence`.
        do {
            try await persistence.bootstrap()
        } catch {
            await errorReporter.report(
                UserFacingError.classify(error),
                underlying: error,
                source: "MinesweeperRootViewModel.bootstrap.persistence"
            )
        }

        do {
            self.authState = try await gameCenter.authenticate()
        } catch {
            // Authentication failure must still degrade to `.unauthenticated`
            // (never block launch — Game Center is optional), but the
            // underlying error travels through the funnel so OSLog / telemetry
            // record what actually went wrong instead of silently masking.
            // Mirrors `RootViewModel.bootstrap.authenticate`.
            self.authState = .unauthenticated
            await errorReporter.report(
                .gameCenterUnauthenticated,
                underlying: error,
                source: "MinesweeperRootViewModel.bootstrap.authenticate"
            )
        }
    }
}
