// GameViewModel — owns one in-flight game session for BoardView.
//
// Per docs/design.md §How.5.3 (state machine) + §How.5.4 (VM ownership) +
// §How.5.5 (debounce flush).
//
// Implementation choice: the VM mirrors `GameSession` state into observable
// properties (`board`, `notes`, `elapsedSeconds`, etc.) so SwiftUI can read
// them synchronously. Every user mutation (place / pencil / undo / redo)
// dispatches to the `GameSession` actor, then re-syncs the cached state.
// Snapshot tests bypass the live session via `setStateForTesting(...)` so
// they can render deterministic boards without spinning up generators.

public import Foundation
public import GameState
public import Persistence
public import PuzzleStore
public import SudokuEngine

@MainActor
@Observable
public final class GameViewModel {

    // MARK: - Identity

    public let identity: PuzzleIdentity

    // MARK: - Observable view state (kept in sync with GameSession)

    public private(set) var board: Board
    public private(set) var notes: NotesGrid
    public private(set) var status: GameSessionStatus
    public private(set) var elapsedSeconds: Int
    public private(set) var canUndo: Bool = false
    public private(set) var canRedo: Bool = false

    /// Currently-focused cell. UI selection drives both tap and keyboard
    /// arrows; `nil` means no cell focused (legal initial state).
    public var selection: GridCoordinate?

    /// Whether digit input writes pencil notes (`true`) or values (`false`).
    public var pencilMode: Bool = false

    /// Set of board indices currently flagged as conflicting. Computed by
    /// `recomputeErrors()` after each placement.
    public private(set) var errorIndices: Set<Int> = []

    /// `true` while the session is paused; UI overlays a "Tap to resume" pane.
    public var isPaused: Bool { status == .paused }

    // MARK: - Collaborators

    private let session: GameSession?
    private let persistence: (any PersistenceProtocol)?

    /// Debounce interval for the save task; injectable so tests can shrink it.
    private let saveDebounceNanos: UInt64
    private var pendingSaveTask: Task<Void, Never>?

    // MARK: - Init

    /// Live init — bind to a real `GameSession` + `Persistence`.
    public init(
        identity: PuzzleIdentity,
        session: GameSession,
        initialBoard: Board,
        initialNotes: NotesGrid = NotesGrid(),
        initialStatus: GameSessionStatus = .idle,
        initialElapsedSeconds: Int = 0,
        persistence: any PersistenceProtocol,
        saveDebounceNanos: UInt64 = 500_000_000
    ) {
        self.identity = identity
        self.session = session
        self.board = initialBoard
        self.notes = initialNotes
        self.status = initialStatus
        self.elapsedSeconds = initialElapsedSeconds
        self.persistence = persistence
        self.saveDebounceNanos = saveDebounceNanos
    }

    /// Snapshot / preview init — no live `GameSession`, no persistence.
    /// All mutators that would hit the actor become no-ops. Used by snapshot
    /// tests + SwiftUI previews to render deterministic board states.
    public init(
        identity: PuzzleIdentity,
        board: Board,
        notes: NotesGrid = NotesGrid(),
        status: GameSessionStatus = .playing,
        elapsedSeconds: Int = 0,
        errorIndices: Set<Int> = [],
        selection: GridCoordinate? = nil,
        pencilMode: Bool = false,
        canUndo: Bool = false,
        canRedo: Bool = false
    ) {
        self.identity = identity
        self.session = nil
        self.persistence = nil
        self.saveDebounceNanos = 0
        self.board = board
        self.notes = notes
        self.status = status
        self.elapsedSeconds = elapsedSeconds
        self.errorIndices = errorIndices
        self.selection = selection
        self.pencilMode = pencilMode
        self.canUndo = canUndo
        self.canRedo = canRedo
    }

    // MARK: - Test seam

    /// Test seam: install a fully-formed view state without going through
    /// the GameSession actor. Used by snapshot tests + behavior tests for
    /// keyboard input.
    public func setStateForTesting(
        board: Board? = nil,
        notes: NotesGrid? = nil,
        status: GameSessionStatus? = nil,
        elapsedSeconds: Int? = nil,
        errorIndices: Set<Int>? = nil,
        selection: GridCoordinate? = nil,
        pencilMode: Bool? = nil,
        canUndo: Bool? = nil,
        canRedo: Bool? = nil
    ) {
        if let board { self.board = board }
        if let notes { self.notes = notes }
        if let status { self.status = status }
        if let elapsedSeconds { self.elapsedSeconds = elapsedSeconds }
        if let errorIndices { self.errorIndices = errorIndices }
        if let selection { self.selection = selection }
        if let pencilMode { self.pencilMode = pencilMode }
        if let canUndo { self.canUndo = canUndo }
        if let canRedo { self.canRedo = canRedo }
    }

    // MARK: - Mutations (UI-facing)

    /// Place a digit (1...9) or clear (`nil`) into the currently-selected
    /// cell. No-op if no cell is selected or the cell is a given. Routes
    /// through `GameSession` when one is bound, then re-syncs view state.
    public func placeDigit(_ digit: Int?) async {
        guard let selection else { return }
        await placeDigit(digit, at: selection)
    }

