// MinesweeperAchievementID — the 11 owner-approved MS achievement short IDs
// (issue #700, owner comment 2026-07-06).
//
// Mirrors `SudokuEngine.AchievementID` / `MinesweeperLeaderboardID`'s shape:
// short IDs are emitted by `MinesweeperAchievementEvaluator`; `prefix` is
// applied at submit time by `MinesweeperGameViewModel+EvaluateAchievements`
// and as the full ASC resource ID by `ASCRegister` (`Config.GCApp.minesweeper`).
//
// #700 (owner decision): MS-native — deliberately NOT wired through the
// shared `TelemetryEvent` / `makeCompletionSinks` pipeline, same precedent as
// `MinesweeperLeaderboardID` / `MinesweeperPersonalRecordStore` (#699).

public enum MinesweeperAchievementID {

    /// Achievement ID prefix. Applied at submit time.
    public static let prefix = "com.wei18.minesweeper.achievement."

    // MARK: Starter

    /// First Sweep — first win, any mode.
    public static let firstSweep = "first_sweep"
    /// Daily Debut — first daily win.
    public static let dailyDebut = "daily.complete_one"

    // MARK: Volume (progressive, both modes combined)

    public static let winsComplete10 = "wins.complete_10"
    public static let winsComplete50 = "wins.complete_50"
    public static let winsComplete200 = "wins.complete_200"

    // MARK: Difficulty

    /// Expert Cleared — first Expert win, any mode.
    public static let expertFirstWin = "expert.first_win"
    /// Full Spectrum — at least one daily win on each of the three difficulties.
    public static let dailyFullSpectrum = "daily.full_spectrum"

    // MARK: Skill

    /// No Flags Needed — win without placing a single flag.
    public static let skillNoFlags = "skill.no_flags"
    /// Lightning Sweep — Expert win under 3 minutes.
    public static let skillLightningExpert = "skill.lightning_expert"

    // MARK: Streak

    public static let dailyStreak7 = "daily.streak_7"
    public static let dailyStreak30 = "daily.streak_30"

    /// All 11 short IDs. Order mirrors the owner-approved table (issue #700).
    public static let allShortIds: [String] = [
        firstSweep,
        dailyDebut,
        winsComplete10,
        winsComplete50,
        winsComplete200,
        expertFirstWin,
        dailyFullSpectrum,
        skillNoFlags,
        skillLightningExpert,
        dailyStreak7,
        dailyStreak30,
    ]

    /// Prepends `prefix` to a short id to produce the full ASC/GameKit resource id.
    public static func fullId(_ shortId: String) -> String {
        prefix + shortId
    }
}
