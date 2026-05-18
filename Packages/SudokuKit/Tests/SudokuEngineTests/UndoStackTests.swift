import Testing
@testable import SudokuEngine

@Suite("UndoStack")
struct UndoStackTests {

    @Test func placeDigitUndoRestoresPrior() {
        var stack = UndoStack()
        let move = Move.placeDigit(row: 0, col: 0, digit: 5, previous: nil)
        stack.push(move)
        #expect(stack.undoStack.count == 1)
        let popped = stack.undo()
        #expect(popped == move)
        #expect(stack.undoStack.isEmpty)
        #expect(stack.redoStack.count == 1)
    }

    @Test func placeDigitUndoRedoReapplies() {
        var stack = UndoStack()
        let move = Move.placeDigit(row: 1, col: 2, digit: 7, previous: 3)
        stack.push(move)
        _ = stack.undo()
        let redone = stack.redo()
        #expect(redone == move)
        #expect(stack.undoStack == [move])
        #expect(stack.redoStack.isEmpty)
    }

    @Test func capacityIsTwenty() {
        var stack = UndoStack()
        for index in 0..<25 {
            stack.push(.placeDigit(row: 0, col: 0, digit: 1, previous: index))
        }
        #expect(stack.undoStack.count == UndoStack.capacity)
        // Oldest 5 entries (previous == 0..4) should have been dropped;
        // remaining range is previous == 5..24.
        if case .placeDigit(_, _, _, let prev) = stack.undoStack.first! {
            #expect(prev == 5)
        } else {
            Issue.record("Expected placeDigit at front of undoStack")
        }
        if case .placeDigit(_, _, _, let prev) = stack.undoStack.last! {
            #expect(prev == 24)
        } else {
            Issue.record("Expected placeDigit at back of undoStack")
        }
    }

    @Test func newPushInvalidatesRedo() {
        var stack = UndoStack()
        let moveA = Move.placeDigit(row: 0, col: 0, digit: 1, previous: nil)
        let moveB = Move.placeDigit(row: 1, col: 1, digit: 2, previous: nil)
        stack.push(moveA)
        _ = stack.undo()
        #expect(stack.redoStack == [moveA])
        stack.push(moveB)
        #expect(stack.redoStack.isEmpty)
        #expect(stack.redo() == nil)
    }

    @Test func undoOnEmptyStackIsNoop() {
        var stack = UndoStack()
        let result = stack.undo()
        #expect(result == nil)
        #expect(stack.undoStack.isEmpty)
        #expect(stack.redoStack.isEmpty)
    }

    @Test func redoOnEmptyRedoStackIsNoop() {
        var stack = UndoStack()
        let result = stack.redo()
        #expect(result == nil)
        #expect(stack.undoStack.isEmpty)
        #expect(stack.redoStack.isEmpty)
    }
}
