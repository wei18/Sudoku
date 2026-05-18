// UndoStack — capacity-20 undo/redo buffer (design.md §What v1.3).
//
// Pure value type — does NOT mutate any Board. Callers (Phase 3 GameState)
// are responsible for applying / reverting move effects on their own Board
// state; UndoStack just records the timeline.
//
// FIFO eviction: when a `push` would exceed `capacity`, the oldest move is
// dropped from index 0. Any new `push` clears the redo stack — redo history
// is invalidated as soon as the user diverges from it.

public struct UndoStack: Sendable, Equatable {

    public static let capacity: Int = 20

    /// Most recent move is at the end. Oldest at index 0.
    public private(set) var undoStack: [Move]
    /// Redo stack — top of redo at the end.
    public private(set) var redoStack: [Move]

    public init() {
        self.undoStack = []
        self.redoStack = []
    }

    /// Record a freshly-applied move. Clears the redo stack and evicts the
    /// oldest entry if capacity would be exceeded.
    public mutating func push(_ move: Move) {
        redoStack.removeAll(keepingCapacity: true)
        undoStack.append(move)
        if undoStack.count > Self.capacity {
            undoStack.removeFirst(undoStack.count - Self.capacity)
        }
    }

    /// Pop the most recent move into the redo stack and return it. Returns
    /// nil and is a no-op if the undo stack is empty.
    public mutating func undo() -> Move? {
        guard let move = undoStack.popLast() else { return nil }
        redoStack.append(move)
        return move
    }

    /// Pop the top redo entry back onto the undo stack and return it. Returns
    /// nil and is a no-op if the redo stack is empty.
    public mutating func redo() -> Move? {
        guard let move = redoStack.popLast() else { return nil }
        undoStack.append(move)
        return move
    }
}
