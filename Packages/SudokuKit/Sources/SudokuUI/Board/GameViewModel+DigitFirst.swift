// GameViewModel+DigitFirst — board-cell tap dispatch for digit-first input
// (#722). Split out of GameViewModel.swift, which already sits well past the
// 400-line SwiftLint file_length ceiling (a lint exemption is documented at
// the top of that file): `tapCell` only calls existing PUBLIC mutators
// (`select`, `placeDigit(at:)`, `toggleNote(at:)`) and touches no `private`
// collaborator, unlike `armDigit`/`select`, which must stay in the main file
// because they write the `private(set) var armedDigit` (Swift's `private`
// access is file-scoped).

import SudokuEngine

extension GameViewModel {
    /// Keypad digit tap (#722 digit-first input).
    ///
    /// - A live selection → today's flow, unchanged: place the digit (or, in
    ///   pencil mode, toggle its note) into the selected cell.
    /// - No selection → arm/disarm the tapped digit (`armDigit`) instead of
    ///   placing anything; a later `tapCell` places it.
    public func keypadDigit(_ digit: Int) async {
        guard selection != nil else {
            armDigit(digit)
            return
        }
        if pencilMode {
            await toggleNote(digit)
        } else {
            await placeDigit(digit)
        }
    }

    /// Board-cell tap dispatch (#722 digit-first input).
    ///
    /// - Not armed → today's cell-first flow, unchanged: `select(row:column:)`.
    /// - Armed + empty interactive cell → place (or, in pencil mode, toggle
    ///   the note for) the armed digit via the EXISTING placement path, so
    ///   mistake / error / undo / completion / persistence rules all still
    ///   apply. The cell does NOT become selected — the digit stays armed
    ///   for consecutive placements.
    /// - Armed + non-empty cell → fall back to cell-first: `select(...)`,
    ///   which also disarms — the single enforcement point for the
    ///   `armedDigit != nil ⟺ selection == nil` invariant on the "selecting"
    ///   side. Note: GIVEN cells never reach here from the UI — they carry no
    ///   Button wrapper (#473 non-interactive), so tapping a given while
    ///   armed is a no-op and the digit stays armed, matching cell-first
    ///   (givens are inert there too). The non-empty branch is reachable from
    ///   the UI only via user-filled cells.
    public func tapCell(row: Int, column: Int) async {
        guard (0..<Board.dimension).contains(row),
              (0..<Board.dimension).contains(column) else { return }
        let index = Board.index(row: row, column: column)
        let isEmpty = board.digit(atIndex: index) == nil
        if let armed = armedDigit, isEmpty {
            let coord = GridCoordinate(row: row, column: column)
            if pencilMode {
                await toggleNote(armed, at: coord)
            } else {
                await placeDigit(armed, at: coord)
            }
        } else {
            select(row: row, column: column)
        }
    }
}
