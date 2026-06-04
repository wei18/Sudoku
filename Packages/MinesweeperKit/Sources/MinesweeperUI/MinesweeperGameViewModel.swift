// MinesweeperGameViewModel — @MainActor @Observable bridge between the
// `MinesweeperSession` actor and SwiftUI's `MinesweeperBoardView`.
//
// Pattern mirrors Sudoku's GameViewModel: the actor is the source of truth;
// the ViewModel caches the most recent snapshot and republishes it to the
// view tree after every `await` round-trip.
//
// MVP scope: no telemetry, no undo, no persistence (per dispatch spec).

import IssueReporting
public import GameCenterClient
public import MinesweeperEngine
public import MinesweeperGameState
public import Observation
public import Telemetry

@MainActor
@Observable
public final class MinesweeperGameViewModel {

    // MARK: - Session

    public let session: MinesweeperSession

    // MARK: - Game Center (#291)

    /// Best-time leaderboard submit seam. `nil` in MVP / preview callsites
    /// (no-op); production wires the shared `LiveGameCenterClient`. Submit is
    /// best-effort and never blocks or crashes gameplay (mirrors Sudoku's
    /// `GameCenterSink` no-retry, swallowed-error policy).
    private let gameCenter: (any GameCenterClient)?
    /// Funnel for swallowed submit failures, so a failed leaderboard write is
    /// observable in OSLog instead of silent. `nil` → fully silent.
    private let errorReporter: (any ErrorReporter)?
    /// Guards against a double-submit if the snapshot re-publishes `.won`.
    private var didSubmitWin = false
    /// Best-effort one-shot auth so an unauthenticated player's first win
    /// still has a chance to land server-side. Mirrors Sudoku, where the
    /// native dashboard / `RootView.task` performs the handshake.
    private var didAttemptAuth = false

    // MARK: - Cached snapshot

    public private(set) var snapshot: MinesweeperSessionSnapshot

    // MARK: - Convenience accessors (read-only projections of snapshot)

    public var rows: Int { snapshot.rows }
    public var columns: Int { snapshot.columns }
    public var cells: [Cell] { snapshot.cells }
    public var status: MinesweeperSessionStatus { snapshot.status }
    public var mineCount: Int { snapshot.mineCount }
    public var flagCount: Int { snapshot.flagCount }
    public var elapsedSeconds: Int { snapshot.elapsedSeconds }
    public var remainingMineCount: Int { max(0, mineCount - flagCount) }

    public var isTerminal: Bool { status == .won || status == .lost }

    // MARK: - Init

    /// Construct a fresh session from a difficulty + seed. Use this for
    /// most cases; the underlying actor is created internally.
    public convenience init(
        difficulty: Difficulty = .beginner,
        seed: UInt64 = 0,
        gameCenter: (any GameCenterClient)? = nil,
        errorReporter: (any ErrorReporter)? = nil
    ) {
        self.init(
            session: MinesweeperSession(difficulty: difficulty, seed: seed),
            gameCenter: gameCenter,
            errorReporter: errorReporter
        )
    }

    /// Construct from an existing session. The view model derives its
    /// `difficulty` from `session.difficulty` so the two cannot disagree.
    public init(
        session: MinesweeperSession,
        gameCenter: (any GameCenterClient)? = nil,
        errorReporter: (any ErrorReporter)? = nil
    ) {
        self.session = session
        self.gameCenter = gameCenter
        self.errorReporter = errorReporter
        let difficulty = session.difficulty
        // Synchronous bootstrap: snapshot before any action is just the
        // immutable initial state — we mirror it locally so SwiftUI has
        // something to render before the first action.
        self.snapshot = MinesweeperSessionSnapshot(
            difficulty: difficulty,
            cells: Array(repeating: Cell(), count: difficulty.cellCount),
            status: .idle,
            elapsedSeconds: 0,
            mineCount: difficulty.mineCount,
            flagCount: 0
        )
    }

    // MARK: - Refresh

    /// Pull the latest snapshot from the actor (e.g. for elapsed-time ticks).
    public func refresh() async {
        snapshot = await session.snapshot()
        await submitBestTimeIfWon()
    }

    // MARK: - Actions

    public func cell(row: Int, col: Int) -> Cell {
        snapshot.cell(row: row, col: col)
    }

    public func reveal(row: Int, col: Int) async {
        do {
            snapshot = try await session.reveal(row: row, col: col)
        } catch {
            // MVP: out-of-bounds shouldn't happen from a well-formed grid view.
            // Swallow — the ViewModel state stays consistent with the last
            // successful snapshot. #178: surface the invariant violation in
            // test / #Preview (non-fatal in release).
            reportIssue("reveal out-of-bounds from well-formed grid: \(error)")
        }
        // #291: a reveal is the only action that can transition to `.won`
        // (flagging never wins). Submit the best time once we cross into the
        // won state.
        await submitBestTimeIfWon()
    }

    public func toggleFlag(row: Int, col: Int) async {
        do {
            snapshot = try await session.toggleFlag(row: row, col: col)
        } catch {
            // See `reveal`. #178: surface the invariant violation.
            reportIssue("toggleFlag out-of-bounds from well-formed grid: \(error)")
        }
    }

    // MARK: - Game Center submit-on-win (#291)

    /// Submit the elapsed time to this difficulty's best-time leaderboard the
    /// first time the board reaches `.won`. Best-effort: a `nil` client is a
    /// no-op (MVP / preview), an unauthenticated player's submit no-ops
    /// server-side, and any thrown error is funneled (never re-raised) so a
    /// failed leaderboard write can never interrupt the win moment.
    private func submitBestTimeIfWon() async {
        guard snapshot.status == .won, !didSubmitWin else { return }
        guard let gameCenter else { return }
        // Latch before the await so a re-entrant refresh tick can't double-fire.
        didSubmitWin = true

        let leaderboardId = MinesweeperLeaderboardID.daily(for: session.difficulty)
        let elapsed = snapshot.elapsedSeconds

        // Best-effort one-shot auth: the native GC dashboard normally performs
        // the handshake, but a player who wins before ever opening it would
        // otherwise submit while unauthenticated. Swallow the result.
        if !didAttemptAuth {
            didAttemptAuth = true
            _ = try? await gameCenter.authenticate()
        }

        do {
            try await gameCenter.submitScore(
                leaderboardId: leaderboardId,
                elapsedSeconds: elapsed
            )
        } catch {
            // No-retry policy mirrors Sudoku's GameCenterSink (§How.3.4):
            // GC is the leaderboard "炫耀面" only; the durable record lives
            // elsewhere. Funnel so the failure is observable in OSLog.
            await errorReporter?.report(
                UserFacingError.classify(error),
                underlying: error,
                source: "MinesweeperGameViewModel.submitBestTime"
            )
        }
    }
}
