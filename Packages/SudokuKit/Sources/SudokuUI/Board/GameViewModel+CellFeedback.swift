// GameViewModel+CellFeedback — the Sudoku view-model half of the per-cell
// success animation (#1018). A placement that NEWLY completes a row / column /
// box begins one unit-sweep event in the shared `CellFeedbackState`; the event
// expires on its own after `CellFeedbackMotionPlan.unitSweepLifetime`.
//
// Hard constraint: feedback must never block or drop input. The view model
// only WRITES to `cellFeedback` — no input path reads it or awaits the expiry
// task. This file also owns the unit identity + "is this unit complete"
// detection (pure over two boards) that audio's section-cleared cue shares, so
// there is exactly one detector.

import GameShellUI
import SudokuEngine
import SudokuGameState

/// One row, column or box of the board. Box indices run 0...8 in reading order.
enum SudokuUnit: Sendable, Hashable {
    case row(Int)
    case column(Int)
    case box(Int)

    /// The unit's nine board indices in sweep order: row first→last cell in
    /// reading order, column top→bottom, box in reading order.
    var cellIndices: [Int] {
        switch self {
        case let .row(row):
            return (0..<Board.dimension).map { Board.index(row: row, column: $0) }
        case let .column(column):
            return (0..<Board.dimension).map { Board.index(row: $0, column: column) }
        case let .box(box):
            let boxRow = (box / 3) * 3
            let boxColumn = (box % 3) * 3
            var indices: [Int] = []
            for row in boxRow..<boxRow + 3 {
                for column in boxColumn..<boxColumn + 3 {
                    indices.append(Board.index(row: row, column: column))
                }
            }
            return indices
        }
    }

    /// The three units containing `coord`, in stable order: row, column, box.
    static func units(touching coord: GridCoordinate) -> [SudokuUnit] {
        [.row(coord.row), .column(coord.column), .box((coord.row / 3) * 3 + coord.column / 3)]
    }
}

/// A unit-sweep feedback event: the placed cell plus the units that placement
/// newly completed (row, column, box order).
struct SudokuCellFeedbackEvent: Sendable, Equatable {
    let coordinate: GridCoordinate
    let units: [SudokuUnit]
}

extension SudokuUnit {
    /// Units among the three containing `coord` that are complete in `after`
    /// but were not in `before`, in stable order (row, column, box). Pure over
    /// the two boards, so a caller holding one placement's own pair is never
    /// affected by any other placement.
    static func newlyCompleted(touching coord: GridCoordinate, from before: Board, to after: Board) -> [SudokuUnit] {
        let errorsBefore = before.conflictingUserIndices()
        let errorsAfter = after.conflictingUserIndices()
        return units(touching: coord).filter {
            $0.isComplete(in: after, errors: errorsAfter) && !$0.isComplete(in: before, errors: errorsBefore)
        }
    }

    /// A unit is "complete" when every cell holds a digit and none is flagged as
    /// an error (a fully-filled-but-conflicting unit is not a real completion).
    private func isComplete(in board: Board, errors: Set<Int>) -> Bool {
        for index in cellIndices {
            guard board.digit(atIndex: index) != nil else { return false }
            if errors.contains(index) { return false }
        }
        return true
    }
}

extension Board {
    /// Indices of user-filled cells whose digit conflicts (row/col/box) with
    /// another cell. Givens are excluded since they're trusted.
    func conflictingUserIndices() -> Set<Int> {
        var errors: Set<Int> = []
        for row in 0..<Board.dimension {
            for col in 0..<Board.dimension {
                let index = Board.index(row: row, column: col)
                guard !givenMask[index], let digit = self.digit(atIndex: index) else { continue }
                if hasConflict(digit: digit, row: row, col: col) {
                    errors.insert(index)
                }
            }
        }
        return errors
    }
}

extension GameViewModel {
    /// Begin one unit-sweep event if the placement at `coord` newly completed
    /// the given units. Write-only: the expiry task is held by `cellFeedback`
    /// itself (`pendingExpiries`) and is never awaited here.
    func beginUnitSweepFeedback(at coord: GridCoordinate, units: [SudokuUnit]) {
        guard !units.isEmpty else { return }
        cellFeedback.begin(
            SudokuCellFeedbackEvent(coordinate: coord, units: units),
            lifetime: CellFeedbackMotionPlan.unitSweepLifetime,
            sleeper: cellFeedbackSleeper
        )
    }
}
