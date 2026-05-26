// Solver — 3-layer constraint propagation per docs/v1/design.md §How.4.4.
//
// Pure functions over Board (in-out for the imperative variants).
// No RNG, no DFS — DFS lives in UniquenessValidator.

public struct Solver: Sendable {

    public init() {}

    /// Apply a single technique once across the whole board. Returns whether anything changed.
    public func applyOnce(_ technique: SolverTechnique, to board: inout Board) -> SolverProgress {
        switch technique {
        case .nakedSingle:
            return applyNakedSingle(to: &board)
        case .hiddenSingle:
            return applyHiddenSingle(to: &board)
        case .nakedPair:
            return applyNakedPair(to: &board)
        }
    }

    /// Run all three techniques to fixed point. Returns true if the board is fully filled
    /// after propagation (i.e., solved by propagation alone).
    @discardableResult
    public func propagate(to board: inout Board) -> Bool {
        while true {
            let single = applyNakedSingle(to: &board)
            if single == .changed { continue }
            let hidden = applyHiddenSingle(to: &board)
            if hidden == .changed { continue }
            let pair = applyNakedPair(to: &board)
            if pair == .changed { continue }
            break
        }
        return board.isFullyFilled
    }

    // MARK: - Naked single

    private func applyNakedSingle(to board: inout Board) -> SolverProgress {
        let grid = CandidateGrid(board: board)
        var changed = false
        for index in 0..<Board.cellCount where board.cellRaw(at: index) == 0 {
            if let digit = CandidateGrid.lonelyDigit(grid.masks[index]) {
                board.setCellRaw(UInt8(digit), at: index)
                changed = true
            }
        }
        return changed ? .changed : .unchanged
    }

    // MARK: - Hidden single

    private func applyHiddenSingle(to board: inout Board) -> SolverProgress {
        var changed = false
        let grid = CandidateGrid(board: board)
        let allUnits = CandidateGrid.rowsIndices + CandidateGrid.colsIndices + CandidateGrid.boxesIndices
        for unit in allUnits {
            for digit in 1...9 {
                if let foundIdx = uniqueCandidateCell(forDigit: digit, in: unit, board: board, grid: grid) {
                    board.setCellRaw(UInt8(digit), at: foundIdx)
                    changed = true
                }
            }
        }
        return changed ? .changed : .unchanged
    }

    private func uniqueCandidateCell(
        forDigit digit: Int,
        in unit: [Int],
        board: Board,
        grid: CandidateGrid
    ) -> Int? {
        let bit: UInt16 = 1 << (digit - 1)
        var foundIdx = -1
        var count = 0
        for cellIdx in unit {
            let value = board.cellRaw(at: cellIdx)
            if value == UInt8(digit) {
                return nil // already placed in this unit
            }
            if value == 0 && (grid.masks[cellIdx] & bit) != 0 {
                foundIdx = cellIdx
                count += 1
                if count > 1 { return nil }
            }
        }
        return count == 1 ? foundIdx : nil
    }

    // MARK: - Naked pair

    /// Applies the naked-pair candidate elimination across all units. The
    /// technique never directly writes a Board cell — it only narrows the
    /// in-memory `CandidateGrid`. A Board cell is filled only when the
    /// narrowed candidate set collapses to a single digit (a cascade into
    /// naked-single territory).
    ///
    /// `SolverProgress.changed` is reported **iff at least one Board cell
    /// was filled**, not merely whenever a candidate was eliminated. The
    /// local CandidateGrid is discarded between `applyOnce` invocations, so
    /// reporting candidate-only eliminations as `.changed` would cause
    /// `propagate()` to loop forever rediscovering the same naked pair on
    /// a Board whose cells never change.
    private func applyNakedPair(to board: inout Board) -> SolverProgress {
        var filled = false
        var grid = CandidateGrid(board: board)
        let allUnits = CandidateGrid.rowsIndices + CandidateGrid.colsIndices + CandidateGrid.boxesIndices
        for unit in allUnits {
            var pairCells: [(Int, UInt16)] = []
            for cellIdx in unit
            where board.cellRaw(at: cellIdx) == 0 && CandidateGrid.popcount(grid.masks[cellIdx]) == 2 {
                pairCells.append((cellIdx, grid.masks[cellIdx]))
            }
            var byMask: [UInt16: [Int]] = [:]
            for (idx, mask) in pairCells {
                byMask[mask, default: []].append(idx)
            }
            for (mask, members) in byMask where members.count == 2 {
                let memberSet = Set(members)
                for cellIdx in unit
                where !memberSet.contains(cellIdx) && board.cellRaw(at: cellIdx) == 0 {
                    let before = grid.masks[cellIdx]
                    let after = before & ~mask
                    if after != before {
                        grid.masks[cellIdx] = after
                        if let digit = CandidateGrid.lonelyDigit(after) {
                            board.setCellRaw(UInt8(digit), at: cellIdx)
                            filled = true
                        }
                    }
                }
            }
        }
        return filled ? .changed : .unchanged
    }
}