    public func placeDigit(_ digit: Int?, at coord: GridCoordinate) async {
        let index = Board.index(row: coord.row, column: coord.column)
        if board.givenMask[index] { return }

        if let session {
            if let digit {
                try? await session.placeDigit(row: coord.row, col: coord.column, digit: digit)
            } else {
                // Per impl-notes 2026-05-20_wave-2-blocker-fixes §B1: clear
                // routes through the actor like place. The actor records a
                // `.clearDigit` undo move and updates `currentBoard`, so the
                // subsequent `resyncFromSession()` keeps the cell cleared.
                try? await session.clearDigit(row: coord.row, col: coord.column)
            }
            await resyncFromSession()
        } else {
            // Preview / test path: poke the mirror without crossing actor.
            try? board.setDigit(digit, atRow: coord.row, column: coord.column)
            recomputeErrors()
        }
        scheduleSave()
    }

    public func toggleNote(_ digit: Int) async {
        guard let selection else { return }
        let index = Board.index(row: selection.row, column: selection.column)
        if board.givenMask[index] { return }

        if let session {
            try? await session.toggleNote(row: selection.row, col: selection.column, digit: digit)
            await resyncFromSession()
        } else {
            _ = notes.toggle(digit: digit, row: selection.row, col: selection.column)
        }
        scheduleSave()
    }

    public func undo() async {
        guard let session else { return }
        try? await session.undo()
        await resyncFromSession()
        scheduleSave()
    }

    public func redo() async {
        guard let session else { return }
        try? await session.redo()
        await resyncFromSession()
        scheduleSave()
    }

    public func pause() async {
        guard let session else {
            status = .paused
            return
        }
        try? await session.pause()
        await resyncFromSession()
        await flush()
    }

    public func resume() async {
        guard let session else {
            status = .playing
            return
        }
        try? await session.resume()
        await resyncFromSession()
    }

    public func togglePencil() {
        pencilMode.toggle()
    }

    public func select(row: Int, column: Int) {
        guard (0..<Board.dimension).contains(row),
              (0..<Board.dimension).contains(column) else { return }
        selection = GridCoordinate(row: row, column: column)
    }

    /// Move focus by a delta (used by Mac arrow keys). Clamps to board bounds.
    public func moveSelection(rowDelta: Int, columnDelta: Int) {
        let current = selection ?? GridCoordinate(row: 0, column: 0)
        let nextRow = max(0, min(Board.dimension - 1, current.row + rowDelta))
        let nextCol = max(0, min(Board.dimension - 1, current.column + columnDelta))
        selection = GridCoordinate(row: nextRow, column: nextCol)
    }

    // MARK: - Persistence

    /// Debounced save — cancels prior pending task, then queues a fresh one.
    /// Per §How.5.5; debounce window is `saveDebounceNanos` (default 500 ms).
    private func scheduleSave() {
        guard let persistence, let session else { return }
        pendingSaveTask?.cancel()
        let delay = saveDebounceNanos
        // Capture identity primitives at scheduling time — they cannot
        // change for a given VM instance, and capturing them here keeps the
        // Task body off `self`'s isolation domain. Per impl-notes
        // 2026-05-20_wave-2-blocker-fixes §B2.
        let puzzleId = identity.puzzleId
        let mode = identity.kind.rawValue
        let difficulty = identity.difficulty
        pendingSaveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: delay)
            if Task.isCancelled { return }
            guard let snapshot = await self?.captureSnapshot() else { return }
            try? await persistence.save(
                snapshot,
                puzzleId: puzzleId,
                mode: mode,
                difficulty: difficulty
            )
        }
        _ = session  // silence unused-capture warning
    }

    private func captureSnapshot() async -> GameSessionSnapshot? {
        guard let session else { return nil }
        return await session.snapshot()
    }

    /// Force-flush any pending debounced save. Awaits the actual write.
    /// Per §How.5.5 — called on pause / scenePhase background / view dismiss.
    public func flush() async {
        pendingSaveTask?.cancel()
        guard let snapshot = await captureSnapshot(),
              let persistence else { return }
        try? await persistence.save(
            snapshot,
            puzzleId: identity.puzzleId,
            mode: identity.kind.rawValue,
            difficulty: identity.difficulty
        )
    }

    // MARK: - Internal helpers

    private func resyncFromSession() async {
        guard let session else { return }
        let snap = await session.snapshot()
        self.board = snap.currentBoard
        self.notes = snap.notes
        self.status = snap.status
        self.elapsedSeconds = snap.elapsedSeconds
        self.canUndo = !snap.undoMoves.isEmpty
        self.canRedo = !snap.redoMoves.isEmpty
        recomputeErrors()
    }

    /// Mark every user-filled cell whose digit conflicts (row/col/box) with
    /// another cell as an error. Givens are excluded since they're trusted.
    private func recomputeErrors() {
        var errors: Set<Int> = []
        for row in 0..<Board.dimension {
            for col in 0..<Board.dimension {
                let index = Board.index(row: row, column: col)
                guard !board.givenMask[index],
                      let digit = board.digit(atIndex: index) else { continue }
                if hasConflict(digit: digit, row: row, col: col) {
                    errors.insert(index)
                }
            }
        }
        self.errorIndices = errors
    }

    private func hasConflict(digit: Int, row: Int, col: Int) -> Bool {
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
}

// MARK: - Value types

public struct GridCoordinate: Sendable, Equatable, Hashable {
    public let row: Int
    public let column: Int
    public init(row: Int, column: Int) {
        self.row = row
        self.column = column
    }
}
