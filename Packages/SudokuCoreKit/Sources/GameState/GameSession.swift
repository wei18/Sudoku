// GameSession — actor owning a single game's mutable state.
//
// Design choice (per docs/v1/design.md §How.5.4 + plan.md Phase 3 dispatch):
//
//   We use `actor GameSession` (NOT `final class @unchecked Sendable`) for
//   Swift 6 strict-concurrency cleanliness. The Phase-8 `GameViewModel` is
//   `@Observable @MainActor` and bridges into this actor with `await`. A
//   value-type `struct GameSession` was considered but rejected: the undo
//   stack + notes side-table mutate together with the board, and an actor
//   makes the resulting "transaction" atomic without manual locking.
//
// Imports: ONLY Foundation + SudokuEngine. No Apple framework imports.

public import Foundation
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
    /// Wall-clock provider for `startedAt`. Default `Date()`; tests inject
    /// a deterministic closure. Per impl-notes
    /// 2026-05-20_wave-2-blocker-fixes §B4: the snapshot is the single
    /// source of truth for `startedAt` so the mapper stays pure.
    private let now: @Sendable () -> Date

    // MARK: - startedAt

    /// Wall-clock instant of the first successful `.start()` on this
    /// session. Nil until `.start()` has been called at least once.
    /// Preserved across `restore(from:)` so analytics + conflict resolution
    /// see the original session-open time, not "time of last save".
    public private(set) var startedAt: Date?

    // MARK: - mistakeCount

    /// Cumulative count of conflicting `placeDigit` calls. Increments when the
    /// newly placed digit immediately conflicts with another cell in the same
    /// row, column, or 3×3 box. Never decrements — correcting a wrong digit
    /// does not reduce the count. Restored from snapshot on `restore(from:)`.
    public private(set) var mistakeCount: Int = 0

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
        telemetry: any GameStateTelemetry = NoOpGameStateTelemetry(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.puzzle = puzzle
        self.currentBoard = puzzle.clues
        self.clock = clock
        self.telemetry = telemetry
        self.now = now
    }

    // MARK: - Transitions

    public func start() async throws {
        try transition(.start)
        runningSince = clock.now
        if startedAt == nil {
            startedAt = now()
        }
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

        // SDD-003 AC-3.4: increment mistake counter when the newly placed digit
        // conflicts with another cell in the same row / column / 3×3 box.
        if Self.hasConflict(digit: digit, row: row, col: col, board: currentBoard) {
            mistakeCount += 1
        }

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

    /// Clear the digit at (row, col). Pushes the move onto the undo stack
    /// so subsequent `undo()` restores the prior digit. No-op if the cell is
    /// already empty (no move is pushed). Per impl-notes
    /// 2026-05-20_wave-2-blocker-fixes §B1: routing clear through the actor
    /// is what fixes the silent no-op (resync no longer overwrites because
    /// the actor IS the source of truth post-clear).
    public func clearDigit(row: Int, col: Int) async throws {
        guard status == .playing else {
            throw GameSessionError.invalidStateForAction(status: status)
        }
        guard (0..<Board.dimension).contains(row),
              (0..<Board.dimension).contains(col) else {
            throw GameSessionError.outOfRange
        }
        let index = Board.index(row: row, column: col)
        if currentBoard.givenMask[index] {
            throw GameSessionError.cellImmutable(row: row, col: col)
        }
        let previous = currentBoard.digit(atIndex: index)
        if previous == nil { return }   // already empty — no move recorded.

        try currentBoard.setDigit(nil, atRow: row, column: col)
        undoStack.push(.clearDigit(row: row, col: col, previous: previous))
        // No `.digitPlaced(digit: 0, ...)` dispatch — the telemetry enum has
        // no clear case yet. Adding `.digitCleared` is a follow-up flagged in
        // impl-notes §未決 (out of scope for the BLOCKER PR).
    }

    /// Clear all pencil notes in (row, col). Fire-and-forget — NOT enrolled
    /// in the undo stack. Used by the "Erase" cell affordance to wipe a
    /// cell's notes alongside its digit; the digit clear participates in
    /// undo via `clearDigit`, but adding notes to undo would require a
    /// `Move.clearDigit` schema bump (SavedGame Codable migration). See
    /// meetings/2026-05-30_board-mac-redesign.impl-notes.md §偏離.
    public func clearNotes(row: Int, col: Int) async throws {
        guard status == .playing else {
            throw GameSessionError.invalidStateForAction(status: status)
        }
        guard (0..<Board.dimension).contains(row),
              (0..<Board.dimension).contains(col) else {
            throw GameSessionError.outOfRange
        }
        let index = Board.index(row: row, column: col)
        if currentBoard.givenMask[index] {
            throw GameSessionError.cellImmutable(row: row, col: col)
        }
        notes.clear(row: row, col: col)
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
            notes: notes,
            startedAt: startedAt,
            mistakeCount: mistakeCount
        )
    }

    /// Rebuild a session from a snapshot. The restored session is "frozen"
    /// in whatever status the snapshot recorded; the wall clock does not
    /// auto-resume — `elapsedSeconds` is fully captured in
    /// `accumulatedSeconds` and a subsequent `resume()` opens a new span.
    public static func restore(
        from snapshot: GameSessionSnapshot,
        clock: any MonotonicClock = LiveMonotonicClock(),
        telemetry: any GameStateTelemetry = NoOpGameStateTelemetry(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) async -> GameSession {
        let session = GameSession(puzzle: snapshot.puzzle, clock: clock, telemetry: telemetry, now: now)
        await session.applySnapshot(snapshot)
        return session
    }

    /// Actor-isolated restore step. Reconstructs the undo/redo halves by
    /// pushing all undo moves, then synthetically routing each redo move
    /// through `push → undo` so it lands on the redo stack in order
    /// (UndoStack's only public mutators are `push` / `undo` / `redo`).
    private func applySnapshot(_ snapshot: GameSessionSnapshot) {
        currentBoard = snapshot.currentBoard
        // Normalize a restored `.playing` snapshot to `.paused`. Mid-play
        // autosaves persist `.playing` (GameViewModel.scheduleSave runs while
        // the session is live), but a restored session is ALWAYS frozen
        // (`runningSince = nil` below), so a `.playing` restore is
        // semantically "paused until the player explicitly resumes". This
        // matters because `resume()` only transitions from `.paused`
        // (GameSessionStatus table) — a frozen `.playing` has no path back to
        // a running span, leaving the clock stuck at the saved value. As
        // `.paused`, the existing explicit-resume path (GameViewModel
        // `startOrResume`: `.paused → resume()`) re-arms the clock when the
        // board mounts. We do NOT open a running span here: per §How.5.5 the
        // wall clock must not auto-resume, so time only accrues after the
        // explicit resume, never before the board is visible.
        status = snapshot.status == .playing ? .paused : snapshot.status
        notes = snapshot.notes
        accumulatedSeconds = snapshot.elapsedSeconds
        runningSince = nil
        startedAt = snapshot.startedAt
        mistakeCount = snapshot.mistakeCount

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

    /// Returns `true` when `digit` at (`row`, `col`) conflicts with any
    /// other cell in the same row, column, or 3×3 box. Used at placement
    /// time to decide whether to increment `mistakeCount`. Mirrors the
    /// logic in `GameViewModel.hasConflict` but lives here at the actor
    /// level so it is available without the MainActor VM dependency.
    private static func hasConflict(digit: Int, row: Int, col: Int, board: Board) -> Bool {
        for col2 in 0..<Board.dimension where col2 != col {
            if board.digit(atRow: row, column: col2) == digit { return true }
        }
        for row2 in 0..<Board.dimension where row2 != row {
            if board.digit(atRow: row2, column: col) == digit { return true }
        }
        let boxRowOrigin = (row / 3) * 3
        let boxColOrigin = (col / 3) * 3
        for row2 in boxRowOrigin..<boxRowOrigin + 3 {
            for col2 in boxColOrigin..<boxColOrigin + 3 where !(row2 == row && col2 == col) {
                if board.digit(atRow: row2, column: col2) == digit { return true }
            }
        }
        return false
    }

    private func revert(_ move: Move) throws {
        switch move {
        case let .placeDigit(row, col, _, previous):
            try currentBoard.setDigit(previous, atRow: row, column: col)
        case let .clearDigit(row, col, previous):
            try currentBoard.setDigit(previous, atRow: row, column: col)
        }
    }

    private func reapply(_ move: Move) throws {
        switch move {
        case let .placeDigit(row, col, digit, _):
            try currentBoard.setDigit(digit, atRow: row, column: col)
        case let .clearDigit(row, col, _):
            try currentBoard.setDigit(nil, atRow: row, column: col)
        }
    }
}
