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
// `.empty` is rendered as `Color.clear` by `DailyHubShellView`. Sudoku's
// existing precedent surfaces the empty case via `.alert(...)` on the
// caller, not via inline copy in the grid; Minesweeper can opt into the
// same pattern or overlay its own empty view at the call site. If a
// future consumer asks for a caller-provided empty builder, add it then.

public enum HubLoadState<Item: Hashable & Sendable>: Sendable, Equatable {
    case idle
    case loading
    case loaded([Item])
    case empty
    case failed(String)
}
