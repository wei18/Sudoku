// GameSessionSnapshot — serializable value capturing the full session state.
//
// Used by Phase 5 (Persistence) to round-trip a `GameSession` through
// CloudKit and back via `GameSession.restore(from:clock:telemetry:)`.
//
// Pure value type: Sendable + Equatable + Hashable + Codable.

public import Foundation
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
    /// Wall-clock instant of the first `.start()` on the originating
    /// session. `nil` if the session was never started (idle snapshot).
    /// Single source of truth for the `SavedGame.startedAt` CloudKit field
    /// (per impl-notes 2026-05-20_wave-2-blocker-fixes §B4).
    public let startedAt: Date?
    /// Cumulative count of digit placements that immediately created a board
    /// conflict at the moment of placement. Increments on each conflicting
    /// `placeDigit`; never decrements (correcting a mistake is progress, not
    /// forgiveness). Persisted in the `SavedGame` CloudKit record so Resume
    /// returns the exact count the player had when they left (SDD-003 AC-3.4).
    /// Defaults to 0 for backward-compat decoding of older snapshots that
    /// predate this field.
    public let mistakeCount: Int

    public init(
        puzzle: Puzzle,
        currentBoard: Board,
        status: GameSessionStatus,
        elapsedSeconds: Int,
        undoMoves: [Move],
        redoMoves: [Move],
        notes: NotesGrid,
        startedAt: Date? = nil,
        mistakeCount: Int = 0
    ) {
        self.puzzle = puzzle
        self.currentBoard = currentBoard
        self.status = status
        self.elapsedSeconds = elapsedSeconds
        self.undoMoves = undoMoves
        self.redoMoves = redoMoves
        self.notes = notes
        self.startedAt = startedAt
        self.mistakeCount = mistakeCount
    }
}
