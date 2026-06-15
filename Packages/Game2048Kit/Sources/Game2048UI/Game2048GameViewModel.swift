// Game2048GameViewModel — @MainActor @Observable bridge between the
// `Game2048Session` actor and SwiftUI's `Game2048BoardView`.
//
// Pattern mirrors MinesweeperGameViewModel exactly: the actor is the source of
// truth; the ViewModel caches the most recent snapshot and republishes it to
// the view tree after every `await` round-trip.
//
// M4 additions vs M3:
//   - Persistence seam: `store` + `recordName` optional pair (nil = no-op,
//     same backward-compat shape as MinesweeperGameViewModel).
//   - GC seam: `gameCenter` optional (nil = no-op submit, same MS pattern).
//   - `submitDailyScoreIfStuck()`: submits score to GC on stuck + mode==.daily.
//     OQ-004-3: stuck = natural end-of-run; score is the GC submission value.
//
// SDD-004 OQ-004-3 RESOLVED: stuck = natural end-of-run (no Failed state);
// `reachedTarget` feeds achievements only; Daily = high score on shared seed.

public import Observation
public import Game2048Engine
public import Game2048GameState
public import Game2048Persistence
public import GameCenterClient
public import Telemetry

@MainActor
@Observable
public final class Game2048GameViewModel {

    // MARK: - Session

    public let session: Game2048Session

    // MARK: - Game Center (#291 pattern)

    /// Score-leaderboard submit seam. `nil` in preview / test callsites (no-op).
    /// Production wires `LiveGameCenterClient` via composition root.
    private let gameCenter: (any GameCenterClient)?
    /// Funnel for swallowed submit failures.
    let errorReporter: (any ErrorReporter)?
    /// #329 pattern: gates the GC daily-board submit to daily-mode stucks.
    /// Defaults to `.practice` (most cautious: no submit).
    public let mode: GameMode
    /// Guards against double-submit if the snapshot re-publishes `.stuck`.
    private var didSubmitStuck = false
    /// Best-effort one-shot auth seam (mirrors MS pattern).
    private var didAttemptAuth = false

    // MARK: - Persistence (M4)

    /// Saved-game store seam. `nil` (preview / test) → no persistence side-effects.
    let store: Game2048SavedGameStore?
    /// The save's CloudKit identity, derived ONCE at board construction.
    let recordName: String?

    // MARK: - Snapshot / preview seam

    private let isSeeded: Bool

    // MARK: - Cached snapshot

    public private(set) var snapshot: Game2048SessionSnapshot

    // MARK: - Convenience accessors

    public var board: Board { snapshot.board }
    public var score: Int { snapshot.score }
    public var moveCount: Int { snapshot.moveCount }
    public var status: Game2048SessionStatus { snapshot.status }
    public var elapsedSeconds: Int { snapshot.elapsedSeconds }
    public var reachedTarget: Bool { snapshot.reachedTarget }

    public var isTerminal: Bool { status == .stuck }
    public var isPaused: Bool { status == .paused }

    // MARK: - Init

    /// Construct a fresh session from a seed.
    public convenience init(
        seed: UInt64 = 0,
        mode: GameMode = .practice,
        gameCenter: (any GameCenterClient)? = nil,
        errorReporter: (any ErrorReporter)? = nil,
        store: Game2048SavedGameStore? = nil,
        recordName: String? = nil
    ) {
        self.init(
            session: Game2048Session(seed: seed),
            mode: mode,
            gameCenter: gameCenter,
            errorReporter: errorReporter,
            store: store,
            recordName: recordName
        )
    }

    /// Construct from an existing session (resume, previews, composition).
    public init(
        session: Game2048Session,
        mode: GameMode = .practice,
        gameCenter: (any GameCenterClient)? = nil,
        errorReporter: (any ErrorReporter)? = nil,
        store: Game2048SavedGameStore? = nil,
        recordName: String? = nil
    ) {
        self.session = session
        self.mode = mode
        self.gameCenter = gameCenter
        self.errorReporter = errorReporter
        self.store = store
        self.recordName = recordName
        self.isSeeded = false
        self.snapshot = Game2048SessionSnapshot(
            seed: session.seed,
            board: Board(),
            score: 0,
            moveCount: 0,
            status: .playing,
            elapsedSeconds: 0,
            reachedTarget: false
        )
    }

