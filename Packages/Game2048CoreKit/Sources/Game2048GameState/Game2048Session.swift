// Game2048Session — actor owning a single 2048 game's mutable state.
//
// Wraps the value-type Board from Game2048Engine and provides:
//
//   - Actor-isolated mutation (`slide(_:)`) returning a Sendable snapshot.
//   - After each legal slide, one tile is spawned via SplitMix64.
//   - Lifecycle: .playing / .paused / .stuck (no legal move).
//   - Elapsed-seconds clock that starts on the first legal slide and freezes
//     when stuck or while paused.
//   - `reachedTarget` latch: set to true the first time any tile reaches 2048;
//     play continues — 2048 has no forced win-terminal.
//   - Snapshot / restore round-trip for future persistence (#455 pattern).
//
// Mirrors MinesweeperSession's shape exactly (same clock pattern, same
// pause/resume, same restore static factory).

public import Game2048Engine
internal import Foundation

public actor Game2048Session {

    // MARK: - Immutable inputs

    public nonisolated let seed: UInt64

    // MARK: - Mutable state

    private var board: Board
    private var score: Int = 0
    private var moveCount: Int = 0
    private var rng: SplitMix64
    private var reachedTarget: Bool = false
    public private(set) var status: Game2048SessionStatus = .playing

    // MARK: - Clock

    private let clock: any MonotonicClock
    private var runningSince: TimeInterval?
    private var accumulatedSeconds: Int = 0

    /// Seconds elapsed while `.playing`. Frozen in any non-playing state.
    public var elapsedSeconds: Int {
        if let runningSince {
            return accumulatedSeconds + Int(clock.now - runningSince)
        }
        return accumulatedSeconds
    }

    // MARK: - Init

    /// Create a fresh session from `seed`. Two tiles are spawned immediately
    /// so the board is never empty at game start.
    public init(seed: UInt64, clock: any MonotonicClock = LiveMonotonicClock()) {
        self.seed = seed
        self.clock = clock
        self.rng = SplitMix64(seed: seed)
        var initialBoard = Board()
        // Spawn two tiles to populate the starting board.
        (initialBoard, _, _) = Spawn.spawnTile(onto: initialBoard, rng: &self.rng)
        (initialBoard, _, _) = Spawn.spawnTile(onto: initialBoard, rng: &self.rng)
        self.board = initialBoard
        // Start the clock immediately (2048 starts in .playing, no idle state).
        self.runningSince = clock.now
    }

    // MARK: - Snapshot

    public func snapshot() -> Game2048SessionSnapshot {
        Game2048SessionSnapshot(
            seed: seed,
            board: board,
            score: score,
            moveCount: moveCount,
            status: status,
            elapsedSeconds: elapsedSeconds,
            reachedTarget: reachedTarget
        )
    }

    // MARK: - Restore

    /// Rebuild a session from a persisted snapshot. The restored session is
    /// always parked at `.paused` (a restored `.playing` has no running span;
    /// call `resume()` to re-arm the clock). Mirrors MinesweeperSession.restore.
    public static func restore(
        from snap: Game2048SessionSnapshot,
        clock: any MonotonicClock = LiveMonotonicClock()
    ) async -> Game2048Session {
        let session = Game2048Session(rawSeed: snap.seed, clock: clock)
        await session.applySnapshot(snap)
        return session
    }

    /// Private init that does NOT spawn initial tiles (used by restore).
    private init(rawSeed: UInt64, clock: any MonotonicClock) {
        self.seed = rawSeed
        self.clock = clock
        self.rng = SplitMix64(seed: rawSeed)
        self.board = Board()
        self.runningSince = nil  // not started
    }

    private func applySnapshot(_ snap: Game2048SessionSnapshot) {
        board = snap.board
        score = snap.score
        moveCount = snap.moveCount
        reachedTarget = snap.reachedTarget
        accumulatedSeconds = snap.elapsedSeconds
        runningSince = nil
        // A restored .playing is parked at .paused (clock not running).
        status = snap.status == .playing ? .paused : snap.status
    }

    // MARK: - Actions

    /// Attempt a slide in `direction`. Returns the post-action snapshot.
    /// - If the move is legal: slides, merges, spawns a new tile, updates score/count.
    /// - If the move is illegal (no board change): returns snapshot unchanged.
    /// - If the session is not `.playing`: returns snapshot unchanged.
    @discardableResult
    public func slide(_ direction: Direction) -> Game2048SessionSnapshot {
        guard status == .playing else { return snapshot() }
        guard let result = MoveEngine.apply(direction, to: board) else {
            return snapshot()  // illegal move — no spawn
        }
        board = result.board
        score += result.scoreDelta
        moveCount += 1
        if result.board.containsTarget { reachedTarget = true }
        // Spawn one tile after every legal move.
        (board, _, _) = Spawn.spawnTile(onto: board, rng: &rng)
        // Check for stuck condition.
        if !MoveEngine.hasLegalMove(on: board) {
            status = .stuck
            freezeRunningClock()
        }
        return snapshot()
    }

    // MARK: - Pause / resume

    /// Pause an in-progress game. No-op unless `.playing`. Returns snapshot.
    @discardableResult
    public func pause() -> Game2048SessionSnapshot {
        guard status == .playing else { return snapshot() }
        freezeRunningClock()
        status = .paused
        return snapshot()
    }

    /// Resume a paused game. No-op unless `.paused`. Returns snapshot.
    @discardableResult
    public func resume() -> Game2048SessionSnapshot {
        guard status == .paused else { return snapshot() }
        runningSince = clock.now
        status = .playing
        return snapshot()
    }

    // MARK: - Internal clock helpers

    private func freezeRunningClock() {
        if let since = runningSince {
            accumulatedSeconds += Int(clock.now - since)
            runningSince = nil
        }
    }
}
