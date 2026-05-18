// GameSession — actor owning a single game's mutable state.
//
// Design choice (per docs/design.md §How.5.4 + plan.md Phase 3 dispatch):
//
//   We use `actor GameSession` (NOT `final class @unchecked Sendable`) for
//   Swift 6 strict-concurrency cleanliness. The Phase-8 `GameViewModel` is
//   `@Observable @MainActor` and bridges into this actor with `await`. A
//   value-type `struct GameSession` was considered but rejected: the undo
//   stack + notes side-table mutate together with the board, and an actor
//   makes the resulting "transaction" atomic without manual locking.
//
// Imports: ONLY Foundation + SudokuEngine. No Apple framework imports.

import Foundation
public import SudokuEngine

public actor GameSession {

    // MARK: - Immutable inputs

    public let puzzle: Puzzle

    // MARK: - Lifecycle state

    public private(set) var status: GameSessionStatus = .idle

    // MARK: - Working state

    /// The mutable board the player is editing. Initialized to `puzzle.clues`.
    public private(set) var currentBoard: Board

    /// Pencil-mark side table. Not part of the Move-based undo stack.
    public private(set) var notes: NotesGrid = NotesGrid()

    /// Bounded (cap 20) undo / redo timeline of `placeDigit` moves.
    public private(set) var undoStack: UndoStack = UndoStack()

    // MARK: - Telemetry + Clock

    private let telemetry: any GameStateTelemetry
    private let clock: any MonotonicClock

    // MARK: - Elapsed-time accounting

    /// Wall-clock instant (seconds) when the current .playing span began.
    /// nil whenever the session is not actively running (idle / paused /
    /// completed / abandoned).
    private var runningSince: TimeInterval?
    /// Sum of completed .playing spans, in whole seconds.
    private var accumulatedSeconds: Int = 0

    /// Total elapsed playing time, frozen while paused / completed / abandoned.
    /// §How.7.2: pause freezes the clock.
    public var elapsedSeconds: Int {
        if let runningSince {
            return accumulatedSeconds + Int(clock.now - runningSince)
        }
        return accumulatedSeconds
    }

    // MARK: - Init

    public init(
        puzzle: Puzzle,
        clock: any MonotonicClock = LiveMonotonicClock(),
        telemetry: any GameStateTelemetry = NoOpGameStateTelemetry()
    ) {
        self.puzzle = puzzle
        self.currentBoard = puzzle.clues
        self.clock = clock
        self.telemetry = telemetry
    }

    // MARK: - Transitions

    public func start() async throws {
        try transition(.start)
        runningSince = clock.now
        await telemetry.dispatch(.sessionStarted)
    }

    public func pause() async throws {
        try transition(.pause)
        freezeRunningClock()
        await telemetry.dispatch(.sessionPaused)
    }

    public func resume() async throws {
        try transition(.resume)
        runningSince = clock.now
        await telemetry.dispatch(.sessionResumed)
    }

    public func complete() async throws {
        try transition(.complete)
        freezeRunningClock()
        await telemetry.dispatch(.sessionCompleted(elapsedSeconds: accumulatedSeconds))
    }

    public func abandon() async throws {
        try transition(.abandon)
        freezeRunningClock()
        await telemetry.dispatch(.sessionAbandoned)
    }

    // MARK: - Play

    /// Place a digit (1...9) in a non-clue cell. Pushes the move onto the
    /// undo stack with the cell's prior digit captured BEFORE the write
    /// (Phase 2 follow-up #3). Triggers completion if the board is now
    /// solved.
    public func placeDigit(row: Int, col: Int, digit: Int) async throws {
        guard status == .playing else {
            throw GameSessionError.invalidStateForAction(status: status)
        }
        guard (0..<Board.dimension).contains(row),
              (0..<Board.dimension).contains(col),
              (1...9).contains(digit) else {
            throw GameSessionError.outOfRange
        }
        let index = Board.index(row: row, column: col)
        if currentBoard.givenMask[index] {
            throw GameSessionError.cellImmutable(row: row, col: col)
        }

        // CRITICAL (Phase 2 follow-up #3): capture previous value BEFORE write.
        let previous = currentBoard.digit(atIndex: index)

        try currentBoard.setDigit(digit, atRow: row, column: col)
        undoStack.push(.placeDigit(row: row, col: col, digit: digit, previous: previous))

        await telemetry.dispatch(.digitPlaced(row: row, col: col, digit: digit, previous: previous))

        // Sticky completion: once the board matches the solution, transition
        // .playing -> .completed. Subsequent undo does NOT reopen the game
        // (documented behavior: completion is sticky).
        if currentBoard.cells == puzzle.solution.cells {
            try transition(.complete)
            freezeRunningClock()
            await telemetry.dispatch(.sessionCompleted(elapsedSeconds: accumulatedSeconds))
        }
    }

    /// Toggle a pencil note (1...9) in a non-clue cell.
    public func toggleNote(row: Int, col: Int, digit: Int) async throws {
        guard status == .playing else {
            throw GameSessionError.invalidStateForAction(status: status)
        }
        guard (0..<Board.dimension).contains(row),
              (0..<Board.dimension).contains(col),
              (1...9).contains(digit) else {
            throw GameSessionError.outOfRange
        }
        let index = Board.index(row: row, column: col)
        if currentBoard.givenMask[index] {
            throw GameSessionError.cellImmutable(row: row, col: col)
        }
        let added = notes.toggle(digit: digit, row: row, col: col)
        await telemetry.dispatch(.noteToggled(row: row, col: col, digit: digit, added: added))
    }

    /// Undo the most recent `placeDigit` move. No-op if the stack is empty.
    public func undo() async throws {
        guard status == .playing else {
            throw GameSessionError.invalidStateForAction(status: status)
        }
        guard let move = undoStack.undo() else { return }
        try revert(move)
        await telemetry.dispatch(.moveUndone)
    }

    /// Redo the most recently undone move.
    public func redo() async throws {
        guard status == .playing else {
            throw GameSessionError.invalidStateForAction(status: status)
        }
        guard let move = undoStack.redo() else { return }
        try reapply(move)
        await telemetry.dispatch(.moveRedone)
    }

    // MARK: - Snapshot / restore

    /// Capture the full session state as a serializable value.
    public func snapshot() -> GameSessionSnapshot {
        GameSessionSnapshot(
            puzzle: puzzle,
            currentBoard: currentBoard,
            status: status,
            elapsedSeconds: elapsedSeconds,
            undoMoves: undoStack.undoStack,
            redoMoves: undoStack.redoStack,
            notes: notes
        )
    }

    /// Rebuild a session from a snapshot. The restored session is "frozen"
    /// in whatever status the snapshot recorded; the wall clock does not
    /// auto-resume — `elapsedSeconds` is fully captured in
    /// `accumulatedSeconds` and a subsequent `resume()` opens a new span.
    public static func restore(
        from snapshot: GameSessionSnapshot,
        clock: any MonotonicClock = LiveMonotonicClock(),
        telemetry: any GameStateTelemetry = NoOpGameStateTelemetry()
    ) async -> GameSession {
        let session = GameSession(puzzle: snapshot.puzzle, clock: clock, telemetry: telemetry)
        await session.applySnapshot(snapshot)
        return session
    }

    /// Actor-isolated restore step. Reconstructs the undo/redo halves by
    /// pushing all undo moves, then synthetically routing each redo move
    /// through `push → undo` so it lands on the redo stack in order
    /// (UndoStack's only public mutators are `push` / `undo` / `redo`).
    private func applySnapshot(_ snapshot: GameSessionSnapshot) {
        currentBoard = snapshot.currentBoard
        status = snapshot.status
        notes = snapshot.notes
        accumulatedSeconds = snapshot.elapsedSeconds
        runningSince = nil

        // Reconstruct the undo/redo split using only the public API
        // (`push` / `undo`). Strategy: push undoMoves in order, then push
        // redoMoves in reverse, then `undo` exactly `redoMoves.count`
        // times — this lands the redo half on top of redoStack in the
        // original order. (UndoStack's `push` clears redo, so any naive
        // alternating push/undo loop would lose prior redo entries.)
        var stack = UndoStack()
        for move in snapshot.undoMoves {
            stack.push(move)
        }
        for move in snapshot.redoMoves.reversed() {
            stack.push(move)
        }
        for _ in 0..<snapshot.redoMoves.count {
            _ = stack.undo()
        }
        undoStack = stack
    }

    // MARK: - Internal

    /// Roll the currently-running playing-span into `accumulatedSeconds`
    /// and clear `runningSince`. Idempotent if not running.
    private func freezeRunningClock() {
        if let runningSince {
            accumulatedSeconds += Int(clock.now - runningSince)
            self.runningSince = nil
        }
    }

    private func transition(_ transition: GameSessionTransition) throws {
        guard let next = status.applying(transition) else {
            throw GameSessionError.illegalTransition(from: status, applying: transition)
        }
        status = next
    }

    private func revert(_ move: Move) throws {
        switch move {
        case let .placeDigit(row, col, _, previous):
            try currentBoard.setDigit(previous, atRow: row, column: col)
        }
    }

    private func reapply(_ move: Move) throws {
        switch move {
        case let .placeDigit(row, col, digit, _):
            try currentBoard.setDigit(digit, atRow: row, column: col)
        }
    }
}
