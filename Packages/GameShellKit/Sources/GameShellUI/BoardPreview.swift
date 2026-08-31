// BoardPreview — game-agnostic board snapshot for resume/thumbnail surfaces
// (#1017; design.md §3.6 ⚠️ 型別約束).
//
// Lives in GameShellKit (zero dependencies, D2 in design.md §8.2): the shell
// must never see `Persistence`-shaped types. `ResumeCandidate<Route>`
// (`GameAppKit`, which DOES depend on Persistence-shaped data) references
// this value type instead of vice versa, so a shell view that renders a
// thumbnail only ever needs to know `BoardPreview` — no game-specific saved
// format leaks into the shell.
//
// Carries just enough to draw a density/progress thumbnail (#1021's job, not
// this issue's): a grid shape + a per-cell coarse classification. Neither app
// needs anything richer than `CellMark` to render "how filled-in is this
// board" — actual digits / mine counts stay in the game engines.
//
// Degrade contract (design.md §3.6, last line): a per-app mapper builds this
// from its own saved payload and returns `nil` on anything malformed —
// resume must never be blocked by a broken/missing preview.

public struct BoardPreview: Sendable, Equatable {
    public let columns: Int
    public let rows: Int
    public let cells: [CellMark]

    /// Fails (returns `nil`) rather than trapping when `cells.count` doesn't
    /// match `columns * rows` — malformed per-app data degrades to "no
    /// preview", it never crashes the resume pill.
    public init?(columns: Int, rows: Int, cells: [CellMark]) {
        guard columns > 0, rows > 0, cells.count == columns * rows else { return nil }
        self.columns = columns
        self.rows = rows
        self.cells = cells
    }
}

/// Coarse, game-agnostic per-cell classification.
///
/// Mapping per app (design.md §3.6):
/// - Sudoku: given clue → `.given`, user-entered digit → `.filled`, blank → `.empty`.
/// - Minesweeper: hidden → `.empty`, revealed → `.filled`, flagged → `.marked`.
public enum CellMark: Sendable, Equatable {
    case empty
    case given
    case filled
    case marked
}
