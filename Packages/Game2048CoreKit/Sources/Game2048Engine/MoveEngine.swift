// MoveEngine — deterministic slide-and-merge logic for 2048.
//
// Classic 2048 semantics:
//   - Tiles slide as far as possible in the chosen direction.
//   - Two tiles of equal value merge into their sum.
//   - Each tile merges at most once per move (double-merge prohibition).
//     e.g. [2,2,4,8] left → [4,4,8,nil]  NOT [8,8,nil,nil]
//          [4,4,4,4] left → [8,8,nil,nil] (each pair merges once)
//   - A move that produces no board change is illegal (returns nil).
//   - score delta = sum of all merged values in this move.
//
// Purely functional: `apply(_:to:)` returns a `MoveResult` with the new board
// and score delta, or nil if illegal.

public struct MoveResult: Sendable, Equatable {
    public let board: Board
    /// Points gained this move (sum of all merged tile values).
    public let scoreDelta: Int
}

public enum MoveEngine {

    // MARK: - Public API

    /// Attempt to slide `board` in `direction`. Returns a `MoveResult` if any tile
    /// moved or merged, or `nil` if the move is illegal (board unchanged).
    public static func apply(_ direction: Direction, to board: Board) -> MoveResult? {
        switch direction {
        case .left:  return applyRows(to: board, reversed: false)
        case .right: return applyRows(to: board, reversed: true)
        case .up:    return applyCols(to: board, reversed: false)
        case .down:  return applyCols(to: board, reversed: true)
        }
    }

    /// Returns true if any legal move exists (used for stuck detection).
    public static func hasLegalMove(on board: Board) -> Bool {
        // Any empty cell means at least one slide direction is legal.
        if !board.emptyIndices.isEmpty { return true }
        // Full board: check for adjacent equal tiles in either axis.
        for row in 0..<Board.size {
            for col in 0..<Board.size {
                let val = board[row, col]
                if col + 1 < Board.size && board[row, col + 1] == val { return true }
                if row + 1 < Board.size && board[row + 1, col] == val { return true }
            }
        }
        return false
    }

    // MARK: - Axis helpers

    private static func applyRows(to board: Board, reversed: Bool) -> MoveResult? {
        var result = board
        var total = 0
        var changed = false
        for row in 0..<Board.size {
            let line = extractRow(row, from: board)
            let (next, delta) = reversed ? slideReversed(line) : slideLine(line)
            if next != line { changed = true; insertRow(row, line: next, into: &result) }
            total += delta
        }
        return changed ? MoveResult(board: result, scoreDelta: total) : nil
    }

    private static func applyCols(to board: Board, reversed: Bool) -> MoveResult? {
        var result = board
        var total = 0
        var changed = false
        for col in 0..<Board.size {
            let line = extractCol(col, from: board)
            let (next, delta) = reversed ? slideReversed(line) : slideLine(line)
            if next != line { changed = true; insertCol(col, line: next, into: &result) }
            total += delta
        }
        return changed ? MoveResult(board: result, scoreDelta: total) : nil
    }

    // MARK: - Line operations

    /// Slide and merge a 4-element line toward index 0.
    /// Each tile merges at most once (double-merge prohibition).
    /// Returns the resulting 4-element line (nil-padded at the end) + score delta.
    ///
    /// Algorithm:
    ///   1. Compact: remove nils, keeping non-nil values in order.
    ///   2. Merge: scan left-to-right; when two adjacent values are equal, replace
    ///      them with their sum and skip the second (prevents double-merge).
    ///   3. Pad: append nils to restore length to Board.size.
    static func slideLine(_ line: some Collection<Int?>) -> (result: [Int?], scoreDelta: Int) {
        let nonNil = line.compactMap { $0 }
        var merged: [Int] = []
        var scoreDelta = 0
        var pos = 0
        while pos < nonNil.count {
            if pos + 1 < nonNil.count && nonNil[pos] == nonNil[pos + 1] {
                let value = nonNil[pos] * 2
                merged.append(value)
                scoreDelta += value
                pos += 2
            } else {
                merged.append(nonNil[pos])
                pos += 1
            }
        }
        var result: [Int?] = merged.map { Optional($0) }
        while result.count < Board.size { result.append(nil) }
        return (result, scoreDelta)
    }

    /// Slide toward the high end (right/down): reverse, slide, reverse back.
    private static func slideReversed(_ line: [Int?]) -> (result: [Int?], scoreDelta: Int) {
        let (slid, delta) = slideLine(line.reversed())
        return (Array(slid.reversed()), delta)
    }

    // MARK: - Row / column extraction

    static func extractRow(_ row: Int, from board: Board) -> [Int?] {
        (0..<Board.size).map { col in board[row, col] }
    }

    static func extractCol(_ col: Int, from board: Board) -> [Int?] {
        (0..<Board.size).map { row in board[row, col] }
    }

    static func insertRow(_ row: Int, line: [Int?], into board: inout Board) {
        for col in 0..<Board.size { board[row, col] = line[col] }
    }

    static func insertCol(_ col: Int, line: [Int?], into board: inout Board) {
        for row in 0..<Board.size { board[row, col] = line[row] }
    }
}
