// GameSessionSnapshot — serializable value capturing the full session state.
//
// Used by Phase 5 (Persistence) to round-trip a `GameSession` through
// CloudKit and back via `GameSession.restore(from:clock:telemetry:)`.
//
// Pure value type: Sendable + Equatable + Hashable + Codable.

import Foundation
public import SudokuEngine

public struct GameSessionSnapshot: Sendable, Equatable, Hashable, Codable {
    public let puzzle: Puzzle
    public let currentBoard: Board
    public let status: GameSessionStatus
    public let elapsedSeconds: Int
    /// UndoStack flattened into its two serializable halves. SudokuEngine
    /// only exposes UndoStack as Sendable+Equatable (no Codable/Hashable),
    /// so the snapshot stores Moves directly and reconstructs the stack on
    /// restore. Keeping the field name `undo*` lines up with §How.2's
    /// `undoStack` CloudKit field.
    public let undoMoves: [Move]
    public let redoMoves: [Move]
    public let notes: NotesGrid

    public init(
        puzzle: Puzzle,
        currentBoard: Board,
        status: GameSessionStatus,
        elapsedSeconds: Int,
        undoMoves: [Move],
        redoMoves: [Move],
        notes: NotesGrid
    ) {
        self.puzzle = puzzle
        self.currentBoard = currentBoard
        self.status = status
        self.elapsedSeconds = elapsedSeconds
        self.undoMoves = undoMoves
        self.redoMoves = redoMoves
        self.notes = notes
    }
}
