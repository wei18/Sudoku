// MinesweeperCompletionViewModel — post-game completion state (#292 / #698).
//
// #698: the leaderboard-slice fetch/present machine (`MinesweeperCompletionState`,
// `bootstrap()`, `retry()`, the leaderboard-CTA present method, the
// `GameCenterClient` dependency) was deleted — the completion popup has
// hardcoded `state: .hidden`
// since v2.6 (SDD-003 Epic 4) and never rendered it. `didWin`/`leaderboardId`
// stay: they are cheap data fields the hero + snapshot tests still use and are
// unrelated to the deleted rendering machinery (real GC score submission is a
// fully separate path — `MinesweeperGameViewModel.submitWinIfWon()`).

public import Foundation

@MainActor
@Observable
public final class MinesweeperCompletionViewModel {

    /// `true` on a win, `false` on a loss. Drives the hero (You won / Boom).
    public let didWin: Bool
    public let elapsedSeconds: Int
    public let leaderboardId: String

    public init(
        didWin: Bool,
        elapsedSeconds: Int,
        leaderboardId: String
    ) {
        self.didWin = didWin
        self.elapsedSeconds = elapsedSeconds
        self.leaderboardId = leaderboardId
    }
}
