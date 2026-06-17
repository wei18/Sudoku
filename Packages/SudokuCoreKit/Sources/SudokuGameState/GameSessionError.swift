// GameSessionError — errors thrown by `GameSession` mutation APIs.
//
// All Phase-3 mutation paths (transitions, placeDigit, undo/redo,
// snapshot restore) funnel illegal-state errors through this enum so that
// callers (Phase 8 ViewModel) can pattern-match a single error type.

internal import SudokuEngine

public enum GameSessionError: Error, Sendable, Equatable {
    /// State-machine violation per `GameSessionStatus.isLegal`.
    case illegalTransition(from: GameSessionStatus, applying: GameSessionTransition)
    /// `placeDigit` (or `clear`) targeted a clue cell.
    case cellImmutable(row: Int, col: Int)
    /// A mutation API was called outside `.playing`.
    case invalidStateForAction(status: GameSessionStatus)
    /// Row / column / digit out of 0..<9 / 1...9.
    case outOfRange
}
