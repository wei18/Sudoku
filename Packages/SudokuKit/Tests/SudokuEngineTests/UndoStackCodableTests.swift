import Foundation
import Testing
@testable import SudokuEngine

@Suite("UndoStack Codable + Hashable")
struct UndoStackCodableTests {

    @Test func moveCodableRoundTrip() throws {
        let move = Move.placeDigit(row: 3, col: 5, digit: 7, previous: 2)
        let data = try JSONEncoder().encode(move)
        let decoded = try JSONDecoder().decode(Move.self, from: data)
        #expect(decoded == move)
    }

    @Test func moveCodableRoundTripNilPrevious() throws {
        let move = Move.placeDigit(row: 0, col: 0, digit: 9, previous: nil)
        let data = try JSONEncoder().encode(move)
        let decoded = try JSONDecoder().decode(Move.self, from: data)
        #expect(decoded == move)
    }

    @Test func moveHashableSameInputSameHash() {
        let lhs = Move.placeDigit(row: 1, col: 2, digit: 3, previous: 4)
        let rhs = Move.placeDigit(row: 1, col: 2, digit: 3, previous: 4)
        #expect(lhs.hashValue == rhs.hashValue)
    }

    @Test func moveHashableDifferentInputsLikelyDifferentHash() {
        let lhs = Move.placeDigit(row: 1, col: 2, digit: 3, previous: 4)
        let rhs = Move.placeDigit(row: 5, col: 6, digit: 7, previous: 8)
        // Smoke check: not a strict guarantee, but collisions on this trivial
        // distinction would indicate something is wrong with synthesis.
        #expect(lhs.hashValue != rhs.hashValue)
    }

    @Test func undoStackCodableRoundTripFiveMoves() throws {
        var stack = UndoStack()
        for index in 0..<5 {
            stack.push(.placeDigit(row: 0, col: index, digit: index + 1, previous: nil))
        }
        let data = try JSONEncoder().encode(stack)
        let decoded = try JSONDecoder().decode(UndoStack.self, from: data)
        #expect(decoded == stack)
        #expect(decoded.undoStack.count == 5)
        #expect(decoded.redoStack.isEmpty)
    }

    @Test func undoStackCodableRoundTripWithRedoEntries() throws {
        var stack = UndoStack()
        stack.push(.placeDigit(row: 0, col: 0, digit: 1, previous: nil))
        stack.push(.placeDigit(row: 0, col: 1, digit: 2, previous: nil))
        stack.push(.placeDigit(row: 0, col: 2, digit: 3, previous: nil))
        _ = stack.undo()
        _ = stack.undo()
        let data = try JSONEncoder().encode(stack)
        let decoded = try JSONDecoder().decode(UndoStack.self, from: data)
        #expect(decoded == stack)
        #expect(decoded.undoStack.count == 1)
        #expect(decoded.redoStack.count == 2)
    }

    @Test func undoStackHashableEqualStatesEqualHash() {
        var lhs = UndoStack()
        var rhs = UndoStack()
        for index in 0..<3 {
            let move = Move.placeDigit(row: 0, col: index, digit: index + 1, previous: nil)
            lhs.push(move)
            rhs.push(move)
        }
        #expect(lhs.hashValue == rhs.hashValue)
    }

    @Test func undoStackCapacityEvictionPreservedAcrossRoundTrip() throws {
        var stack = UndoStack()
        for index in 0..<25 {
            stack.push(.placeDigit(row: 0, col: 0, digit: 1, previous: index))
        }
        let data = try JSONEncoder().encode(stack)
        let decoded = try JSONDecoder().decode(UndoStack.self, from: data)
        #expect(decoded.undoStack.count == UndoStack.capacity)
        if case .placeDigit(_, _, _, let prev) = decoded.undoStack.first! {
            #expect(prev == 5)
        } else {
            Issue.record("Expected placeDigit at front")
        }
        if case .placeDigit(_, _, _, let prev) = decoded.undoStack.last! {
            #expect(prev == 24)
        } else {
            Issue.record("Expected placeDigit at back")
        }
    }
}
