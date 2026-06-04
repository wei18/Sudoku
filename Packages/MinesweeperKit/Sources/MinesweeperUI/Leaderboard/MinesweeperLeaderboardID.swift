// MinesweeperLeaderboardID — per-difficulty best-time leaderboard identifiers.
//
// Mirrors Sudoku's `SudokuEngine.LeaderboardID` (#291). One best-time
// leaderboard per difficulty; the `.v1` suffix is mandatory — any future
// bump of the board generator opens a new leaderboard family so v1-generated
// and v2-generated times never mix into one global ranking (same rule as
// Sudoku's daily families).
//
// MS has no engine-level shared-identifier file (SudokuEngine hosts Sudoku's
// because ASCRegister also reads them); these MS IDs are UI-layer config
// consumed only by `MinesweeperGameViewModel` (submit-on-win) and the
// `MinesweeperGameCenterDashboard`.
//
// NOTE: ASC registration of these 3 leaderboard IDs (App Store Connect Game
// Center catalog) is a separate user-owned / ASCRegister step — not done here.

public import MinesweeperEngine

public enum MinesweeperLeaderboardID {

    /// Bundle-id-rooted prefix shared by all best-time leaderboards.
    public static let prefix = "com.wei18.minesweeper.leaderboard"

    /// Current generator family suffix. Bumped alongside any board-generator
    /// version change (mirrors Sudoku's `versionSuffix`).
    public static let versionSuffix = "v1"

    public static let beginnerBestTime = "\(prefix).beginner.besttime.\(versionSuffix)"
    public static let intermediateBestTime = "\(prefix).intermediate.besttime.\(versionSuffix)"
    public static let expertBestTime = "\(prefix).expert.besttime.\(versionSuffix)"

    /// All 3 best-time leaderboard IDs in difficulty order
    /// (beginner → intermediate → expert).
    public static let allBestTime: [String] = [
        beginnerBestTime,
        intermediateBestTime,
        expertBestTime,
    ]

    /// Maps a difficulty to its best-time leaderboard identifier. Exhaustive
    /// on `Difficulty` so a new difficulty case fails to compile rather than
    /// silently dropping its score.
    public static func bestTime(for difficulty: Difficulty) -> String {
        switch difficulty {
        case .beginner: return beginnerBestTime
        case .intermediate: return intermediateBestTime
        case .expert: return expertBestTime
        }
    }
}
