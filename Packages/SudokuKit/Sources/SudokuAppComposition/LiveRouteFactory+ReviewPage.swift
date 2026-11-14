// LiveRouteFactory+ReviewPage — the pushed `.completion` review route's
// regular-width page title (#1049). Minesweeper mirrors this in its own
// `LiveRouteFactory+ReviewPage.swift`; only the route payload differs.

internal import GameShellUI
internal import SudokuEngine

extension LiveRouteFactory {
    /// `.pushedPage` titled "<Difficulty> · <day>" for a Daily puzzleId
    /// (`"YYYY-MM-DD-<difficulty>"`, `PuzzleIdentity.daily`); `.overlay`
    /// for anything else, which this route never receives.
    static func reviewPresentation(puzzleId: String) -> CompletionPresentation {
        guard let dash = puzzleId.lastIndex(of: "-"),
              let difficulty = Difficulty(rawValue: String(puzzleId[puzzleId.index(after: dash)...])),
              let day = UTCDay.date(from: String(puzzleId[..<dash]))
        else { return .overlay }
        return .pushedPage(CompletionPageTitle(difficultyKey: difficulty.rawValue.capitalized, day: day))
    }
}
