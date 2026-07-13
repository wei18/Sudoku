// HubLoadState — generic load-state enum shared by Daily-style hubs.
//
// Lifted out of SudokuKit's `DailyHubState` (which carried Sudoku's
// `DailyCard` shape) so a second game can reuse the same five-state
// machine — idle / loading / loaded / empty / failed — without taking a
// dependency on Sudoku types.
//
// Semantic map (Sudoku → GameShellUI):
//   .idle        ←  .idle
//   .loading     ←  .loading
//   .loaded      ←  .loaded
//   .empty       ←  .exhausted  (Sudoku's "no puzzle for today" branch;
//                                Minesweeper's "no daily seed" branch)
//   .failed      ←  .failed
//
// `.empty` is rendered by `DailyHubShellView`'s caller-provided `empty`
// builder (defaults to `Color.clear` if the caller doesn't supply one).
// #768: Sudoku's `.exhausted` now maps here and supplies an inline
// icon+message+action block, matching the visual language of `.failed`.
// Minesweeper never reaches `.empty` (its daily generation is pure and
// non-throwing) and relies on the default.

public enum HubLoadState<Item: Hashable & Sendable>: Sendable, Equatable {
    case idle
    case loading
    case loaded([Item])
    case empty
    case failed(String)
}
