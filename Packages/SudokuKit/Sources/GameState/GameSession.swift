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

    // MARK: - Telemetry

    private let telemetry: any GameStateTelemetry

    // MARK: - Init

    public init(
        puzzle: Puzzle,
        telemetry: any GameStateTelemetry = NoOpGameStateTelemetry()
    ) {
        self.puzzle = puzzle
        self.currentBoard = puzzle.clues
        self.telemetry = telemetry
    }

    // MARK: - Transitions

    public func start() async throws {
        try transition(.start)
        await telemetry.dispatch(.sessionStarted)
    }

    public func pause() async throws {
        try transition(.pause)
        await telemetry.dispatch(.sessionPaused)
    }

    public func resume() async throws {
        try transition(.resume)
        await telemetry.dispatch(.sessionResumed)
    }

    public func complete() async throws {
        try transition(.complete)
        await telemetry.dispatch(.sessionCompleted(elapsedSeconds: 0))
    }

    public func abandon() async throws {
        try transition(.abandon)
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
            await telemetry.dispatch(.sessionCompleted(elapsedSeconds: 0))
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

    // MARK: - Internal

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