    /// Snapshot / preview seam — installs a fixed snapshot, no-ops refresh/slide.
    public init(seeded snapshot: Game2048SessionSnapshot) {
        self.session = Game2048Session(seed: snapshot.seed)
        self.mode = .practice
        self.gameCenter = nil
        self.errorReporter = nil
        self.store = nil
        self.recordName = nil
        self.snapshot = snapshot
        self.isSeeded = true
    }

    // MARK: - Refresh

    public func refresh() async {
        guard !isSeeded else { return }
        snapshot = await session.snapshot()
    }

    // MARK: - Actions

    public func slide(_ direction: Direction) async {
        guard !isSeeded else { return }
        snapshot = await session.slide(direction)
        // OQ-004-3: stuck = end-of-run. Persist immediately on stuck.
        if snapshot.status == .stuck {
            await persistCurrentState()
            await submitDailyScoreIfStuck()
        }
    }

    // MARK: - Pause / resume

    public func pause() async {
        guard !isSeeded else { return }
        snapshot = await session.pause()
        await persistCurrentState()
    }

    public func resume() async {
        guard !isSeeded else { return }
        snapshot = await session.resume()
    }

    // MARK: - Persistence (M4)

    /// Persist the current board through the saved-game store. Called on:
    ///   - pause, stuck (above)
    ///   - scenePhase == .background, onDisappear (Game2048BoardView)
    /// No-ops when persistence seam isn't threaded, when seeded, or while
    /// the board is fresh (score == 0 && moveCount == 0 → nothing to resume).
    /// Failures funnel — a failed save never interrupts gameplay.
    public func persistCurrentState() async {
        guard !isSeeded, let store, let recordName else { return }
        // Skip a zero-information save (nothing useful to resume).
        guard snapshot.score > 0 || snapshot.moveCount > 0 else { return }
        do {
            try await store.save(snapshot, modeRaw: mode.rawValue, recordName: recordName)
        } catch {
            await errorReporter?.report(
                UserFacingError.classify(error),
                underlying: error,
                source: "Game2048GameViewModel.persistCurrentState"
            )
        }
    }

    // MARK: - Game Center (M4)

    /// Submit the score to the daily leaderboard the first time a daily-mode
    /// board reaches `.stuck`. OQ-004-3: stuck = natural end-of-run; score is
    /// the leaderboard metric (high score ranking).
    ///
    /// Note for M5 ASC config: configure the leaderboard with INTEGER format
    /// and "higher is better" — NOT ELAPSED_TIME. The `submitScore(leaderboardId:
    /// elapsedSeconds:)` call here uses `score` as the submitted value; the
    /// name `elapsedSeconds` in the protocol is a misnomer for 2048's use-case
    /// (the GameKit wire value is `score * 100` centiseconds — integers either
    /// way). This open question is tracked for the M5 ASC setup (OQ-GC-2048-1).
    private func submitDailyScoreIfStuck() async {
        guard snapshot.status == .stuck, !didSubmitStuck else { return }
        guard mode == .daily else { return }
        guard let gameCenter else { return }
        didSubmitStuck = true

        // Best-effort one-shot auth.
        if !didAttemptAuth {
            didAttemptAuth = true
            _ = try? await gameCenter.authenticate()
        }

        do {
            try await gameCenter.submitScore(
                leaderboardId: Game2048LeaderboardID.daily,
                elapsedSeconds: snapshot.score
            )
        } catch {
            await errorReporter?.report(
                UserFacingError.classify(error),
                underlying: error,
                source: "Game2048GameViewModel.submitDailyScore"
            )
        }
    }
}
