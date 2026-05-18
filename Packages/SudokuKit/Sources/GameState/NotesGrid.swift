// NotesGrid — 9×9 pencil-mark side table.
//
// Phase 2's `Move` enum only carries `placeDigit`; pencil notes are NOT
// part of the undo/redo stack (per design.md, note toggles are cheap and
// the Phase 2.4 design intentionally limited Move to placeDigit). We store
// candidates here as a separate value type owned by `GameSession`.
//
// Encoding: a `UInt16` per cell, with bits 1..9 indicating "digit d is
// pencilled in". Bit 0 unused.

import Foundation
public import SudokuEngine

public struct NotesGrid: Sendable, Equatable, Hashable, Codable {

    public private(set) var masks: [UInt16]

    public init() {
        self.masks = Array(repeating: 0, count: Board.cellCount)
    }

    public init(masks: [UInt16]) {
        precondition(masks.count == Board.cellCount, "NotesGrid requires 81 entries")
        self.masks = masks
    }

    public func contains(digit: Int, row: Int, col: Int) -> Bool {
        guard (1...9).contains(digit) else { return false }
        let index = Board.index(row: row, column: col)
        return (masks[index] & (1 << digit)) != 0
    }

    @discardableResult
    public mutating func toggle(digit: Int, row: Int, col: Int) -> Bool {
        guard (1...9).contains(digit) else { return false }
        let index = Board.index(row: row, column: col)
        let bit: UInt16 = 1 << digit
        if (masks[index] & bit) != 0 {
            masks[index] &= ~bit
            return false
        } else {
            masks[index] |= bit
            return true
        }
    }

    public mutating func clear(row: Int, col: Int) {
        let index = Board.index(row: row, column: col)
        masks[index] = 0
    }
}
