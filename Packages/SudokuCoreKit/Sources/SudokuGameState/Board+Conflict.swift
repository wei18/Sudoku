import SudokuEngine

extension Board {
    /// Returns `true` when `digit` at (`row`, `col`) conflicts with any
    /// other cell in the same row, column, or 3×3 box. Used at placement
    /// time to decide whether to increment `mistakeCount`. Logic is identical
    /// to `Board.conflictingUserIndices()` in SudokuUI — that is the UI-layer
    /// duplicate (MainActor) which cannot call into this module's internals;
    /// CoreKit is the authoritative copy.
    func hasConflict(digit: Int, row: Int, col: Int) -> Bool {
        for col2 in 0..<Board.dimension where col2 != col {
            if self.digit(atRow: row, column: col2) == digit { return true }
        }
        for row2 in 0..<Board.dimension where row2 != row {
            if self.digit(atRow: row2, column: col) == digit { return true }
        }
        let boxRowOrigin = (row / 3) * 3
        let boxColOrigin = (col / 3) * 3
        for row2 in boxRowOrigin..<boxRowOrigin + 3 {
            for col2 in boxColOrigin..<boxColOrigin + 3 where !(row2 == row && col2 == col) {
                if self.digit(atRow: row2, column: col2) == digit { return true }
            }
        }
        return false
    }
}
