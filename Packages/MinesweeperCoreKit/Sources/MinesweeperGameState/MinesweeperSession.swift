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
            cells: engine.cells,
            status: status,
            elapsedSeconds: elapsedSeconds,
            mineCount: engine.mineCount,
            flagCount: flagCount
        )
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
