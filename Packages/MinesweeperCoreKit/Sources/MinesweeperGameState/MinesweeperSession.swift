// MinesweeperSession — actor owning a single Minesweeper game's mutable state.
//
// Wraps the value-type `MinesweeperEngine` from MinesweeperCoreKit and
// provides:
//
//   - Actor-isolated mutation (`reveal`, `toggleFlag`) returning a Sendable
//     snapshot for the UI to bind to.
//   - Lifecycle status `.idle / .playing / .won / .lost` driven by engine
//     win/lose detection.
//   - Elapsed-seconds clock that starts on first action and freezes on
//     terminal status (.won / .lost).
//
// Mirrors the SudokuCoreKit/GameState shape but trimmed for MVP scope —
// no telemetry, no undo, no notes, no persistence (per dispatch spec).

public import MinesweeperEngine
internal import Foundation

public actor MinesweeperSession {

    // MARK: - Immutable inputs

    // Immutable + Sendable — safe to expose without actor hop so callers
    // (e.g. the @MainActor view model) can read them synchronously.
    public nonisolated let difficulty: Difficulty
    public nonisolated let seed: UInt64

    // MARK: - Engine

    private var engine: MinesweeperEngine

    // MARK: - Lifecycle

    public private(set) var status: MinesweeperSessionStatus = .idle

    // MARK: - Clock

    private let clock: any MonotonicClock
    private var runningSince: TimeInterval?
    private var accumulatedSeconds: Int = 0

    /// Seconds elapsed while in `.playing`. Frozen in any non-playing state.
    public var elapsedSeconds: Int {
        if let runningSince {
            return accumulatedSeconds + Int(clock.now - runningSince)
        }
        return accumulatedSeconds
    }

    // MARK: - Init

    public init(
        difficulty: Difficulty,
        seed: UInt64,
        clock: any MonotonicClock = LiveMonotonicClock()
    ) {
        self.difficulty = difficulty
        self.seed = seed
        self.engine = MinesweeperEngine(difficulty: difficulty, seed: seed)
        self.clock = clock
    }

    // MARK: - Snapshot

    public func snapshot() -> MinesweeperSessionSnapshot {
        MinesweeperSessionSnapshot(
            difficulty: difficulty,
            seed: seed,
            cells: engine.cells,
            status: status,
            elapsedSeconds: elapsedSeconds,
            mineCount: engine.mineCount,
            flagCount: flagCount
        )
    }

    // MARK: - Restore (#455)

    /// Rebuild a session from a snapshot. Mirrors `GameSession.restore`:
    /// the engine is reconstructed from the snapshot's `seed` + `difficulty`
    /// (the same deterministic init path) and reinstated to the captured
    /// board (`cells`), so the mine layout is bit-identical to the original.
    /// The restored session is frozen — `elapsedSeconds` is fully captured in
    /// `accumulatedSeconds`, the clock does not auto-resume, and a restored
    /// `.playing` is normalized to `.paused` (matching Sudoku's
    /// `GameSession.applySnapshot`): a frozen `.playing` has no path back to a
    /// running span, so it is parked at `.paused` until an explicit `resume()`.
    public static func restore(
        from snapshot: MinesweeperSessionSnapshot,
        clock: any MonotonicClock = LiveMonotonicClock()
    ) async -> MinesweeperSession {
        let session = MinesweeperSession(
            difficulty: snapshot.difficulty,
            seed: snapshot.seed,
            clock: clock
        )
        await session.applySnapshot(snapshot)
        return session
    }

    /// Actor-isolated restore step. Reinstates the captured board into a fresh
    /// engine (same deterministic seed/difficulty init) and freezes the clock.
    private func applySnapshot(_ snapshot: MinesweeperSessionSnapshot) {
        let minesPlaced = snapshot.cells.contains { $0.isMine }
        engine = MinesweeperEngine(
            difficulty: snapshot.difficulty,
            seed: snapshot.seed,
            cells: snapshot.cells,
            minesPlaced: minesPlaced,
            isLost: snapshot.status == .lost
        )
        // A restored session is always frozen: a restored `.playing` is parked
        // at `.paused` (no running span) so `resume()` can re-arm the clock.
        status = snapshot.status == .playing ? .paused : snapshot.status
        accumulatedSeconds = snapshot.elapsedSeconds
        runningSince = nil
    }

    private var flagCount: Int {
        var count = 0
        for cell in engine.cells where cell.state == .flagged { count += 1 }
        return count
    }

    // MARK: - Actions

    /// Reveal the cell at (row, col). First reveal also starts the clock.
    /// Returns the post-action snapshot.
    @discardableResult
    public func reveal(row: Int, col: Int) throws -> MinesweeperSessionSnapshot {
        guard status == .idle || status == .playing else { return snapshot() }
        // Engine mutation first — if it throws (e.g. OOB) we leave status
        // untouched so a bad call from a misbehaving caller cannot start
        // the clock or transition .idle → .playing.
        try engine.reveal(row: row, col: col)
        try ensurePlaying()
        updateStatusFromEngine()
        return snapshot()
    }

    /// Toggle the flag at (row, col). Also starts the clock (first action
    /// can be a flag — matches engine semantics where flagging a hidden cell
    /// pre-first-reveal is legal and doesn't trigger mine placement).
    /// Returns the post-action snapshot.
    @discardableResult
    public func toggleFlag(row: Int, col: Int) throws -> MinesweeperSessionSnapshot {
        guard status == .idle || status == .playing else { return snapshot() }
        // Engine mutation first; see `reveal` for rationale.
        try engine.toggleFlag(row: row, col: col)
        try ensurePlaying()
        updateStatusFromEngine()
        return snapshot()
    }

    // MARK: - Pause / resume (#434)

    /// Pause an in-progress game: freeze the elapsed clock and move to
    /// `.paused`. No-op unless currently `.playing` (idle / terminal / already
    /// paused are left untouched). Mirrors Sudoku's `GameSession.pause()`.
    /// Returns the post-action snapshot.
    @discardableResult
    public func pause() -> MinesweeperSessionSnapshot {
        guard status == .playing else { return snapshot() }
        freezeRunningClock()
        status = .paused
        return snapshot()
    }

    /// Resume a paused game: restart the running-span clock from now and move
    /// back to `.playing`. No-op unless currently `.paused`. Mirrors Sudoku's
    /// `GameSession.resume()`. Returns the post-action snapshot.
    @discardableResult
    public func resume() -> MinesweeperSessionSnapshot {
        guard status == .paused else { return snapshot() }
        runningSince = clock.now
        status = .playing
        return snapshot()
    }

    // MARK: - Internal

    /// Promote `.idle` to `.playing` and start the running-span clock on
    /// the first action. Idempotent if already `.playing`.
    private func ensurePlaying() throws {
        if status == .idle {
            status = .playing
            runningSince = clock.now
        }
    }

    /// Roll the running span into `accumulatedSeconds`. Idempotent.
    private func freezeRunningClock() {
        if let runningSince {
            accumulatedSeconds += Int(clock.now - runningSince)
            self.runningSince = nil
        }
    }

    /// Read win/lose flags from the engine and transition status. Freezes
    /// the clock on any terminal status.
    private func updateStatusFromEngine() {
        if engine.isLost {
            status = .lost
            freezeRunningClock()
        } else if engine.isWon {
            status = .won
            freezeRunningClock()
        }
    }
}
