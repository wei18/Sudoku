// MinesweeperRootViewModel — coordinates Minesweeper app-launch bootstrap.
//
// Mirrors `SudokuUI.RootViewModel` (issue #313): owns the launch-time Game
// Center auth handshake (`GameCenterClient.authenticate`) kicked off from
// `MinesweeperRoot`'s `.task`. Unlike Sudoku's RootViewModel this does NOT
// run `persistence.bootstrap()` or fetch a resume candidate — Minesweeper has
// no saved-game / resume flow yet (no ResumePill in MinesweeperRoot), so the
// only launch IO to mirror is the GC auth.
//
// Errors from the auth handshake are swallowed into `.unauthenticated` and
// funneled through `ErrorReporter` — Game Center is optional and Root must
// never block gameplay (mirrors Sudoku's RootViewModel auth block exactly).

public import GameCenterClient
public import Telemetry
public import SwiftUI

@MainActor
@Observable
public final class MinesweeperRootViewModel {

    public private(set) var authState: GameCenterAuthState = .unknown
    public private(set) var hasBootstrapped: Bool = false

    private let gameCenter: any GameCenterClient
    private let errorReporter: any ErrorReporter

    public init(
        gameCenter: any GameCenterClient,
        errorReporter: any ErrorReporter = NoopErrorReporter()
    ) {
        self.gameCenter = gameCenter
        self.errorReporter = errorReporter
    }

    /// Idempotent: only the first call performs IO; subsequent calls return
    /// immediately so View `.task` re-entries (size-class changes etc.) do
    /// not re-trigger GameKit auth. Mirrors `SudokuUI.RootViewModel.bootstrap`.
    public func bootstrap() async {
        guard !hasBootstrapped else { return }
        hasBootstrapped = true

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
