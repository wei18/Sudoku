// GameCenterIdentifiers — single source-of-truth for all Game Center
// identifier strings shared by:
//   - `GameCenterClient` (runtime submit + auth + achievement reporting)
//   - `ASCRegister` (App Store Connect API provisioning CLI)
//
// Lives in SudokuEngine — the deepest leaf module both targets can reach —
// per the pattern set by `UTCDay` in PR #127. Resolves issue #66 (M6):
// the previous arrangement kept duplicate strings in `GameCenterClient/
// LeaderboardIDs.swift` and `ASCRegister/Config.swift`, reconciled by
// `ConfigConsistencyTests`. With a single source the consistency check
// is structural-by-construction.
//
// Domain layering note: SudokuEngine is otherwise puzzle-mechanics-focused
// and holds no Game Center semantics. We host the *identifier strings*
// only — no submission logic, no `LeaderboardKind` enum, no auth state.
// The mapping `LeaderboardKind → identifier string` stays in
// `GameCenterClient/LeaderboardIDs.swift` because `LeaderboardKind` itself
// is a GameCenterClient public type.

public import Foundation

// MARK: - Leaderboard IDs (design.md §How.3.1)

/// 3 daily leaderboard identifiers. `.v1` suffix is mandatory: every bump
/// of `GeneratorVersion` MUST open a new leaderboard family so v1-generated
/// and v2-generated puzzle times do not get mixed into one global ranking
/// (§How.4.5).
public enum LeaderboardID {

    /// Bundle-id-rooted prefix shared by all 3 daily leaderboards.
    public static let dailyPrefix = "com.wei18.sudoku.leaderboard"

    /// Current generator family suffix. Bumped alongside `GeneratorVersion`.
    public static let versionSuffix = "v1"

    public static let dailyEasy = "\(dailyPrefix).easy.daily.\(versionSuffix)"
    public static let dailyMedium = "\(dailyPrefix).medium.daily.\(versionSuffix)"
    public static let dailyHard = "\(dailyPrefix).hard.daily.\(versionSuffix)"

    /// All 3 daily leaderboard IDs in design.md §How.3.1 table order
    /// (easy → medium → hard).
    public static let allDaily: [String] = [dailyEasy, dailyMedium, dailyHard]
}

// MARK: - Achievement IDs (design.md §How.3.2)

/// 8 v1 achievements. Short IDs are emitted by `AchievementEvaluator`;
/// the `prefix` is applied at submit time by `GameCenterSink` and as the
/// full ASC resource ID by `ASCRegister`.
public enum AchievementID {

    /// Achievement ID prefix per §How.3.2. Applied at submit time.
    public static let prefix = "com.wei18.sudoku.achievement."

    public static let firstPuzzle = "first_puzzle"
    public static let dailyCompleteOne = "daily.complete_one"
    public static let dailyStreak3 = "daily.streak_3"
    public static let dailyStreak7 = "daily.streak_7"
    public static let practiceComplete10 = "practice.complete_10"
    public static let practiceComplete100 = "practice.complete_100"
    public static let hardMaster = "hard.master"
    public static let dailySweep = "daily.sweep"

    /// All 8 short IDs in design.md §How.3.2 table order.
    public static let allShortIds: [String] = [
        firstPuzzle,
        dailyCompleteOne,
        dailyStreak3,
        dailyStreak7,
        practiceComplete10,
        practiceComplete100,
        hardMaster,
        dailySweep,
    ]

    /// Prepends `prefix` to a short id to produce the full ASC resource id.
    public static func fullId(_ shortId: String) -> String {
        prefix + shortId
    }
}
