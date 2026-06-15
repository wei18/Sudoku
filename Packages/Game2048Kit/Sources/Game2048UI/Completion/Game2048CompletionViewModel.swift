// Game2048CompletionViewModel — post-game state for the 2048 Completion surface.
//
// Mirrors MinesweeperCompletionViewModel but adapted for 2048's OQ-004-3:
//   - stuck = end-of-run (no "won" / "lost" distinction — just "game over")
//   - outcome shows score + reachedTarget badge
//   - GC: no leaderboard slice to show post-game (the daily ranking is
//     viewable from Home Leaderboard, not from the completion overlay)
//   - CTA: Close only (no Retry — run is over; return to hub for a new game)
//
// Constructed by `LiveRouteFactory` which passes the board's final snapshot.

public import Foundation
public import GameCenterClient

@MainActor
@Observable
public final class Game2048CompletionViewModel {

    public let score: Int
    public let moveCount: Int
    public let elapsedSeconds: Int
    public let reachedTarget: Bool

    public init(
        score: Int,
        moveCount: Int,
        elapsedSeconds: Int,
        reachedTarget: Bool
    ) {
        self.score = score
        self.moveCount = moveCount
        self.elapsedSeconds = elapsedSeconds
        self.reachedTarget = reachedTarget
    }
}
