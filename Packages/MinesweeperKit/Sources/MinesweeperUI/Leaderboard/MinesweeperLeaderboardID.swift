// MinesweeperLeaderboardID — per-difficulty DAILY leaderboard identifiers.
//
// Mirrors Sudoku's `SudokuEngine.LeaderboardID` (#291) EXACTLY: one recurring
// daily leaderboard per difficulty, `.v1`-suffixed (any future board-generator
// bump opens a new family so v1- and v2-generated times never mix into one
// global ranking — same rule as Sudoku's daily families).
//
// Difficulty-name mapping: MS's engine difficulty enum is
// beginner/intermediate/expert, but the leaderboard ID *segment* uses Sudoku's
// easy/medium/hard so the two apps' Config shapes are byte-identical (the id is
// opaque to players — only the localized title, which DOES say
// Beginner/Intermediate/Expert, is shown). Mapping:
//   .beginner     → easy    → com.wei18.minesweeper.leaderboard.easy.daily.v1
//   .intermediate → medium  → com.wei18.minesweeper.leaderboard.medium.daily.v1
//   .expert       → hard    → com.wei18.minesweeper.leaderboard.hard.daily.v1
//
// These IDs MUST stay byte-equal to ASCRegister's
// `Config.leaderboards(for: .minesweeper)` — enforced by
// `ASCRegisterTests/ConfigConsistencyTests.minesweeperLeaderboardIDs`.
//
// NOTE: ASC registration of these 3 leaderboard IDs (App Store Connect Game
// Center catalog) is a separate user-owned / ASCRegister `apply` step.

public import MinesweeperEngine

public enum MinesweeperLeaderboardID {

    /// Bundle-id-rooted prefix shared by all 3 daily leaderboards.
    /// Must equal `Config.GCApp.minesweeper.leaderboardPrefix` in ASCRegister.
    public static let prefix = "com.wei18.minesweeper.leaderboard"

    /// Current generator family suffix. Bumped alongside any board-generator
    /// version change (mirrors Sudoku's `versionSuffix`).
    public static let versionSuffix = "v1"

    public static let easyDaily = "\(prefix).easy.daily.\(versionSuffix)"
    public static let mediumDaily = "\(prefix).medium.daily.\(versionSuffix)"
    public static let hardDaily = "\(prefix).hard.daily.\(versionSuffix)"

    /// All 3 daily leaderboard IDs in difficulty order
    /// (beginner/easy → intermediate/medium → expert/hard).
    public static let allDaily: [String] = [
        easyDaily,
        mediumDaily,
        hardDaily,
    ]

    /// Maps an MS engine difficulty to its daily leaderboard identifier.
    /// Exhaustive on `Difficulty` so a new difficulty case fails to compile
    /// rather than silently dropping its score.
    public static func daily(for difficulty: Difficulty) -> String {
        switch difficulty {
        case .beginner: return easyDaily
        case .intermediate: return mediumDaily
        case .expert: return hardDaily
        }
    }
}
