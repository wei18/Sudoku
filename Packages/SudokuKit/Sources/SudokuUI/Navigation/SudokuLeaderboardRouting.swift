// SudokuLeaderboardRouting — Daily-puzzle classification + leaderboard-id
// resolution, extracted from `LiveRouteFactory` (#639) so it can stay in
// SudokuUI while the concrete factory moves to SudokuAppComposition (aligning
// with the 2048/MS canonical shape, SDD-006 §2). Both `BoardView+Completion`
// (SudokuUI) and `LiveRouteFactory` (now SudokuAppComposition) call these pure
// functions, so they must live in SudokuUI — the module both can reach without
// a dependency cycle. `public` so the composition-side factory can call them.

internal import GameCenterClient
internal import SudokuEngine

public enum SudokuLeaderboardRouting {
    /// A puzzleId is a Daily unless it carries the practice prefix — same
    /// encoding `BoardLoaderView.identity(from:)` relies on. The reminder primer
    /// is offered only after a Daily solve (proposal §5.1; flow S02).
    public static func isDaily(puzzleId: String) -> Bool {
        !puzzleId.hasPrefix("practice-")
    }

    /// Leaderboard id this `puzzleId` submits to, or `nil` when it has none.
    /// Issue #381: the Completion screen must post to the board matching the
    /// solved difficulty, not always daily-easy. Practice puzzles have no
    /// leaderboard (`LeaderboardKind` has no practice case) → `nil`.
    ///
    /// Mirrors `PuzzleIdentity`'s encoding: every id ends with the
    /// `Difficulty.rawValue` suffix (`-easy` / `-medium` / `-hard`); Daily ids
    /// have no `practice-` prefix. Only Daily ids resolve to a board.
    public static func leaderboardId(forPuzzleId puzzleId: String) -> String? {
        guard isDaily(puzzleId: puzzleId) else { return nil }
        let kind: LeaderboardKind
        switch puzzleId {
        case let id where id.hasSuffix("-\(Difficulty.easy.rawValue)"):
            kind = .dailyEasy
        case let id where id.hasSuffix("-\(Difficulty.medium.rawValue)"):
            kind = .dailyMedium
        case let id where id.hasSuffix("-\(Difficulty.hard.rawValue)"):
            kind = .dailyHard
        default:
            return nil
        }
        return LeaderboardIDs.id(for: kind)
    }
}
