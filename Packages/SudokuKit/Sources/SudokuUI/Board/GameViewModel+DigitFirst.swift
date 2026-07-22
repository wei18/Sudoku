// GameViewModel+DigitFirst — board-cell tap dispatch for digit-first input
// (#722; sticky-armed per #939). Split out of GameViewModel.swift, which
// already sits well past the 400-line SwiftLint file_length ceiling (a lint
// exemption is documented at the top of that file): `tapCell` only calls
// existing PUBLIC mutators (`select`, `placeDigit(at:)`, `toggleNote(at:)`)
// plus one internal forwarder (`fireArmedMismatchFeedback()`) and touches no
// `private` collaborator, unlike `armDigit`/`select`, which must stay in the
// main file because they write the `private(set) var armedDigit` (Swift's
// `private` access is file-scoped).

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

    /// Board-cell tap dispatch (#722 digit-first input; sticky-armed per #939).
    ///
    /// - Not armed → today's cell-first flow, unchanged: `select(row:column:)`.
    /// - Armed + empty interactive cell → place (or, in pencil mode, toggle
    ///   the note for) the armed digit via the EXISTING placement path, so
    ///   mistake / error / undo / completion / persistence rules all still
    ///   apply. The cell does NOT become selected — the digit stays armed
    ///   for consecutive placements.
    /// - Armed + user-filled cell already holding the armed digit → clear it
    ///   (toggle off) in normal mode; in pencil mode, toggle the note instead
    ///   (notes are independent of the cell's digit value, so this matches
    ///   the empty-cell note-toggle semantics above rather than clearing).
    /// - Armed + any OTHER non-empty cell (a different digit, or a given) →
    ///   sticky no-op: the tap is absorbed, `armedDigit` is untouched, and a
    ///   light haptic (iOS only, via the existing `GameAudio` haptic seam —
    ///   see `fireArmedMismatchFeedback()`) signals the tap registered. This
    ///   is #939's whole point: a fast digit-first sweep no longer dies the
    ///   moment it mis-taps a filled cell.
    ///
    /// None of the armed branches call `select(...)`, so — unlike pre-#939 —
    /// this function never disarms; the invariant `armedDigit != nil ⟺
    /// selection == nil` holds because `selection` was already `nil` on
    /// entry (armed) and stays untouched throughout.
    public func tapCell(row: Int, column: Int) async {
        guard (0..<Board.dimension).contains(row),
              (0..<Board.dimension).contains(column) else { return }
        guard let armed = armedDigit else {
            select(row: row, column: column)
            return
        }
        let index = Board.index(row: row, column: column)
        let cellDigit = board.digit(atIndex: index)
        let isEmpty = cellDigit == nil
        let isArmedMatch = !isEmpty && !board.givenMask[index] && cellDigit == armed
        guard isEmpty || isArmedMatch else {
            fireArmedMismatchFeedback()
            return
        }
        let coord = GridCoordinate(row: row, column: column)
        if pencilMode {
            await toggleNote(armed, at: coord)
        } else if isEmpty {
            await placeDigit(armed, at: coord)
        } else {
            await placeDigit(nil, at: coord)
        }
    }
}
