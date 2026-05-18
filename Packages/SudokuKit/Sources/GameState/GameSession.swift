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

    // MARK: - Init

    public init(puzzle: Puzzle) {
        self.puzzle = puzzle
        self.currentBoard = puzzle.clues
    }

    // MARK: - Transitions

    public func start() throws {
        try transition(.start)
    }

    public func pause() throws {
        try transition(.pause)
    }

    public func resume() throws {
        try transition(.resume)
    }

    public func complete() throws {
        try transition(.complete)
    }

    public func abandon() throws {
        try transition(.abandon)
    }

    // MARK: - Internal

    /// Apply a transition or throw `.illegalTransition` if disallowed by the
    /// state machine. All public transition methods funnel through here so
    /// the lifecycle table is enforced in exactly one place.
    private func transition(_ transition: GameSessionTransition) throws {
        guard let next = status.applying(transition) else {
            throw GameSessionError.illegalTransition(from: status, applying: transition)
        }
        status = next
    }
}
