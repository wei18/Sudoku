// GameViewModel+CellFeedback — the Sudoku view-model half of the per-cell
// success animation (#1018). A placement that NEWLY completes a row / column /
// box begins one unit-sweep event in the shared `CellFeedbackState`; the event
// expires on its own after `CellFeedbackMotionPlan.unitSweepLifetime`.
//
// Hard constraint: feedback must never block or drop input. The view model
// only WRITES to `cellFeedback` — no input path reads it or awaits the expiry
// task. This file also owns the unit identity + "is this unit complete"
// detection that audio's section-cleared cue shares, so there is exactly one
// detector.

public import GameShellUI
import SudokuEngine

/// One row, column or box of the board. Box indices run 0...8 in reading order.
public enum SudokuUnit: Sendable, Hashable {
    case row(Int)
    case column(Int)
    case box(Int)

    /// The unit's nine board indices in sweep order: row left→right, column
    /// top→bottom, box in reading order.
    public var cellIndices: [Int] {
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
public struct SudokuCellFeedbackEvent: Sendable, Equatable {
    public let coordinate: GridCoordinate
    public let units: [SudokuUnit]
}

extension GameViewModel {
    /// Units among the three containing `coord` that are currently complete.
    func completedUnits(touching coord: GridCoordinate) -> Set<SudokuUnit> {
        Set(SudokuUnit.units(touching: coord).filter { isComplete($0) })
    }

    /// Units touching `coord` that are complete now but were not in `before`,
    /// in stable order (row, column, box).
    func newlyCompletedUnits(touching coord: GridCoordinate, before: Set<SudokuUnit>) -> [SudokuUnit] {
        SudokuUnit.units(touching: coord).filter { isComplete($0) && !before.contains($0) }
    }

    /// A unit is "complete" when every cell holds a digit and none is flagged as
    /// an error (a fully-filled-but-conflicting unit is not a real completion).
    private func isComplete(_ unit: SudokuUnit) -> Bool {
        for index in unit.cellIndices {
            guard board.digit(atIndex: index) != nil else { return false }
            if errorIndices.contains(index) { return false }
        }
        return true
    }

    /// Begin one unit-sweep event if the placement at `coord` newly completed
    /// a unit. Write-only: the expiry task is held by `cellFeedback` itself
    /// (`pendingExpiries`) and is never awaited here.
    func beginUnitSweepFeedback(at coord: GridCoordinate, before: Set<SudokuUnit>) {
        let units = newlyCompletedUnits(touching: coord, before: before)
        guard !units.isEmpty else { return }
        cellFeedback.begin(
            SudokuCellFeedbackEvent(coordinate: coord, units: units),
            lifetime: CellFeedbackMotionPlan.unitSweepLifetime,
            sleeper: cellFeedbackSleeper
        )
    }
}
