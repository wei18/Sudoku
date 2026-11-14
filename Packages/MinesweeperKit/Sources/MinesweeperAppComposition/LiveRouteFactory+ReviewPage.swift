// LiveRouteFactory+ReviewPage — the pushed `.completion` review route's
// regular-width page title (#1049). Sudoku mirrors this in its own
// `LiveRouteFactory+ReviewPage.swift`; only the route payload differs.

internal import GameShellUI
internal import MinesweeperEngine
internal import MinesweeperGameState
internal import MinesweeperUI

extension LiveRouteFactory {
    /// `.pushedPage` titled "<Difficulty> · <day>" for a Daily review whose
    /// `day` the hub resolved at push time; `.overlay` otherwise, so the
    /// title never reads the wall clock.
    static func reviewPresentation(difficulty: Difficulty, mode: GameMode, day: String?) -> CompletionPresentation {
        guard mode == .daily, let day, let date = UTCDay.date(from: day) else { return .overlay }
        return .pushedPage(CompletionPageTitle(difficultyKey: difficulty.rawValue.capitalized, day: date))
    }
}
