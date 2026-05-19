// LeaderboardIDs — single source of truth for the App Store Connect
// leaderboard ID format (design.md §How.3.1 + §How.4.5).
//
// `.v1` suffix is mandatory: every bump of `GeneratorVersion` MUST open a
// new leaderboard family so v1-generated and v2-generated puzzle times do
// not get mixed into one global ranking. Tests freeze the exact strings.

public enum LeaderboardIDs {

    /// Bundle-id-rooted prefix shared by all 3 daily leaderboards.
    public static let dailyPrefix = "com.wei18.sudoku.leaderboard"
    /// Current generator family suffix. Bumped alongside `GeneratorVersion`.
    public static let versionSuffix = "v1"

    public static func id(for kind: LeaderboardKind) -> String {
        let difficulty: String
        switch kind {
        case .dailyEasy: difficulty = "easy"
        case .dailyMedium: difficulty = "medium"
        case .dailyHard: difficulty = "hard"
        }
        return "\(dailyPrefix).\(difficulty).daily.\(versionSuffix)"
    }
}
