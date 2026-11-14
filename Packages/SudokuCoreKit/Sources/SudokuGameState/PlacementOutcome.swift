public import SudokuEngine

/// What one `GameSession.placeDigit` call did, captured by the session itself.
/// `boardBefore` and `boardAfter` belong to a single placement: nothing written
/// by a concurrent placement appears in either, so cues derived from the pair
/// are attributed to this call alone.
public struct PlacementOutcome: Sendable, Equatable {
    /// Session board just before this call's write.
    public let boardBefore: Board
    /// Session board just after this call's write and nothing else.
    public let boardAfter: Board
    /// This call moved the session from `.playing` to `.completed`.
    public let completedGame: Bool

    public init(boardBefore: Board, boardAfter: Board, completedGame: Bool) {
        self.boardBefore = boardBefore
        self.boardAfter = boardAfter
        self.completedGame = completedGame
    }
}
