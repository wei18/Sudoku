// CompletionViewModel — post-solve completion state (#698).
//
// #698: the leaderboard-slice fetch/present machine (`CompletionState`,
// `bootstrap()`, `retry()`, the leaderboard-CTA present method, the
// `GameCenterClient` dependency) was deleted — the completion popup has
// hardcoded `state: .hidden`
// since v2.6 (SDD-003 Epic 4) and never rendered it. `leaderboardId`/`puzzleId`
// stay: they are cheap data fields still asserted by tests and unrelated to the
// deleted rendering machinery (real GC score submission is a fully separate
// path — `GameCenterSink`, driven by `TelemetryEvent.puzzleCompleted`).

public import Foundation

@MainActor
@Observable
public final class CompletionViewModel {

    public let puzzleId: String
    public let elapsedSeconds: Int
    /// Cumulative mistake count forwarded from `GameViewModel.mistakeCount`
    /// (SDD-003 Epic 4). Displayed in the completion popup hero card.
    public let mistakeCount: Int
    /// Leaderboard this solve belongs to, or `nil` when the puzzle has no
    /// associated board (Practice solves — issue #381).
    public let leaderboardId: String?

    public init(
        puzzleId: String,
        elapsedSeconds: Int,
        mistakeCount: Int,
        leaderboardId: String?
    ) {
        self.puzzleId = puzzleId
        self.elapsedSeconds = elapsedSeconds
        self.mistakeCount = mistakeCount
        self.leaderboardId = leaderboardId
    }
}
